require 'gosu'
begin
  require 'hidaping'
  HIDAPING_AVAILABLE = true
rescue LoadError
  HIDAPING_AVAILABLE = false
  puts "hidaping gem not available: Joy-Con support disabled"
end

# ハードルを飛び越すだけの最小限ゲーム
class HurdleOnlyWindow < Gosu::Window
  def initialize
  super 1920, 1000
    self.caption = "ハードルジャンプ練習"

  # 地面はウィンドウ下寄りに設定（高さ 1000 の場合は 800 程度）
  @ground_y = 800

    # プレイヤー
    @player_x = 100.0
    @player_w = 32
    @player_h = 48
    @player_y = @ground_y - @player_h
    @player_vel_y = 0.0
    @gravity = 0.6
    @jump_power = -12.0
    @on_ground = true

  # Joy-Con 関連（hidaping が利用可能な場合のみ初期化）
  @joycon_handle = nil
  @joycon_connected = false
  @jump_threshold = 2.0
  @jump_cooldown = 0
  @current_accel_z = 0.0
  @accel_z_history = []
  # 使用する加速度の軸（:x, :y, :z）。X軸のみを使う設定にする
  @accel_axis = :x
  # true の場合はキーで軸を切り替えられない（Y 固定モード）
  @force_accel_axis = true

    # 加速度読み取りに使うバイト位置の候補（Joy-Conのレポートによる）
    # ここでは既存コードと互換性を保つために z=(18,17) を既定にし、
    # 他は近傍のペアを仮に割り当てます。実機で動作確認して調整してください。
    @accel_index = {
      x: [14, 13],
      y: [16, 15],
      z: [18, 17]
    }

    @current_accel = { x: 0.0, y: 0.0, z: 0.0 }

    initialize_joycon if HIDAPING_AVAILABLE

    # スクロール（地面は固定、障害物を左に動かす）
    @scroll_speed = 5.0

    # ハードル
    @hurdles = []
    @spawn_counter = 0
    @spawn_interval = 90 # フレーム間隔（ランダム化あり）
  # ハードル固定サイズ（幅、高さ）
  @hurdle_w = 40
  @hurdle_h = 50
    # プレイヤー画像を左右反転するか
    @player_flip = true

    # フォント: 指定された keifont.ttf を優先して使う。見つからなければデフォルトフォントを使用
    font_candidates = [
      # ユーザー指定の絶対パス
      "C:/Users/tamag/Desktop/aiueo/yokoscroll_game/font/keifont.ttf",
      # このファイルから見た相対パス (プロジェクトルート/font)
      File.join(__dir__, "..", "font", "keifont.ttf"),
      # さらに一般的な相対パス
      File.join(__dir__, "..", "..", "font", "keifont.ttf"),
      "font/keifont.ttf"
    ]

    chosen = font_candidates.find { |p| File.exist?(p) }
    if chosen
      @font = Gosu::Font.new(20, name: chosen)
    else
      @font = Gosu::Font.new(20)
    end
    # 画像読み込み（プレイヤー・ブロック）
    # プレイヤー画像: 優先順に hurdle_run / hurdle_junp (typo 対応) / hurdle_jump / kyara を探す
    player_candidates = [
      File.join(__dir__, "..", "img", "hurdle_run.png"),
      File.join(__dir__, "..", "..", "img", "hurdle_run.png"),
      File.join(__dir__, "img", "hurdle_run.png"),
      "img/hurdle_run.png",

      File.join(__dir__, "..", "img", "hurdle_junp.png"), # typo 互換
      File.join(__dir__, "..", "..", "img", "hurdle_junp.png"),
      File.join(__dir__, "img", "hurdle_junp.png"),
      "img/hurdle_junp.png",

      File.join(__dir__, "..", "img", "hurdle_jump.png"),
      File.join(__dir__, "..", "..", "img", "hurdle_jump.png"),
      File.join(__dir__, "img", "hurdle_jump.png"),
      "img/hurdle_jump.png",

      File.join(__dir__, "..", "img", "kyara.png"),
      File.join(__dir__, "..", "..", "img", "kyara.png"),
      File.join(__dir__, "img", "kyara.png"),
      "img/kyara.png"
    ]

    # ランニング画像とジャンプ画像を個別に探す
    run_path = player_candidates.find { |p| p.end_with?("hurdle_run.png") && File.exist?(p) }
    jump_path = player_candidates.find { |p| (p.end_with?("hurdle_junp.png") || p.end_with?("hurdle_jump.png")) && File.exist?(p) }
    # fallback: kyara
    kyara_path = player_candidates.find { |p| p.end_with?("kyara.png") && File.exist?(p) }

    if run_path
      @player_run_image = Gosu::Image.new(run_path, retro: true)
    else
      @player_run_image = nil
    end

    if jump_path
      @player_jump_image = Gosu::Image.new(jump_path, retro: true)
    else
      @player_jump_image = nil
    end

    if @player_run_image.nil? && kyara_path
      @player_run_image = Gosu::Image.new(kyara_path, retro: true)
      @player_jump_image = Gosu::Image.new(kyara_path, retro: true) if @player_jump_image.nil?
    end

    block_candidates = [
      File.join(__dir__, "..", "img", "block.png"),
      File.join(__dir__, "..", "..", "img", "block.png"),
      File.join(__dir__, "img", "block.png"),
      "img/block.png"
    ]
    img_block = block_candidates.find { |p| File.exist?(p) }
    if img_block
      @block_image = Gosu::Image.new(img_block, retro: true)
    else
      @block_image = nil
    end
    @score = 0
    @game_over = false
  end

  def update
    return if @game_over

    # ハードル生成
    @spawn_counter -= 1
    if @spawn_counter <= 0
      spawn_hurdle
      @spawn_counter = @spawn_interval + rand(-30..30)
      @spawn_counter = 30 if @spawn_counter < 30
    end

    # ハードル移動
    @hurdles.each do |h|
      h[:x] -= @scroll_speed
    end

    # 画面外ハードルを削除してスコア加算
    passed, alive = @hurdles.partition { |h| h[:x] + h[:w] < 0 }
    @score += passed.size
    @hurdles = alive

  # Joy-Con 入力処理（あれば） - 先に処理することでジャンプ設定が
  # 重力適用や地面補正で上書きされるのを防ぐ
  handle_joycon_input if HIDAPING_AVAILABLE
  handle_joycon_input if HIDAPING_AVAILABLE




    # ジャンプのクールダウン
    @jump_cooldown = [@jump_cooldown - 1, 0].max

    # 重力適用
    @player_vel_y += @gravity
    @player_y += @player_vel_y

    # 地面との接触
    if @player_y + @player_h >= @ground_y
      @player_y = @ground_y - @player_h
      @player_vel_y = 0
      @on_ground = true
    else
      @on_ground = false
    end

    # 衝突判定（ポールまたは横棒に衝突したらゲームオーバー）
    @hurdles.each do |h|
      if collision_with_hurdle?(h)
        @game_over = true
      end
    end
  end

  def draw
    # 背景
    Gosu.draw_rect(0, 0, width, height, Gosu::Color::WHITE, 0)

    # 地面
    Gosu.draw_rect(0, @ground_y, width, height - @ground_y, Gosu::Color::GREEN, 0)

    # プレイヤー描画（画像があれば画像で、なければ矩形）
    # プレイヤー画像があれば走りとジャンプで切り替えて描画
    img_run = @player_run_image
    img_jump = @player_jump_image || @player_run_image
    if img_run
      scale_x = @player_w.to_f / img_run.width
      scale_y = @player_h.to_f / img_run.height
      if @on_ground
        # 走り画像は左右反転に従う
        if @player_flip
          img_run.draw(@player_x + @player_w, @player_y, 1, -scale_x, scale_y)
        else
          img_run.draw(@player_x, @player_y, 1, scale_x, scale_y)
        end
      else
        # ジャンプ中はジャンプ画像を優先して描画（ジャンプ画像は左右反転しない仕様）
        if img_jump && img_jump != img_run
          img_jump.draw(@player_x, @player_y, 1, scale_x, scale_y)
        else
          # ジャンプ画像が無い場合は走り画像を回転して代用するが、ここでも反転は行わない
          cx = @player_x + @player_w / 2.0
          cy = @player_y + @player_h / 2.0
          angle = -15
          img_run.draw_rot(cx, cy, 1, angle, 0.5, 0.5, scale_x, scale_y)
        end
      end
    else
      Gosu.draw_rect(@player_x, @player_y, @player_w, @player_h, Gosu::Color::BLUE, 1)
    end

    # ハードル描画（ポール + 横棒）
    @hurdles.each do |h|
      pole_w = h[:pole_w] || 6
      bar_h = h[:bar_h] || 6
      bar_x = h[:x] + pole_w
      bar_w = [h[:w] - pole_w * 2, 4].max
      bar_y = h[:bar_y] || (h[:y] + (h[:h] * 0.2).to_i)

      if @block_image
        # ポールを画像でタイル描画（縦方向）
        img_h = @block_image.height
        img_w = @block_image.width
        # 左ポール
        y_pos = h[:y]
        while y_pos < h[:y] + h[:h]
          @block_image.draw(h[:x], y_pos, 1, pole_w.to_f / img_w, img_h.to_f / img_h)
          y_pos += img_h
        end
        # 右ポール
        y_pos = h[:y]
        while y_pos < h[:y] + h[:h]
          @block_image.draw(h[:x] + h[:w] - pole_w, y_pos, 1, pole_w.to_f / img_w, img_h.to_f / img_h)
          y_pos += img_h
        end

        # 横棒を画像でタイル描画（横方向）
        x_pos = bar_x
        while x_pos < bar_x + bar_w
          draw_w = [img_w, bar_x + bar_w - x_pos].min
          scale = draw_w.to_f / img_w
          @block_image.draw(x_pos, bar_y, 1, scale, bar_h.to_f / img_h)
          x_pos += img_w * scale
        end
      else
        # フォールバック: 矩形描画
        Gosu.draw_rect(h[:x], h[:y], pole_w, h[:h], Gosu::Color::FUCHSIA, 1)
        Gosu.draw_rect(h[:x] + h[:w] - pole_w, h[:y], pole_w, h[:h], Gosu::Color::FUCHSIA, 1)
        Gosu.draw_rect(bar_x, bar_y, bar_w, bar_h, Gosu::Color::FUCHSIA, 1)
      end
    end

    # UI
    @font.draw_text("スコア: #{@score}", 10, 10, 2, 1, 1, Gosu::Color::YELLOW)

    # Joy-Con の選択軸表示と現在値（デバッグ用）
    if HIDAPING_AVAILABLE
      axis_val = @current_accel[@accel_axis] || 0.0
      # 使用軸が固定されている場合はその旨を表示
      axis_label = @force_accel_axis ? "#{@accel_axis.upcase} (固定)" : @accel_axis.upcase
      @font.draw_text("Joy axis: #{axis_label}  値: #{axis_val.round(3)}G", 10, 40, 2, 1, 1, Gosu::Color::CYAN)
      y_offset = 64
    else
      @font.draw_text("スペース/上キーでジャンプ", 10, 40, 2, 1, 1, Gosu::Color::WHITE)
      y_offset = 64
    end

    if @game_over
      @font.draw_text("GAME OVER - Rでリスタート", width/2 - 140, height/2 - 10, 3, 1, 1, Gosu::Color::RED)
    end
  end

  def button_down(id)
    case id
    when Gosu::KB_ESCAPE
      close
    when Gosu::KB_SPACE, Gosu::KB_UP
      jump if @on_ground && !@game_over
    when Gosu::KB_R
      restart_game
    # 1/2/3 による軸切替は固定モードでは無効化しているため削除しました
    when Gosu::KB_F
      @player_flip = !@player_flip
      puts "player_flip => #{@player_flip}"
    end
  end

  def jump
    @player_vel_y = @jump_power
    @on_ground = false
  end

  def spawn_hurdle
    # ハードルは固定サイズを使う
    w = @hurdle_w
    h = @hurdle_h
    x = width + 50
    y = @ground_y - h
    pole_w = 6
    bar_h = 6
    bar_y = y + (h * 0.25).to_i
    @hurdles << { x: x, y: y, w: w, h: h, pole_w: pole_w, bar_h: bar_h, bar_y: bar_y }
  end

  def rect_collision?(ax, ay, aw, ah, bx, by, bw, bh)
    ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by
  end

  # ハードル（ポール + 横棒）との衝突判定
  def collision_with_hurdle?(h)
    pole_w = h[:pole_w] || 6
    bar_h = h[:bar_h] || 6
    # 左ポール
    left_x = h[:x]
    left_y = h[:y]
    # 右ポール
    right_x = h[:x] + h[:w] - pole_w
    right_y = h[:y]
    # 横棒
    bar_x = h[:x] + pole_w
    bar_y = h[:bar_y] || (h[:y] + (h[:h] * 0.2).to_i)
    bar_w = [h[:w] - pole_w * 2, 4].max

    if rect_collision?(@player_x, @player_y, @player_w, @player_h, left_x, left_y, pole_w, h[:h])
      return true
    end

    if rect_collision?(@player_x, @player_y, @player_w, @player_h, right_x, right_y, pole_w, h[:h])
      return true
    end

    if rect_collision?(@player_x, @player_y, @player_w, @player_h, bar_x, bar_y, bar_w, bar_h)
      return true
    end

    false
  end

  def restart_game
    @player_x = 100.0
    @player_y = @ground_y - @player_h
    @player_vel_y = 0
    @hurdles.clear
    @spawn_counter = 0
    @score = 0
    @game_over = false
  end

  # Joy-Con 初期化
  def initialize_joycon
    begin
      @joycon_handle = HIDAPING.open(0x057e, 0x2007)
      if @joycon_handle
        # 初期化シーケンス（既存プロジェクト参照）
        begin
          @joycon_handle.write("\x01\x00\x00\x01\x40\x40\x00\x01\x40\x40\x40\x01")
          @joycon_handle.write("\x01\x01\x00\x01\x40\x40\x00\x01\x40\x40\x03\x30")
        rescue
          # 送信に失敗しても続行
        end
        @joycon_connected = true
        puts "Joy-Con 接続成功"
      else
        @joycon_connected = false
        puts "Joy-Con が見つかりません"
      end
    rescue => e
      @joycon_connected = false
      puts "Joy-Con 初期化エラー: #{e}"
    end
  end

  # Joy-Con 入力の読み取りとジャンプ検出
  def handle_joycon_input
    return unless @joycon_connected && @joycon_handle

    data = nil
    begin
      # 短いタイムアウトで非ブロッキング読み取り
      data = @joycon_handle.read_timeout(49, 0.01)
    rescue
      return
    end

    return unless data && data.length >= 49 && data[0].ord == 0x30

    # 各軸の生データを取り出す（ペアのバイトから 16bit 値を復元）
    [:x, :y, :z].each do |ax|
      hi_idx, lo_idx = @accel_index[ax][0], @accel_index[ax][1]
      if hi_idx < data.length && lo_idx < data.length
        raw = (data[hi_idx].ord << 8) | data[lo_idx].ord
        val = (raw > 32767 ? raw - 65536 : raw) / 4000.0
        @current_accel[ax] = val
      else
        @current_accel[ax] = 0.0
      end
    end

    # 履歴は便利なら z の履歴で保持（必要に応じて拡張可）
    @accel_z_history << @current_accel[:z]
    @accel_z_history.shift if @accel_z_history.size > 100

    # ジャンプ検出
    sel_val = @current_accel[@accel_axis]
    if sel_val && sel_val.abs > @jump_threshold && @on_ground && @jump_cooldown == 0
      @player_vel_y = @jump_power
      @on_ground = false
      @jump_cooldown = 30
      puts "Joy-Con ジャンプ検出(#{@accel_axis.upcase}): #{sel_val.round(3)}G"
    end
  end
end

# 実行
window = HurdleOnlyWindow.new
window.show
