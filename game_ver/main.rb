require 'gosu'
require 'hidaping'
require 'timeout'

class GameWindow < Gosu::Window
  def initialize
    # ウィンドウサイズ
    super 800, 600
    self.caption = "横スクロールアクションRPG"
    
    # Joy-Con初期化
    initialize_joycon
    
    # 位置
    @camera_x = 0
    @camera_y = 0
    
    # ワールドサイズ
    @world_width = 10000
    @world_height = 600
    
    # プレイヤーのサイズ
    @player_x = 100
    @player_y = 400
    @player_width = 32
    @player_height = 48
    
    # 自動スクロール設定
    @auto_scroll_speed = 2.0
    @auto_scroll_enabled = true
    @max_scroll_speed = 6
    @scroll_acceleration = 0.02
    @scroll_direction = 1 
    
    # プレイヤー移動
    @player_speed = 5
    @player_vel_y = 0
    @gravity = 0.5
    @jump_power_low = -10
    @jump_power_high = -18 
    @on_ground = false
    
  # Joy-Con関連
  @jump_threshold = 1.0 
  @jump_cooldown = 0    
  @current_accel_z = 0.0 
  # 加速度値履歴
  @accel_z_history = []
    
    # 地面の高さ
    @ground_y = 500
    
    # プラットフォーム生成
    @platforms = []
    @platform_generator_x = 800
    generate_initial_platforms
    
    # コイン
    @coins = []
    @coins_collected = 0
    @coins_needed = 10
    @coin_generator_x = 400
    generate_initial_coins
    
    # 敵
    @enemies = []
    @enemy_generator_x = 600
    generate_initial_enemies
    
    # 色
    @player_color = Gosu::Color::BLUE
    @ground_color = Gosu::Color::GREEN
    @platform_color = Gosu::Color::GRAY
    @bg_color = Gosu::Color::BLACK
    @enemy_color = Gosu::Color::RED
    
    # フォント
    @font = Gosu::Font.new(20, name: "font/keifont.ttf")
    
    # ゲーム状態
    @score = 0
    @distance = 0
    @lives = 5
    @max_lives = 5
    @invincible_time = 0
    @invincible_duration = 60
    @game_over = false
    @game_clear = false
    @pause = false

    # 画像
    @coin_image = Gosu::Image.new("img/coin.png", retro: true)
    @block_image = Gosu::Image.new("img/block.png", retro: true)
    @player_image = Gosu::Image.new("img/kyara.png", retro: true)
  end
  
  def initialize_joycon
    
    begin
      @joycon_handle = HIDAPING.open(0x057e, 0x2007)
      if @joycon_handle
        @joycon_handle.write("\x01\x00\x00\x01\x40\x40\x00\x01\x40\x40\x40\x01")
        @joycon_handle.write("\x01\x01\x00\x01\x40\x40\x00\x01\x40\x40\x03\x30")
        @joycon_connected = true
        puts "Joy-Con接続成功！"
      else
        @joycon_connected = false
        puts "Joy-Conが見つかりません"
      end
    rescue => e
      puts "Joy-Con接続エラー: #{e}"
      @joycon_connected = false
    end
  end
  
  def update
    return if @game_over || @game_clear || @pause
    
    handle_input
    handle_joycon_input
    # ジャンプのクールダウン
    @jump_cooldown = [@jump_cooldown - 1, 0].max
    # 無敵時間
    @invincible_time = [@invincible_time - 1, 0].max
    
    # 自動スクロール
    update_auto_scroll
    
    # 重力
    @player_vel_y += @gravity
    @player_y += @player_vel_y
    
    # 衝突判定
    handle_collisions
    
    # カメラの更新
    update_camera
    
    # プラットフォーム生成
    manage_platforms
    
    # コイン
    manage_coins
    
    # 敵
    manage_enemies
    
    # コイン収集判定
    collect_coins
    
    # 敵との衝突判定
    check_enemy_collision
    
    # スコア更新
    update_score
    
    # ゲームオーバー・クリア判定
    check_game_over
    check_game_clear
  end
  
  def update_auto_scroll
    return unless @auto_scroll_enabled
    
    # スクロール速度を徐々に上げる
    if @auto_scroll_speed < @max_scroll_speed
      @auto_scroll_speed += @scroll_acceleration
    end
    
    # プレイヤーを自動的に移動させる
    @player_x += @auto_scroll_speed * @scroll_direction
    @distance += @auto_scroll_speed
    
    
    # プレイヤーが画面端に近づいたら強制的に移動
    if @scroll_direction == 1
      min_x = @camera_x + 50
      if @player_x < min_x
        @player_x = min_x
      end
    else
      max_x = @camera_x + width - 50 - @player_width
      if @player_x > max_x
        @player_x = max_x
      end
    end
  end
  
  def generate_initial_platforms
    # プラットフォームを生成
    x = 300
    while x < @platform_generator_x
      generate_platform_at(x)
      x += rand(150..300)
    end
  end
  
  def generate_platform_at(x)
    # プラットフォームを生成
    platform = {
      x: x,
      y: rand(200..450),
      width: rand(80..150),
      height: 20,
      type: [:normal, :moving].sample
    }
    
    # 移動プラットフォームの場合
    if platform[:type] == :moving
      platform[:move_speed] = rand(1..3)
      platform[:move_direction] = [-1, 1].sample
      platform[:move_range] = rand(100..200)
      platform[:start_y] = platform[:y]
    end
    
    @platforms << platform
  end
  
  def manage_platforms
    # プラットフォームを削除
    if @scroll_direction == 1
      @platforms.reject! { |p| p[:x] + p[:width] < @camera_x - 100 }
    else
      @platforms.reject! { |p| p[:x] > @camera_x + width + 100 }
    end
    
    # プラットフォームを生成
    if @scroll_direction == 1
      while @platform_generator_x < @camera_x + width + 500
        generate_platform_at(@platform_generator_x)
        @platform_generator_x += rand(150..300)
      end
    else
      while @platform_generator_x > @camera_x - 500
        generate_platform_at(@platform_generator_x)
        @platform_generator_x -= rand(150..300)
      end
    end
    
    # プラットフォームの更新
    @platforms.each do |platform|
      if platform[:type] == :moving
        platform[:y] += platform[:move_speed] * platform[:move_direction]
        
        if (platform[:y] - platform[:start_y]).abs > platform[:move_range]
          platform[:move_direction] *= -1
        end
        
        platform[:y] = [platform[:y], 100].max
        platform[:y] = [platform[:y], @ground_y - 50].min
      end
    end
  end
  
  def generate_initial_coins
    # コインを生成
    x = 400
    while x < @world_width - 400
      # コインの高さを地面や低いプラットフォーム付近に調整
      generate_coin_at(x + rand(-50..50), rand(300..450))  # 元: rand(150..400)
      x += (rand(250..415) * 0.714).to_i
    end
  end
  
  def generate_coin_at(x, y)
    @coins << {
      x: x,
      y: y,
      width: 20,
      height: 20,
      animation: 0
    }
  end
  
  def manage_coins
    # アニメーション更新
    @coins.each do |coin|
      coin[:animation] += 1
    end
  end

  def collect_coins
    @coins.each do |coin|
      if collision_with_coin?(coin)
        @coins.delete(coin)
        @coins_collected += 1
        puts "コイン取得！ (#{@coins_collected}/#{@coins_needed})"
      end
    end
  end
  
  def collision_with_coin?(coin)
    @player_x < coin[:x] + coin[:width] &&
    @player_x + @player_width > coin[:x] &&
    @player_y < coin[:y] + coin[:height] &&
    @player_y + @player_height > coin[:y]
  end
  
  def generate_initial_enemies
    # 初期敵を生成
    x = 600
    while x < @world_width - 400
      generate_enemy_at(x + rand(-100..100))
      x += rand(800..1500) 
    end
  end
  
  def generate_enemy_at(x)
    enemy_type = [:walker, :jumper, :flyer].sample
    enemy = {
      x: x,
      y: @ground_y - 40,
      width: 24,
      height: 40,
      type: enemy_type,
      vel_y: 0,
      move_direction: [-1, 1].sample,
      move_speed: rand(1.0..2.5),
      animation: 0
    }
    
    # 飛行敵の場合は空中に配置
    if enemy_type == :flyer
      enemy[:y] = rand(200..400)
      enemy[:move_range] = rand(100..200)
      enemy[:start_y] = enemy[:y]
    end
    
    @enemies << enemy
  end
  
  def manage_enemies
    # 敵を削除
    @enemies.reject! do |enemy|
      if @scroll_direction == 1
        enemy[:x] + enemy[:width] < @camera_x - 200
      else
        enemy[:x] > @camera_x + width + 200
      end
    end
    
    # 新しい敵を生成
    if @scroll_direction == 1
      while @enemy_generator_x < @camera_x + width + 500
        generate_enemy_at(@enemy_generator_x)
        @enemy_generator_x += rand(800..1500)  
      end
    else
      while @enemy_generator_x > @camera_x - 500
        generate_enemy_at(@enemy_generator_x)
        @enemy_generator_x -= rand(800..1500)
      end
    end
    
    # 敵の動作更新
    @enemies.each do |enemy|
      enemy[:animation] += 1
      
      case enemy[:type]
      when :walker
        enemy[:x] += enemy[:move_speed] * enemy[:move_direction]
      when :jumper
        enemy[:x] += enemy[:move_speed] * enemy[:move_direction] * 0.5
        # たまにジャンプ
        if rand(120) == 0 && enemy[:vel_y] == 0
          enemy[:vel_y] = -8
        end
        enemy[:vel_y] += @gravity
        enemy[:y] += enemy[:vel_y]
        # 地面との衝突
        if enemy[:y] >= @ground_y - enemy[:height]
          enemy[:y] = @ground_y - enemy[:height]
          enemy[:vel_y] = 0
        end
      when :flyer
        enemy[:x] += enemy[:move_speed] * enemy[:move_direction] * 0.7
        # 上下に飛行
        enemy[:y] += Math.sin(enemy[:animation] * 0.1) * 0.5
      end
    end
  end
  
  def check_enemy_collision
    return if @invincible_time > 0 
    
    @enemies.each do |enemy|
      if collision_with_enemy?(enemy)
        @lives -= 1
        @invincible_time = @invincible_duration
        puts "敵に接触！ライフ: #{@lives}/#{@max_lives}"
        
        if @lives <= 0
          @game_over = true
          puts "ゲームオーバー"
        end
        break
      end
    end
  end
  
  def collision_with_enemy?(enemy)
    @player_x < enemy[:x] + enemy[:width] &&
    @player_x + @player_width > enemy[:x] &&
    @player_y < enemy[:y] + enemy[:height] &&
    @player_y + @player_height > enemy[:y]
  end
  
  def check_game_clear
    if @coins_collected >= @coins_needed
      @game_clear = true
      puts "ゲームクリア！"
    end
  end
  
  def update_score
    @score = (@distance / 10).to_i
  end
  
  def check_game_over
    # 画面下に落ちた場合
    if @player_y > @world_height + 100
      @game_over = true
    end

    # 画面左端に到達した場合 - 反転
    if @player_x <= @camera_x
      reverse_direction
    end

    # 画面右端に到達した場合 - 反転
    if @player_x + @player_width >= @camera_x + width
      reverse_direction
    end
  end
  
  def reverse_direction
    @scroll_direction *= -1
    puts "方向反転！ 新しい方向: #{@scroll_direction == 1 ? '右' : '左'}"
    
    # 新しい障害物を生成する準備
    if @scroll_direction == 1
      # 右方向の場合、画面右端から先に生成
      @platform_generator_x = @camera_x + width + 100
      @enemy_generator_x = @camera_x + width + 200
    else
      # 左方向の場合、画面左端から先に生成
      @platform_generator_x = @camera_x - 100
      @enemy_generator_x = @camera_x - 200
    end
  end
  
  def handle_joycon_input
    return unless @joycon_connected && @joycon_handle

    # 改善点のif文
  data = nil
  begin
    if # ちょっと謎のif分(これでなぜか思い通りに動いてくれてる)
      data = @joycon_handle.read(49)
      data = @joycon_handle.read_timeout(49 , 0.01)
    else
      data = @joycon_handle.read_timeout(49, 0.01)
    end
  rescue
    return
  end

    return unless data && data.length >= 49 && data[0].ord == 0x30

    # Z軸加速度取得
    az_raw = (data[18].ord << 8) | data[17].ord
    az = (az_raw > 32767 ? az_raw - 65536 : az_raw) / 4000.0

  @current_accel_z = az
  @accel_z_history << az
  @accel_z_history.shift if @accel_z_history.size > 100
  
    # ジャンプ検出
    if az.abs > @jump_threshold && @on_ground && @jump_cooldown == 0
      # ジャンプ力を加速度値で決定
      if az <= -2.0 || az >= 2.0
        @player_vel_y = @jump_power_high
        puts "Joy-Con高ジャンプ検出！ Z軸: #{az.round(3)}G"
      else
        @player_vel_y = @jump_power_low
        puts "Joy-Con低ジャンプ検出！ Z軸: #{az.round(3)}G"
      end
      @on_ground = false
      @jump_cooldown = 30
    end
  end
  
  def draw
    if @game_over
      draw_game_over
      return
    end

    if @game_clear
      draw_game_clear
      return
    end

    if @pause
      draw_pause
      return
    end

    # カメラ
    translate(-@camera_x, -@camera_y) do
      draw_parallax_background

      # 地面の描画
      Gosu.draw_rect(@camera_x, @ground_y, width, @world_height - @ground_y, @ground_color, 0)

      # プラットフォームの描画
      @platforms.each do |platform|
        if @block_image
          block_width = @block_image.width
          blocks = (platform[:width] / block_width).floor
          offset = (platform[:width] - blocks * block_width) / 2.0
          blocks.times do |i|
            x = platform[:x] + offset + i * block_width
            @block_image.draw(x, platform[:y], 1)
          end
        else
          Gosu.draw_rect(platform[:x], platform[:y], platform[:width], platform[:height], @platform_color)
        end
      end

      # コインの描画
      @coins.each do |coin|
        @coin_image.draw(coin[:x], coin[:y], 1, coin[:width] / @coin_image.width.to_f, coin[:height] / @coin_image.height.to_f)
      end

      # 敵の描画
      @enemies.each do |enemy|
        color = case enemy[:type]
                when :walker then Gosu::Color::RED
                when :jumper then Gosu::Color::YELLOW
                when :flyer then Gosu::Color::CYAN
                end
        Gosu.draw_rect(enemy[:x], enemy[:y], enemy[:width], enemy[:height], color)
      end

      # プレイヤー描画
      if @invincible_time > 0 && (@invincible_time / 5) % 2 == 0
        # 点滅中は描画しない
      elsif @player_image
        @player_image.draw(@player_x, @player_y, 1, @player_width / @player_image.width.to_f, @player_height / @player_image.height.to_f)
      else
        Gosu.draw_rect(@player_x, @player_y, @player_width, @player_height, @player_color)
      end
    end

    # UI表示
    draw_ui
  end
  
  def draw_parallax_background
    # 空
    star_offset = (@camera_x * 0.1).to_i
    20.times do |i|
      x = (i * 100 - star_offset) % (width + 200) + @camera_x - 100
      y = (i * 37) % (height - 100) + 50
      Gosu.draw_rect(x, y, 2, 2, Gosu::Color::WHITE)
    end
  end
  
  def draw_ui
    # コイン収集状況
    @font.draw_text("コイン: #{@coins_collected}/#{@coins_needed}", 10, 10, 1, 1, 1, Gosu::Color::YELLOW)
    @font.draw_text("スコア: #{@score}", 10, 35, 1, 1, 1, Gosu::Color::WHITE)
    @font.draw_text("速度: #{@auto_scroll_speed.round(1)}", 10, 60, 1, 1, 1, Gosu::Color::WHITE)
    
    # ライフ表示
    life_color = @lives > 2 ? Gosu::Color::RED : Gosu::Color::YELLOW
    if @invincible_time > 0 && (@invincible_time / 10) % 2 == 0
      life_color = Gosu::Color::WHITE 
    end
    @font.draw_text("ライフ: #{'♥' * @lives}#{'♡' * (@max_lives - @lives)}", 10, 85, 1, 1, 1, life_color)
    
    @font.draw_text("敵: #{@enemies.size}体", 10, 185, 1, 1, 1, Gosu::Color::RED)
    
    # スクロール方向表示
    direction_text = @scroll_direction == 1 ? "→" : "←"
    @font.draw_text("方向: #{direction_text}", 10, 110, 1, 1, 1, Gosu::Color::CYAN)
    
    # Joy-Con状態
    status_text = @joycon_connected ? "Joy-Con: 接続中" : "Joy-Con: 未接続"
    status_color = @joycon_connected ? Gosu::Color::GREEN : Gosu::Color::RED
    @font.draw_text(status_text, 10, 235, 1, 1, 1, status_color)
    
    # 操作説明
    @font.draw_text("現実世界でジャンプ！！！", 10, 135, 1, 1, 1, Gosu::Color::YELLOW)
    @font.draw_text("P: ポーズ, R: リスタート", 10, 160, 1, 1, 1, Gosu::Color::WHITE)
    
    # デバッグ情報
    if @jump_cooldown > 0
      cooldown_text = "クールダウン: #{@jump_cooldown}"
      @font.draw_text(cooldown_text, 10, 210, 1, 1, 1, Gosu::Color::RED)
    end

    # 加速度グラフ描画
    if @accel_z_history && !@accel_z_history.empty?
      graph_w = 300
      graph_h = 100
      graph_x = width - graph_w - 10
      graph_y = 10
      max_val = 2.0
      min_val = -2.0
      scale_x = graph_w.to_f / [@accel_z_history.size-1,1].max
      scale_y = graph_h.to_f / (max_val - min_val)
      # 0の基準線
      zero_y = graph_y + graph_h/2
      Gosu.draw_line(graph_x, zero_y, Gosu::Color::WHITE, graph_x+graph_w, zero_y, Gosu::Color::WHITE, 12)

  # 2, 4, -2, -4の基準線
  y_2 = zero_y - (2.0 * scale_y)
  y_4 = zero_y - (4.0 * scale_y)
  y_m2 = zero_y - (-2.0 * scale_y) 
  y_m4 = zero_y - (-4.0 * scale_y)
  # 4の線はグラフ外になるので、グラフ上端/下端に合わせる
  y_4 = [y_4, graph_y].max
  y_m4 = [y_m4, graph_y + graph_h].min
  # +2 赤, +4 ピンク, -2 青, -4 水色
  Gosu.draw_line(graph_x, y_2, Gosu::Color::RED, graph_x+graph_w, y_2, Gosu::Color::RED, 13)
  Gosu.draw_line(graph_x, y_4, Gosu::Color::FUCHSIA, graph_x+graph_w, y_4, Gosu::Color::FUCHSIA, 13)
  Gosu.draw_line(graph_x, y_m2, Gosu::Color::BLUE, graph_x+graph_w, y_m2, Gosu::Color::BLUE, 13)
  Gosu.draw_line(graph_x, y_m4, Gosu::Color::AQUA, graph_x+graph_w, y_m4, Gosu::Color::AQUA, 13)

      prev_x = graph_x
      prev_y = zero_y - (@accel_z_history[0] * scale_y).to_i
      @accel_z_history.each_with_index do |val, i|
        x = graph_x + (i * scale_x)
        y = zero_y - (val * scale_y).to_i
        if i > 0
          Gosu.draw_line(prev_x, prev_y, Gosu::Color::CYAN, x, y, Gosu::Color::YELLOW, 11)
        end
        prev_x = x
        prev_y = y
      end
      @font.draw_text("加速度Z", graph_x, graph_y-22, 11, 1, 1, Gosu::Color::WHITE)
    end
  end
  
  def draw_game_over
    # ゲームオーバー画面
    Gosu.draw_rect(0, 0, width, height, Gosu::Color.new(100, 0, 0, 0))
    
    game_over_font = Gosu::Font.new(40)
    game_over_font.draw_text("GAME OVER", width/2 - 120, height/2 - 60, 1, 1, 1, Gosu::Color::RED)
    
    @font.draw_text("最終スコア: #{@score}", width/2 - 80, height/2 - 10, 1, 1, 1, Gosu::Color::WHITE)
    @font.draw_text("Rキーでリスタート", width/2 - 80, height/2 + 20, 1, 1, 1, Gosu::Color::WHITE)
    @font.draw_text("ESCキーで終了", width/2 - 70, height/2 + 50, 1, 1, 1, Gosu::Color::WHITE)
  end
  
  def draw_game_clear
    # ゲームクリア画面
    Gosu.draw_rect(0, 0, width, height, Gosu::Color.new(100, 0, 100, 0))
    
    clear_font = Gosu::Font.new(40)
    clear_font.draw_text("GAME CLEAR!", width/2 - 140, height/2 - 60, 1, 1, 1, Gosu::Color::YELLOW)
    
    @font.draw_text("コイン #{@coins_needed}枚収集完了！", width/2 - 100, height/2 - 10, 1, 1, 1, Gosu::Color::WHITE)
    @font.draw_text("最終スコア: #{@score}", width/2 - 80, height/2 + 20, 1, 1, 1, Gosu::Color::WHITE)
    @font.draw_text("Rキーでリスタート", width/2 - 80, height/2 + 50, 1, 1, 1, Gosu::Color::WHITE)
    @font.draw_text("ESCキーで終了", width/2 - 70, height/2 + 80, 1, 1, 1, Gosu::Color::WHITE)
  end
  
  def draw_pause
    # ポーズ画面
    Gosu.draw_rect(0, 0, width, height, Gosu::Color.new(100, 0, 0, 0))

    pause_font = Gosu::Font.new(40)
    pause_font.draw_text("PAUSE", width/2 - 80, height/2 - 20, 1, 1, 1, Gosu::Color::YELLOW)

    @font.draw_text("Pキーで再開", width/2 - 60, height/2 + 30, 1, 1, 1, Gosu::Color::WHITE)
  end
  
  def restart_game
    # ゲームリスタート
    @camera_x = 0
    @player_x = 100
    @player_y = 400
    @player_vel_y = 0
    @auto_scroll_speed = 2.0
    @scroll_direction = 1
    @score = 0
    @distance = 0
    @coins_collected = 0
    @lives = @max_lives
    @invincible_time = 0
    @game_over = false
    @game_clear = false
    @pause = false
    @on_ground = false
    @platforms.clear
    @coins.clear
    @enemies.clear
    @platform_generator_x = 800
    @coin_generator_x = 400
    @enemy_generator_x = 600
    generate_initial_platforms
    generate_initial_coins
    generate_initial_enemies
  end
  
  private
  
  def handle_input
    # 左右微調整
    if Gosu.button_down?(Gosu::KB_LEFT) || Gosu.button_down?(Gosu::KB_A)
      if @scroll_direction == 1
        @player_x -= @player_speed * 0.5 unless @player_x <= @camera_x + 50
      else
        @player_x -= @player_speed * 0.5 unless @player_x <= @camera_x + 50
      end
    end
    
    if Gosu.button_down?(Gosu::KB_RIGHT) || Gosu.button_down?(Gosu::KB_D)
      if @scroll_direction == 1
        @player_x += @player_speed * 0.5 unless @player_x >= @camera_x + width - 100
      else
        @player_x += @player_speed * 0.5 unless @player_x >= @camera_x + width - 100
      end
    end
  end
  
  def button_down(id)
    # ESCキーで終了
    if id == Gosu::KB_ESCAPE
      close
    end
    
    # ポーズ
    if id == Gosu::KB_P
      @pause = !@pause
    end
    
    # リスタート
    if id == Gosu::KB_R
      restart_game
    end
    
    # キーボードでのジャンプ
    if (id == Gosu::KB_SPACE || id == Gosu::KB_UP || id == Gosu::KB_J) && @on_ground && !@game_over && !@game_clear && !@pause
      @player_vel_y = @jump_power_low
      @on_ground = false
      puts "キーボードジャンプ"
    end
  end
  
  def handle_collisions
    @on_ground = false
    
    # 地面との衝突判定
    if @player_y + @player_height >= @ground_y
      @player_y = @ground_y - @player_height
      @player_vel_y = 0
      @on_ground = true
    end
    
    # プラットフォームとの衝突判定
    @platforms.each do |platform|
      if collision_with_platform?(platform)
        if @player_vel_y > 0 && @player_y < platform[:y]
          @player_y = platform[:y] - @player_height
          @player_vel_y = 0
          @on_ground = true
        end
      end
    end
  end
  
  def collision_with_platform?(platform)
    @player_x < platform[:x] + platform[:width] &&
    @player_x + @player_width > platform[:x] &&
    @player_y < platform[:y] + platform[:height] &&
    @player_y + @player_height > platform[:y]
  end
  
  def update_camera
    # 自動スクロールに合わせてカメラを更新
    target_camera_x = @player_x - width / 3  
    @camera_x += (target_camera_x - @camera_x) * 0.1
    @camera_x = [@camera_x, 0].max
    @camera_x = [@camera_x, @world_width - width].min
  end
  
  def close
    # Joy-Con接続を切断する
    if @joycon_connected && @joycon_handle
      @joycon_handle.close
    end
    super
  end
end

# ゲームを開始
window = GameWindow.new
window.show