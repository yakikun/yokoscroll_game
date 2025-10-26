// Minimal port of the Ruby horizontal scroller to HTML5 Canvas + JS
// - Jump input: Space / ArrowUp / 'joycon-jump' custom event from the existing index.js
// - Uses assets in ../img/ (relative to web_yoko/index.html)

(() => {
  try {
    console.log('[game.js] loaded');
  const canvas = document.getElementById('gameCanvas');
  const ctx = canvas.getContext('2d');
  // make canvas size match window size (logical pixels = CSS px)
  let W = window.innerWidth, H = window.innerHeight;
  // how many pixels of free space to keep below the ground
  const GROUND_OFFSET = 140;
  function resizeCanvas() {
    const ratio = window.devicePixelRatio || 1;
    // set CSS size to window size minus margins (50px each side)
    const cssW = Math.max(100, window.innerWidth - 100); // 50px margin left/right
  // reduce bottom area by an extra 50px (user requested) so canvas is 50px shorter vertically
  const cssH = Math.max(100, window.innerHeight - 150); // 50px margin left/right, extra 50px removed from bottom
    canvas.style.width = cssW + 'px';
    canvas.style.height = cssH + 'px';
  // position canvas with 50px inset from each window edge (avoids body padding issues)
  canvas.style.position = 'absolute';
  canvas.style.left = '50px';
  // leave extra space at top for header/UI
  canvas.style.top = '110px';
    // set actual backing store size for high-DPI
  canvas.width = Math.max(1, Math.floor(cssW * ratio));
  canvas.height = Math.max(1, Math.floor(cssH * ratio));
    // scale drawing operations so 1 unit = 1 CSS pixel
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
  W = cssW;
  H = cssH;
    // do not touch `state` here; caller will update state.groundY after state is initialized
  }
  // initial resize will be performed after state is created
  window.addEventListener('resize', () => { resizeCanvas(); });

  // Assets
  const assets = {
    player: '../img/kyara.png'
  };
  const images = {};
  let loaded = 0, toLoad = Object.keys(assets).length;
  for (const k of Object.keys(assets)) {
    const img = new Image();
    img.src = assets[k];
    img.onload = () => { images[k] = img; loaded++; };
    img.onerror = () => { loaded++; console.warn('Failed to load', assets[k]); };
  }

  // Game state (simplified, inspired by main.rb)
  const state = {
    cameraX: 0,
    worldWidth: 10000,
  player: { x: 100, y: 400, w: 32, h: 48, velY: 0, velX: 0, knockbackTimer: 0 },
    gravity: 0.5,
    jumpPower: -12,
    onGround: false,
    autoScrollSpeed: 2,
    maxScrollSpeed: 6,
    scrollAcceleration: 0.02,
    hurdles: [],                 // ハードル（障害物）
    hurdlesCleared: 0,          // ハードル通過数
    // coins removed — focusing on hurdles
    groundY: 500,
    lives: 5,
    hits: 0,
    maxHits: 5,
    invincibleTime: 0,
    pause: false
  };

  // ensure groundY and W/H are updated now that state exists
  resizeCanvas();
  state.groundY = Math.floor(H - GROUND_OFFSET);
  // place player on the ground at start
  state.player.y = state.groundY - state.player.h;

  // Input
  const keys = {};
  window.addEventListener('keydown', (e) => { keys[e.code] = true; if (e.code === 'Space' || e.code === 'ArrowUp') tryJump(); });
  window.addEventListener('keyup', (e) => { keys[e.code] = false; });

  // Joy‑Con jump event from index.html script
  window.addEventListener('joycon-jump', (e) => { tryJump(); });

  function tryJump() {
    if (state.onGround) {
      state.player.velY = state.jumpPower;
      state.onGround = false;
    }
  }

  // Initial platform generator
  // platforms removed — focusing on hurdles only

  // coins and enemies removed — focusing on hurdles only

  // --- ハードル生成 ---
  function generateHurdleAt(x) {
    const h = {
      x: x,
      y: state.groundY - rand(30, 70), // ハードル高さは地面から上向きに調整
      w: rand(20, 40),
      h: rand(30, 60),
      passed: false,
      falling: false,   // 倒れるアニメーション状態
      fallen: false,
      angle: 0,         // ラジアン
      fallSpeed: 0,
      removeTimer: 0
    };
    // ハードルは基本的に地面に立っているようにする
    h.y = state.groundY - h.h;
    state.hurdles.push(h);
  }

  function generateInitialHurdles() {
    // Create a small, spaced set of initial hurdles placed off-screen to the right
    // so they don't pop up immediately in the player's view.
  const initialCount = 4;
    // startBase: at least just beyond the right edge of the current view
    const startBase = state.cameraX + W + 150;
    let x = startBase;
    for (let i = 0; i < initialCount; i++) {
      x += rand(450, 1000);
      generateHurdleAt(x + rand(-30, 30));
    }
  }

  // Helpers
  function rand(a,b){ return Math.floor(a + Math.random()*(b-a+1)); }
  function randf(a,b){ return a + Math.random()*(b-a); }

  // Setup world
  generateInitialHurdles();

  // Main loop
  let last = performance.now();
  function loop(now) {
    const dt = (now - last) / 16.666; // ~60fps normalization
    last = now;
    if (!state.pause) update(dt);
    render();
    requestAnimationFrame(loop);
  }

  function update(dt) {
    // auto scroll
    if (state.autoScrollSpeed < state.maxScrollSpeed) state.autoScrollSpeed += state.scrollAcceleration * dt;
    state.player.x += state.autoScrollSpeed * dt;
    state.cameraX = Math.max(0, state.player.x - 150);

    // Horizontal keyboard influence (disabled briefly during knockback)
    if (state.player.knockbackTimer <= 0) {
      if (keys['ArrowLeft']) state.player.x -= 3 * dt;
      if (keys['ArrowRight']) state.player.x += 3 * dt;
    }

    // apply horizontal velocity (knockback)
    state.player.x += (state.player.velX || 0) * dt;
    // decay horizontal velocity
    state.player.velX *= Math.pow(0.7, dt);
    if (state.player.knockbackTimer > 0) state.player.knockbackTimer = Math.max(0, state.player.knockbackTimer - 1 * dt);

    // gravity
    state.player.velY += state.gravity * dt;
    state.player.y += state.player.velY * dt;

    // ground collision
    if (state.player.y + state.player.h >= state.groundY) {
      state.player.y = state.groundY - state.player.h;
      state.player.velY = 0; state.onGround = true;
    } else {
      state.onGround = false;
    }

    // platforms removed — rely on ground collision only

    // (coins and enemies removed) invincible time countdown
    if (state.invincibleTime > 0) state.invincibleTime -= 1 * dt;

    // ハードルの更新・生成・衝突判定
    // 生成: 画面外（右側）に予めハードルを用意しておく方式に変更
    // 画面内に突然出ないよう、常に "upcoming"（画面外に待機する）ハードルが
    // 一定数存在するようにする。
    const desiredUpcoming = 4; // 画面外にキープするハードル数
    let upcoming = state.hurdles.filter(h => h.x > state.cameraX + W);
    // 最後に生成されたハードルの X を取得（なければカメラ先端を基準）
    let lastX = state.hurdles.length ? Math.max(...state.hurdles.map(h => h.x)) : (state.cameraX + W);
    let attempts = 0;
    const maxAttempts = 50;
    while (upcoming.length < desiredUpcoming && attempts < maxAttempts) {
      const gap = rand(450, 1000);
      let nextX = lastX + gap;
      // 必ず現在の画面右端より少し先（オフスクリーン）になるようにする
      const minOffscreen = state.cameraX + W + 150;
      if (nextX < minOffscreen) nextX = minOffscreen + rand(0, 200);
      if (nextX <= lastX) nextX = lastX + 300;
      lastX = nextX;
      generateHurdleAt(lastX + rand(-20,20));
      upcoming = state.hurdles.filter(h => h.x > state.cameraX + W);
      attempts++;
    }
    if (attempts >= maxAttempts) console.warn('[game.js] hurdle generation attempts capped', attempts, upcoming.length, lastX);

    // Fallback: if no hurdles are scheduled to enter the visible area soon, add one just off the right edge
    const anyVisibleSoon = state.hurdles.some(h => h.x < state.cameraX + W + 200 && h.x > state.cameraX - 200);
    if (!anyVisibleSoon) {
      const fallbackX = state.cameraX + W + rand(50, 220);
      console.log('[game.js] fallback hurdle generated at', fallbackX);
      generateHurdleAt(fallbackX);
    }

    // ハードル通過判定と衝突
    for (let i = state.hurdles.length - 1; i >= 0; i--) {
      const h = state.hurdles[i];
      // 通過（プレイヤーの右端がハードルの右端を越えたらクリア）
      if (!h.passed && state.player.x > h.x + h.w) {
        h.passed = true;
        state.hurdlesCleared += 1;
        // クリアで少し速度を上げて難易度上昇
        state.autoScrollSpeed = Math.min(state.maxScrollSpeed, state.autoScrollSpeed + 0.05);
      }

      // 衝突：AABB
      if (!h.falling && collideRect(state.player, h) && state.invincibleTime <= 0) {
        // increment hit counter
        state.hits = (state.hits || 0) + 1;
        state.invincibleTime = 60;
        // ノックバック効果: 位置ジャンプではなく水平速度を付与して滑らかに戻す
        state.player.velX = -6; // 左方向へ押し戻す速度
        state.player.knockbackTimer = 12; // 数フレーム入力を制限
        // ハードルを倒すアニメーションを開始
        h.falling = true;
        h.fallSpeed = randf(0.06, 0.14); // ラジアン/フレーム相当
        // If hit limit reached, end the run and show result
        if (state.hits >= state.maxHits) {
          state.pause = true;
          showResult();
        }
      }

      // 倒れるアニメーション更新
      if (h.falling && !h.fallen) {
        h.angle += h.fallSpeed * dt;
        // 加速度的な増加で勢いをつける
        h.fallSpeed += 0.01 * dt;
        if (h.angle >= Math.PI / 2) {
          h.angle = Math.PI / 2;
          h.fallen = true;
          h.removeTimer = 120; // 倒れた後の表示時間（フレーム）
        }
      }
      if (h.fallen && h.removeTimer > 0) {
        h.removeTimer -= 1 * dt;
      }
    }

    // ハードルのオフスクリーン削除（倒れて一定時間経過したら削除）
    state.hurdles = state.hurdles.filter(h => {
      const onScreen = (h.x + h.w > state.cameraX - 200 && h.x < state.cameraX + W + 400);
      const alive = !(h.fallen && h.removeTimer <= 0);
      return onScreen && alive;
    });

  // cleanup offscreen things (platforms/enemies removed)
  }

  function collideRect(a,b) {
    return a.x < b.x + (b.w||b.width) && a.x + a.w > b.x && a.y < b.y + (b.h||b.height) && a.y + a.h > b.y;
  }

  function render() {
    // clear
    ctx.fillStyle = '#0b1220'; ctx.fillRect(0,0,W,H);

    // translate by camera
    ctx.save(); ctx.translate(-state.cameraX, 0);

    // ground
    ctx.fillStyle = '#2b8f2b'; ctx.fillRect(state.cameraX - 1000, state.groundY, W + 3000, H - state.groundY);

  // platforms removed

    // (coins and enemies removed)

    // hurdles（障害物） - 倒れるアニメーションに対応して描画
    for (const h of state.hurdles) {
      const pivotX = h.x + h.w / 2;
      const pivotY = h.y + h.h; // 地面側を軸に回転
      ctx.save();
      ctx.translate(pivotX, pivotY);
      ctx.rotate(h.angle || 0);
      // 本体（脚）
      ctx.fillStyle = '#b24';
      ctx.fillRect(-h.w / 2, -h.h, h.w, h.h);
      // トップバー（横棒）
      ctx.fillStyle = '#eee';
      ctx.fillRect(-h.w / 2 - 4, -h.h - 6, h.w + 8, 6);
      ctx.restore();
    }

    // player
    if (images.player) ctx.drawImage(images.player, state.player.x, state.player.y, state.player.w*1.5, state.player.h*1.5);
    else { ctx.fillStyle = '#4aa'; ctx.fillRect(state.player.x, state.player.y, state.player.w, state.player.h); }

    ctx.restore();

    // HUD (hurdle-focused)
    ctx.fillStyle = '#fff'; ctx.font = '16px sans-serif';
    ctx.fillText(`Hurdles: ${state.hurdlesCleared}`, 10, 20);
    ctx.fillText(`Distance: ${Math.floor(state.player.x)}`, 10, 40);
    ctx.fillText(`Hits: ${state.hits || 0} / ${state.maxHits}`, 10, 60);
  }

  // Show result overlay when run ends
  function showResult() {
    // prevent duplicate overlays
    if (document.getElementById('resultOverlay')) return;
    const overlay = document.createElement('div');
    overlay.id = 'resultOverlay';
    overlay.style.position = 'fixed';
    overlay.style.left = '50%';
    overlay.style.top = '50%';
    overlay.style.transform = 'translate(-50%,-50%)';
    overlay.style.background = 'rgba(0,0,0,0.9)';
    overlay.style.color = '#fff';
    overlay.style.padding = '24px';
    overlay.style.borderRadius = '8px';
    overlay.style.zIndex = 99999;
    overlay.style.textAlign = 'center';
    const dist = Math.floor(state.player.x);
    overlay.innerHTML = `<h2>Run finished</h2><p>Distance: ${dist}</p>`;
    const restartBtn = document.createElement('button');
    restartBtn.textContent = 'Restart';
    restartBtn.style.marginTop = '12px';
    restartBtn.addEventListener('click', () => { document.body.removeChild(overlay); restartGame(); });
    overlay.appendChild(restartBtn);
    document.body.appendChild(overlay);
  }

  function restartGame() {
    // reset state to initial conditions (keep assets loaded)
    state.hits = 0;
    state.hurdlesCleared = 0;
    state.hurdles = [];
    state.player.x = 100;
    state.player.y = state.groundY - state.player.h;
    state.player.velX = 0;
    state.player.velY = 0;
    state.cameraX = 0;
    state.autoScrollSpeed = 2;
    state.invincibleTime = 0;
    state.pause = false;
    generateInitialHurdles();
  }

  // start when assets loaded (or after small timeout)
  const startWhenReady = () => {
    if (loaded >= toLoad || performance.now() > 5000) { console.log('[game.js] starting loop'); requestAnimationFrame(loop); }
    else setTimeout(startWhenReady, 100);
  };
  startWhenReady();
  } catch (e) {
    console.error('[game.js] fatal error', e);
    // show a visible notification in the page for debugging
    const pre = document.createElement('pre'); pre.style.color = 'red'; pre.textContent = '[game.js] fatal error: ' + e;
    document.body.appendChild(pre);
  }

})();
