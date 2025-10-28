(async () => {
  const connectBtn = document.getElementById('connectBtn');
  const dumpBtn = document.getElementById('dumpBtn');
  const clearLogBtn = document.getElementById('clearLogBtn');
  const logEl = document.getElementById('log');
  const accelXEl = document.getElementById('accelX');
  const accelYEl = document.getElementById('accelY');
  const accelZEl = document.getElementById('accelZ');

  let device = null;
  let dumping = false;
  // throttle timestamps
  let _lastAccUpdateTime = 0; // ms
  const ACC_UPDATE_MS = 33; // ~30Hz updates for accel DOM

  // Force using accelerometer data only (true = ignore gyro channels)
  // 加速度センサーのみを使うよう強制するフラグ（true の場合、ジャイロは無視します）
  const FORCE_ACCEL_ONLY = true;

  // Joy‑Con vendor/product filters
  const filters = [
    { vendorId: 0x057e, productId: 0x2006 }, // Joy‑Con L
    { vendorId: 0x057e, productId: 0x2007 }  // Joy‑Con R
  ];

  function prependLog(text) {
    // Rate-limited DOM log updates to avoid thrashing the UI when reports are frequent.
    try {
      const now = performance.now();
      if (!window._joycon_logState) window._joycon_logState = { buf: [], last: 0 };
      const s = window._joycon_logState;
      s.buf.push(text);
      // flush at most every 100ms
      const LOG_UPDATE_MS = 100;
      if (now - s.last > LOG_UPDATE_MS) {
        // prepend buffered lines (most recent first)
        const toPrepend = s.buf.reverse().join('\n');
        logEl.textContent = toPrepend + "\n" + logEl.textContent;
        s.buf.length = 0;
        s.last = now;
      }
    } catch (e) {
      // fallback
      try { logEl.textContent = text + "\n" + logEl.textContent; } catch(e){}
    }
  }
  clearLogBtn.addEventListener('click', () => { logEl.textContent = "-- logs --"; });

  // Helper: sendReport where arr[0] is reportId
  async function sendOutputWithReportId(arr) {
    if (!device || !device.opened) return;
    const reportId = arr[0];
    const data = new Uint8Array(arr.slice(1));
    try {
      await device.sendReport(reportId, data);
      prependLog(`SENT reportId=0x${reportId.toString(16)} data=${Array.from(data).map(b=>b.toString(16).padStart(2,'0')).join(' ')}`);
    } catch (e) {
      console.warn("sendReport failed", e);
      prependLog(`sendReport failed: ${e}`);
    }
  }

  // Initialization sequences (from Ruby example)
  const initSeqs = [
    [0x01,0x00,0x00,0x01,0x40,0x40,0x00,0x01,0x40,0x40,0x40,0x01],
    [0x01,0x01,0x00,0x01,0x40,0x40,0x00,0x01,0x40,0x40,0x03,0x30]
  ];

  // --- ジャンプ検出ロジック ---
  const accelHistory = [];
  const MAX_HISTORY = 40;
  // 応答性の改善: フィルタ応答を速めつつ閾値をやや下げ、クールダウンを短めに調整
  // 実機の g 値はおおむね 0〜3 程度なので、閾値は現実的な値 (約 0.8〜1.5 G) にする
  let JUMP_THRESHOLD = 0.9; // G 単位の差分閾値（調整済み）
  let JUMP_ABS_THRESHOLD = 0.9; // zBaseline からの絶対差による閾値
  let jumpCooldown = 0;
  // default cooldown: 30 frames ≈ 0.5s at 60fps
  let JUMP_COOLDOWN_FRAMES = 30; // frames
  let JUMP_COOLDOWN_MS = Math.round(JUMP_COOLDOWN_FRAMES * (1000/60)); // milliseconds cooldown
  let lastJumpTime = 0;

  function canTriggerJump() {
    return (Date.now() - lastJumpTime) >= JUMP_COOLDOWN_MS;
  }
  // Immediate Z-axis spike trigger (lower-latency fallback)
  const Z_AXIS_USE_RAW = false; // false = use scaled g units (zG), true = use raw 16-bit (zr_raw)
  let RAW_Z_TRIGGER_ENABLE = false; // Disable immediate Z-axis trigger
  let Z_G_IMMEDIATE = 2.8; // g units magnitude to consider immediate trigger（厳しめ）
  let Z_RAW_IMMEDIATE = 2800; // raw units magnitude to consider immediate trigger（厳しめ）
  let Z_DELTA_IMMEDIATE = 1.6; // g change between frames considered an immediate spike（大きめ）
  let prevZFiltered = null;
  // オプション: Y 軸の強い値で直接ジャンプをトリガーする（ユーザー要望）。
  // デフォルトは ON にして、Y 軸のしきい値でジャンプをトリガーする（ユーザー要望: y>7G）
  let USE_Y_AXIS_TRIGGER = true;
  // Y の解釈: スケール済みの g 単位（yG）か生のセンサー値（yr_raw）かを切り替えます。
  // We'll use scaled g units (yG) directly for a simple threshold.
  let Y_AXIS_USE_RAW = false;
  let Y_G_THRESHOLD = 7.9; // G 単位の閾値をコードで固定
  let Y_RAW_THRESHOLD = 8000; // 生の16-bit単位の閾値（未使用）
  const Y_JUMP_COOLDOWN_FRAMES = 45;
  // enable/disable the history/diff-based detection at runtime for debugging
  let ENABLE_DIFF_DETECTION = true;
  // persistence key for localStorage
  const STORAGE_KEY = 'joycon_tuning_v1';
  // 低域通過フィルタ（指数移動平均）: 生の加速度を滑らかにしてノイズを除去します
  let zFiltered = null;
  let LP_ALPHA = 0.22; // smoothing factor (0..1) — 応答を速くして遅延を減らす
  // keep a filtered Y as well for more robust Y-trigger detection
  let yFiltered = null;
  let prevYFiltered = null;
  // auto-calibration for Y/Z baseline (to handle different orientations)
  let calibrating = false;
  const CALIB_SAMPLES = 120;
  const calibYSamples = [];
  const calibZSamples = [];
  let yBaseline = null;
  let zBaseline = null;
  const magHistory = [];
  const WAVE_MAX = 300;
  let showMagnitude = true;
  const calibMagSamples = [];
  let magBaseline = null;

  // waveform draw throttling
  let _lastWaveTime = 0;
  const WAVE_FPS = 30; // draw waveform at most this many times per second

  // Auto-tune (magnitude-based) vars
  let autoTuneActive = false;
  const AUTO_TUNE_COUNT = 5;
  let autoTuneSamples = [];
  let autoTuneCapturing = false;
  let autoTuneCurrentMax = 0;
  const AUTO_TUNE_START_DELTA = 0.6; // start capture when mag > magBaseline + this
  const AUTO_TUNE_END_DELTA = 0.35; // end capture when mag drops below magBaseline + this

  function pushAccel(zG) {
     // 基本チェック: 無効な数値は無視する
    if (typeof zG !== 'number' || !isFinite(zG)) return;
  // LPF を適用して平滑化
    if (zFiltered === null) zFiltered = zG;
    else zFiltered = zFiltered * (1 - LP_ALPHA) + zG * LP_ALPHA;
    accelHistory.push(zFiltered);
    if (accelHistory.length > MAX_HISTORY) accelHistory.shift();
  // frame-based cooldown removed in favor of time-based cooldown (JUMP_COOLDOWN_MS)
    detectJump();
  }

  // --- Persistence: load/save tuning settings to localStorage ---
  function loadSettings() {
    try {
      if (!window.localStorage) return;
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return;
      const obj = JSON.parse(raw);
  // Y_G_THRESHOLD is intentionally fixed in code; do not override from storage
      if (typeof obj.Y_AXIS_USE_RAW === 'boolean') Y_AXIS_USE_RAW = obj.Y_AXIS_USE_RAW;
      if (typeof obj.ENABLE_DIFF_DETECTION === 'boolean') ENABLE_DIFF_DETECTION = obj.ENABLE_DIFF_DETECTION;
      if (typeof obj.JUMP_THRESHOLD === 'number') JUMP_THRESHOLD = obj.JUMP_THRESHOLD;
      if (typeof obj.JUMP_ABS_THRESHOLD === 'number') JUMP_ABS_THRESHOLD = obj.JUMP_ABS_THRESHOLD;
      if (typeof obj.JUMP_COOLDOWN_FRAMES === 'number') { JUMP_COOLDOWN_FRAMES = obj.JUMP_COOLDOWN_FRAMES; JUMP_COOLDOWN_MS = Math.round(JUMP_COOLDOWN_FRAMES * (1000/60)); }
      if (typeof obj.RAW_Z_TRIGGER_ENABLE === 'boolean') RAW_Z_TRIGGER_ENABLE = obj.RAW_Z_TRIGGER_ENABLE;
      if (typeof obj.LP_ALPHA === 'number') LP_ALPHA = obj.LP_ALPHA;
      prependLog('Loaded saved tuning settings');
    } catch (e) {
      console.warn('loadSettings error', e);
    }
  }

  function saveSettings() {
    try {
      if (!window.localStorage) return;
      const obj = {
        Y_AXIS_USE_RAW,
        ENABLE_DIFF_DETECTION,
        JUMP_THRESHOLD,
        JUMP_ABS_THRESHOLD,
        JUMP_COOLDOWN_FRAMES,
        RAW_Z_TRIGGER_ENABLE,
        LP_ALPHA
      };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(obj));
      prependLog('Saved tuning settings');
    } catch (e) {
      console.warn('saveSettings error', e);
    }
  }

  function detectJump() {
  if (!canTriggerJump()) return;
    if (!ENABLE_DIFF_DETECTION) return; // allow disabling diff-based detection for testing
    if (accelHistory.length < 10) return;
    // recent average vs older average の差を用いた簡易ピーク検出
    const recentN = 2;
      const olderN = Math.min(accelHistory.length - recentN, 8);
    if (olderN <= 0) return;
    const recent = accelHistory.slice(-recentN);
    const older = accelHistory.slice(-recentN - olderN, -recentN);
    const avgRecent = recent.reduce((a,b)=>a+b,0) / recent.length;
    const avgOlder = older.reduce((a,b)=>a+b,0) / older.length;
    const diff = Math.abs(avgRecent - avgOlder);
  // 直近が過去平均より大きく、かつ差分が閾値を超えることを要求（上向きのピークのみ検出）
    // 差分ベースの判定に加えて、キャリブレーションで得た zBaseline からの絶対差でも判定する
    const diffUp = avgRecent - avgOlder;
    const absFromBaseline = (zBaseline !== null) ? (avgRecent - zBaseline) : null;
    if ((diffUp > JUMP_THRESHOLD && avgRecent > avgOlder) || (absFromBaseline !== null && absFromBaseline > JUMP_ABS_THRESHOLD)) {
      // ジャンプ検出：カスタムイベントで通知
      window.dispatchEvent(new CustomEvent('joycon-jump', { detail: { diff, avgRecent, avgOlder } }));
  lastJumpTime = Date.now();
      prependLog(`Jump detected! diff=${diff.toFixed(3)} (recent=${avgRecent.toFixed(3)} older=${avgOlder.toFixed(3)})`);
      // clear recent detection buffers to avoid immediate re-triggers
      clearDetectionState();
    }
  }
  // --- ジャンプ検出ここまで ---

  // clear detection buffers/state after a confirmed jump to avoid immediate re-triggers
  function clearDetectionState() {
    try {
      accelHistory.length = 0;
      magHistory.length = 0;
      autoTuneCapturing = false;
      autoTuneCurrentMax = 0;
      prevZFiltered = null;
      prevYFiltered = null;
      zFiltered = null;
    } catch (e) {
      console.warn('clearDetectionState error', e);
    }
  }

  // ガード: WebHID API が利用可能かをチェック
  if (!navigator || !navigator.hid) {
    prependLog('WebHID API が利用できません。Chrome / Edge の最新で、localhost または HTTPS 上で実行してください。');
    connectBtn.disabled = true;
    connectBtn.textContent = 'WebHID 不可';
  }

  connectBtn.addEventListener('click', async () => {
    try {
      const devices = await navigator.hid.requestDevice({ filters });
      if (!devices || devices.length === 0) {
        prependLog("デバイスが選択されませんでした。");
        return;
      }
      device = devices[0];
      await device.open();
      prependLog(`Connected: ${device.productName} (vendor=0x${device.vendorId.toString(16)} product=0x${device.productId.toString(16)})`);

  // log current thresholds/settings so user can verify what is active
  prependLog(`Settings: Y_G_THRESHOLD=${Y_G_THRESHOLD} Y_AXIS_USE_RAW=${Y_AXIS_USE_RAW} ENABLE_DIFF_DETECTION=${ENABLE_DIFF_DETECTION} JUMP_THRESHOLD=${JUMP_THRESHOLD} RAW_Z_TRIGGER_ENABLE=${RAW_Z_TRIGGER_ENABLE}`);

  // start auto calibration: collect a short baseline while controller is stationary
  calibrating = true;
  calibYSamples.length = 0;
  prependLog('Calibrating sensors for 2s... keep the controller still');

      device.addEventListener('inputreport', (event) => {
        const dv = event.data; // DataView（受信レポート）
        const bytes = new Uint8Array(dv.buffer);

        // Raw dump if enabled
        if (dumping) {
          prependLog(`[reportId=${event.reportId}] head=0x${(bytes[0]||0).toString(16)} data=${Array.from(bytes).map(b=>b.toString(16).padStart(2,'0')).join(' ')}`);
        }

        try {
          if (event.reportId === 0x30 && bytes.length > 18) {
            // 16-bit リトルエンディアンの符号付き整数を取得するヘルパー
            function getSigned16(lowIndex, highIndex) {
              if (lowIndex < 0 || highIndex >= bytes.length) return null;
              let raw = (bytes[highIndex] << 8) | bytes[lowIndex];
              if (raw > 32767) raw -= 65536;
              return raw;
            }

            // 実機ログから推定したパケット内オフセット
            const xr_raw = getSigned16(13,14);
            const yr_raw = getSigned16(15,16);
            const zr_raw = getSigned16(17,18);

            // スケール: 初期値は /4000（必要に応じて /4096 等に調整）
            const scale = 4000;
            const xG = xr_raw !== null ? xr_raw / scale : null;
            const yG = yr_raw !== null ? yr_raw / scale : null;
            const zG = zr_raw !== null ? zr_raw / scale : null;

                    // Throttle DOM updates for accelerometer readouts to reduce main-thread work
                    try {
                      const nowAcc = performance.now();
                      if (nowAcc - _lastAccUpdateTime >= ACC_UPDATE_MS) {
                        if (xG !== null) accelXEl.textContent = xG.toFixed(3);
                        if (yG !== null) accelYEl.textContent = yG.toFixed(3);
                        if (zG !== null) accelZEl.textContent = zG.toFixed(3);
                        _lastAccUpdateTime = nowAcc;
                      }
                    } catch(e) { /* ignore DOM errors */ }

                    // magnitude (vector length) - useful when controller is tilted
                    const mag = (typeof xG === 'number' && typeof yG === 'number' && typeof zG === 'number') ? Math.sqrt(xG*xG + yG*yG + zG*zG) : null;
                    // push to waveform history
                    if (typeof mag === 'number') {
                      magHistory.push(mag);
                      if (magHistory.length > WAVE_MAX) magHistory.shift();
                    }

                    // Immediate Z-axis spike detection for lower-latency jumps
                    if (RAW_Z_TRIGGER_ENABLE && canTriggerJump() && zG !== null) {

  // --- Waveform drawing ---
  function drawWaveform() {
    const canvas = document.getElementById('waveCanvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    // clear
    ctx.fillStyle = '#071018';
    ctx.fillRect(0,0,w,h);

    // determine display range (0..maxG)
    const maxG = 4.0;
    // draw baseline if known
    if (magBaseline !== null) {
      const yb = h - (magBaseline / maxG) * h;
      ctx.strokeStyle = 'rgba(255,255,255,0.08)'; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(0,yb); ctx.lineTo(w,yb); ctx.stroke();
    }

    // draw threshold lines (absolute thresholds relative to baseline)
    if (magBaseline !== null) {
      const tAbs = magBaseline + JUMP_ABS_THRESHOLD;
      const tDiff = magBaseline + JUMP_THRESHOLD;
      const yT = h - (tAbs / maxG) * h;
      const yD = h - (tDiff / maxG) * h;
      ctx.strokeStyle = 'rgba(255,0,0,0.12)'; ctx.beginPath(); ctx.moveTo(0,yT); ctx.lineTo(w,yT); ctx.stroke();
      ctx.strokeStyle = 'rgba(255,165,0,0.12)'; ctx.beginPath(); ctx.moveTo(0,yD); ctx.lineTo(w,yD); ctx.stroke();
    }

    // draw history line
    if (magHistory.length > 1) {
      ctx.strokeStyle = '#6ff'; ctx.lineWidth = 1.5;
      ctx.beginPath();
      for (let i=0;i<magHistory.length;i++) {
        const gx = i / (WAVE_MAX-1) * w;
        const gy = h - (Math.min(magHistory[i], maxG) / maxG) * h;
        if (i===0) ctx.moveTo(gx,gy); else ctx.lineTo(gx,gy);
      }
      ctx.stroke();
    }
  }

  // animation loop for waveform
  (function waveLoop(){
    const now = performance.now();
    if (now - _lastWaveTime >= (1000 / WAVE_FPS)) {
      drawWaveform();
      _lastWaveTime = now;
    }
    requestAnimationFrame(waveLoop);
  })();
                      // compute delta from previous filtered Z (or previous raw if null)
                      const zCurr = zG;
                      const zPrev = (prevZFiltered !== null) ? prevZFiltered : zCurr;
                      const dz = Math.abs(zCurr - zPrev);
                      // magnitude check (use raw or g units depending on config)
                      let magTriggered = false;
                      if (Z_AXIS_USE_RAW) {
                        if (zr_raw !== null && Math.abs(zr_raw) >= Z_RAW_IMMEDIATE) magTriggered = true;
                      } else {
                        if (Math.abs(zCurr) >= Z_G_IMMEDIATE) magTriggered = true;
                      }
                      if (dz >= Z_DELTA_IMMEDIATE && magTriggered) {
                        window.dispatchEvent(new CustomEvent('joycon-jump', { detail: { source: 'z-immediate', raw: zr_raw, g: zG } }));
                        lastJumpTime = Date.now();
                        prependLog(`Z-immediate trigger dz=${dz.toFixed(3)} g=${zG.toFixed(3)}`);
                        // clear detection buffers/state so we don't immediately re-trigger
                        clearDetectionState();
                      }
                      prevZFiltered = zCurr;
                    }

                    // update filtered Y for derivative-based trigger
                    if (typeof yG === 'number') {
                      if (calibrating) {
                        calibYSamples.push(yG);
                        if (typeof zG === 'number') calibZSamples.push(zG);
                        if (typeof mag === 'number') calibMagSamples.push(mag);
                        if (calibYSamples.length >= CALIB_SAMPLES && calibZSamples.length >= CALIB_SAMPLES && calibMagSamples.length >= CALIB_SAMPLES) {
                          // compute medians
                          const sortedY = calibYSamples.slice().sort((a,b)=>a-b);
                          const midY = Math.floor(sortedY.length/2);
                          yBaseline = (sortedY.length % 2 === 1) ? sortedY[midY] : (sortedY[midY-1] + sortedY[midY]) / 2;
                          const sortedZ = calibZSamples.slice().sort((a,b)=>a-b);
                          const midZ = Math.floor(sortedZ.length/2);
                          zBaseline = (sortedZ.length % 2 === 1) ? sortedZ[midZ] : (sortedZ[midZ-1] + sortedZ[midZ]) / 2;
                          const sortedM = calibMagSamples.slice().sort((a,b)=>a-b);
                          const midM = Math.floor(sortedM.length/2);
                          magBaseline = (sortedM.length % 2 === 1) ? sortedM[midM] : (sortedM[midM-1] + sortedM[midM]) / 2;
                          calibrating = false;
                          prependLog(`Calibration complete: yBaseline=${yBaseline.toFixed(3)} G zBaseline=${(zBaseline!==null?zBaseline.toFixed(3):'n/a')} G magBaseline=${(magBaseline!==null?magBaseline.toFixed(3):'n/a')} G`);
                        }
                      }
                      if (yFiltered === null) { yFiltered = yG; prevYFiltered = yG; }
                      else { prevYFiltered = yFiltered; yFiltered = yFiltered * (1 - LP_ALPHA) + yG * LP_ALPHA; }
                    }

                    // Auto-Tune: collect magnitude peaks when enabled
                    if (autoTuneActive && typeof mag === 'number') {
                      // ensure we have a baseline
                      const base = (magBaseline !== null) ? magBaseline : 0;
                      if (!autoTuneCapturing) {
                        if (mag > base + AUTO_TUNE_START_DELTA) {
                          autoTuneCapturing = true;
                          autoTuneCurrentMax = mag;
                          prependLog('Auto-Tune: detected start of a jump capture');
                        }
                      } else {
                        if (mag > autoTuneCurrentMax) autoTuneCurrentMax = mag;
                        if (mag < base + AUTO_TUNE_END_DELTA) {
                          // commit peak
                          const peakDelta = autoTuneCurrentMax - base;
                          autoTuneSamples.push(peakDelta);
                          autoTuneCapturing = false;
                          prependLog(`Auto-Tune: captured peak delta=${peakDelta.toFixed(3)} G (${autoTuneSamples.length}/${AUTO_TUNE_COUNT})`);
                          if (autoTuneSamples.length >= AUTO_TUNE_COUNT) {
                            // finish auto-tune
                            autoTuneActive = false;
                            // compute median
                            const s = autoTuneSamples.slice().sort((a,b)=>a-b);
                            const m = Math.floor(s.length/2);
                            const medianPeak = (s.length%2===1)?s[m]:(s[m-1]+s[m])/2;
                            // set thresholds conservatively
                            JUMP_ABS_THRESHOLD = Math.max(0.4, medianPeak * 0.55);
                            JUMP_THRESHOLD = Math.max(0.35, medianPeak * 0.45);
                            prependLog(`Auto-Tune complete. medianPeak=${medianPeak.toFixed(3)} => JUMP_ABS_THRESHOLD=${JUMP_ABS_THRESHOLD.toFixed(3)} JUMP_THRESHOLD=${JUMP_THRESHOLD.toFixed(3)}`);
                            // update UI sliders if present
                            try { document.getElementById('jumpAbsThreshold').value = JUMP_ABS_THRESHOLD; document.getElementById('jumpAbsThresholdVal').textContent = JUMP_ABS_THRESHOLD.toFixed(2); } catch(e){}
                            try { document.getElementById('jumpThreshold').value = JUMP_THRESHOLD; document.getElementById('jumpThresholdVal').textContent = JUMP_THRESHOLD.toFixed(2); } catch(e){}
                            try { document.getElementById('autoTuneStatus').textContent = 'done'; } catch(e){}
                            autoTuneSamples.length = 0;
                          } else {
                            try { document.getElementById('autoTuneStatus').textContent = `captured ${autoTuneSamples.length}`; } catch(e){}
                          }
                        }
                      }
                    }

                    // 設定により、Y 軸の強い値で即時ジャンプをトリガーする
                    // 生の値 (yr_raw) を使うかスケール済みの g 単位 (yG) を使うかを明確に扱う
                    if (USE_Y_AXIS_TRIGGER && canTriggerJump()) {
                      if (Y_AXIS_USE_RAW) {
                        if (typeof yr_raw === 'number' && Math.abs(yr_raw) > Y_RAW_THRESHOLD) {
                          window.dispatchEvent(new CustomEvent('joycon-jump', { detail: { source: 'y-axis-raw', raw: yr_raw, g: yG } }));
                          lastJumpTime = Date.now();
                          prependLog(`Y-axis RAW threshold trigger (raw=${yr_raw} > ${Y_RAW_THRESHOLD})`);
                          clearDetectionState();
                        }
                      } else {
                        if (typeof yG === 'number' && yG > Y_G_THRESHOLD) {
                          window.dispatchEvent(new CustomEvent('joycon-jump', { detail: { source: 'y-axis', raw: yr_raw, g: yG } }));
                          lastJumpTime = Date.now();
                          prependLog(`Y-axis threshold trigger (g=${yG.toFixed(3)} > ${Y_G_THRESHOLD})`);
                          clearDetectionState();
                        }
                      }
                    }

                    // ジャンプ検出用に Z を履歴へプッシュ
                    if (zG !== null) pushAccel(zG);
          }
        } catch (e) {
          console.warn('parse error', e);
        }
      });

      // send init sequences
      for (const seq of initSeqs) {
        await sendOutputWithReportId(seq);
        await new Promise(res => setTimeout(res, 50));
      }

      prependLog("初期化シーケンス送信完了。コントローラを動かしてレポートを確認してください。");
    } catch (err) {
      console.error(err);
      prependLog("接続エラー: " + err);
    }
  });

  dumpBtn.addEventListener('click', () => {
    dumping = !dumping;
    dumpBtn.textContent = dumping ? "Stop Raw Dump" : "Start Raw Dump";
    prependLog("dumping = " + dumping);
  });

  // --- Tuning UI bindings (if present in DOM) ---
  function setupTuningUI() {
    const lp = document.getElementById('lpAlpha');
    const lpVal = document.getElementById('lpAlphaVal');
    if (lp && lpVal) {
      lp.value = LP_ALPHA;
      lpVal.textContent = LP_ALPHA.toFixed(2);
      lp.addEventListener('input', () => { LP_ALPHA = parseFloat(lp.value); lpVal.textContent = LP_ALPHA.toFixed(2); prependLog(`LP_ALPHA=${LP_ALPHA}`); saveSettings(); });
    }

    const jt = document.getElementById('jumpThreshold');
    const jtVal = document.getElementById('jumpThresholdVal');
    if (jt && jtVal) {
      jt.value = JUMP_THRESHOLD;
      jtVal.textContent = JUMP_THRESHOLD.toFixed(2);
      jt.addEventListener('input', () => { JUMP_THRESHOLD = parseFloat(jt.value); jtVal.textContent = JUMP_THRESHOLD.toFixed(2); prependLog(`JUMP_THRESHOLD=${JUMP_THRESHOLD}`); saveSettings(); });
    }

    const ja = document.getElementById('jumpAbsThreshold');
    const jaVal = document.getElementById('jumpAbsThresholdVal');
    if (ja && jaVal) {
      ja.value = JUMP_ABS_THRESHOLD;
      jaVal.textContent = JUMP_ABS_THRESHOLD.toFixed(2);
      ja.addEventListener('input', () => { JUMP_ABS_THRESHOLD = parseFloat(ja.value); jaVal.textContent = JUMP_ABS_THRESHOLD.toFixed(2); prependLog(`JUMP_ABS_THRESHOLD=${JUMP_ABS_THRESHOLD}`); saveSettings(); });
    }

    const jc = document.getElementById('jumpCooldown');
    const jcVal = document.getElementById('jumpCooldownVal');
    if (jc && jcVal) {
      jc.value = JUMP_COOLDOWN_FRAMES;
      jcVal.textContent = JUMP_COOLDOWN_FRAMES;
      jc.addEventListener('input', () => {
        JUMP_COOLDOWN_FRAMES = parseInt(jc.value);
        JUMP_COOLDOWN_MS = Math.round(JUMP_COOLDOWN_FRAMES * (1000/60));
        jcVal.textContent = JUMP_COOLDOWN_FRAMES;
        prependLog(`JUMP_COOLDOWN_FRAMES=${JUMP_COOLDOWN_FRAMES} (${JUMP_COOLDOWN_MS} ms)`);
        saveSettings();
      });
    }

    const rz = document.getElementById('rawZEnable');
    if (rz) {
      rz.checked = RAW_Z_TRIGGER_ENABLE;
      rz.addEventListener('change', () => { RAW_Z_TRIGGER_ENABLE = !!rz.checked; prependLog(`RAW_Z_TRIGGER_ENABLE=${RAW_Z_TRIGGER_ENABLE}`); saveSettings(); });
    }

    // --- Y-axis threshold control (create if not present) ---
    let yControl = document.getElementById('yThreshold');
    if (!yControl) {
      try {
        const panel = document.getElementById('tuningPanel') || document.body;
        const wrapper = document.createElement('div');
        wrapper.style.marginTop = '6px';
        wrapper.innerHTML = `
          <label>Y_G_THRESHOLD (fixed): <span id="yThresholdVal">${Y_G_THRESHOLD}</span></label><br>
          <input id="yThreshold" type="range" min="0" max="16" step="0.1" value="${Y_G_THRESHOLD}" disabled />
        `;
        panel.appendChild(wrapper);
        yControl = document.getElementById('yThreshold');
      } catch(e){ /* ignore DOM insertion errors */ }
    }
    if (yControl) {
      const yVal = document.getElementById('yThresholdVal');
      yControl.value = Y_G_THRESHOLD;
      if (yVal) yVal.textContent = Number(Y_G_THRESHOLD).toFixed(1);
      // Y_G_THRESHOLD is fixed in code; only display the value and keep the control disabled
      if (yControl) yControl.disabled = true;
    }

    // --- Toggle for diff-based detection ---
    let diffToggle = document.getElementById('diffDetectEnable');
    if (!diffToggle) {
      try {
        const panel2 = document.getElementById('tuningPanel') || document.body;
        const w2 = document.createElement('div');
        w2.style.marginTop = '6px';
        w2.innerHTML = `
          <label><input id="diffDetectEnable" type="checkbox" ${ENABLE_DIFF_DETECTION? 'checked': ''} /> Enable diff-based detection</label>
        `;
        panel2.appendChild(w2);
        diffToggle = document.getElementById('diffDetectEnable');
      } catch(e){}
    }
    if (diffToggle) {
      diffToggle.checked = ENABLE_DIFF_DETECTION;
      diffToggle.addEventListener('change', () => { ENABLE_DIFF_DETECTION = !!diffToggle.checked; prependLog(`ENABLE_DIFF_DETECTION=${ENABLE_DIFF_DETECTION}`); saveSettings(); });
    }

    const recal = document.getElementById('recalBtn');
  if (recal) recal.addEventListener('click', () => { calibrating = true; calibYSamples.length = 0; calibZSamples.length = 0; yBaseline = null; zBaseline = null; prependLog('Manual recalibration started — keep controller still'); });

    const resetBtn = document.getElementById('resetBtn');
    if (resetBtn) resetBtn.addEventListener('click', () => {
      LP_ALPHA = 0.22;
      JUMP_THRESHOLD = 0.9;
      JUMP_ABS_THRESHOLD = 0.9;
  JUMP_COOLDOWN_FRAMES = 30;
  JUMP_COOLDOWN_MS = Math.round(JUMP_COOLDOWN_FRAMES * (1000/60));
      RAW_Z_TRIGGER_ENABLE = false;
      Z_G_IMMEDIATE = 2.8;
      Z_DELTA_IMMEDIATE = 1.6;
      // update UI
      if (lp && lpVal) { lp.value = LP_ALPHA; lpVal.textContent = LP_ALPHA.toFixed(2); }
      if (jt && jtVal) { jt.value = JUMP_THRESHOLD; jtVal.textContent = JUMP_THRESHOLD.toFixed(2); }
      if (ja && jaVal) { ja.value = JUMP_ABS_THRESHOLD; jaVal.textContent = JUMP_ABS_THRESHOLD.toFixed(2); }
      if (jc && jcVal) { jc.value = JUMP_COOLDOWN_FRAMES; jcVal.textContent = JUMP_COOLDOWN_FRAMES; }
      if (rz) { rz.checked = RAW_Z_TRIGGER_ENABLE; }
      prependLog('Tuning defaults restored');
      // save defaults to storage
      saveSettings();
    });

    const autoBtn = document.getElementById('autoTuneBtn');
    const autoStatus = document.getElementById('autoTuneStatus');
    if (autoBtn && autoStatus) {
      autoBtn.addEventListener('click', () => {
        autoTuneActive = true;
        autoTuneSamples.length = 0;
        autoTuneCapturing = false;
        autoTuneCurrentMax = 0;
        if (autoStatus) autoStatus.textContent = 'waiting...';
        prependLog('Auto-Tune started: perform 5 clear jump motions now');
      });
    }
  }

  // initialize tuning UI if present
  try { 
    loadSettings();
    setupTuningUI(); 
  } catch (e) { /* ignore if DOM not ready or elements missing */ }

})();
