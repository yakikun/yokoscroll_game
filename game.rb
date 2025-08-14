require 'gosu'
require 'hidaping'

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
    @world_width = 2400
    @world_height = 600
    
    # プレイヤーのサイズ
    @player_x = 100
    @player_y = 400
    @player_width = 32
    @player_height = 48
    
    # プレイヤー移動
    @player_speed = 5
    @player_vel_y = 0
    @gravity = 0.5
    @jump_power = -15
    @on_ground = false
    
    # Joy-Con関連
    @jump_threshold = 1.0 
    @jump_cooldown = 0    
    @current_accel_z = 0.0 
    
    # 地面の高さ
    @ground_y = 500
    
    # プラットフォームの定義
    @platforms = [
      { x: 300, y: 450, width: 100, height: 20 },
      { x: 500, y: 400, width: 120, height: 20 },
      { x: 700, y: 350, width: 80, height: 20 },
      { x: 900, y: 300, width: 100, height: 20 },
      { x: 1100, y: 250, width: 150, height: 20 },
      { x: 1350, y: 320, width: 100, height: 20 },
      { x: 1550, y: 400, width: 120, height: 20 },
      { x: 1750, y: 200, width: 100, height: 20 },
      { x: 1950, y: 350, width: 200, height: 20 },
      { x: 2200, y: 450, width: 150, height: 20 }
    ]
    
    # 色
    @player_color = Gosu::Color::BLUE
    @ground_color = Gosu::Color::GREEN
    @platform_color = Gosu::Color::GRAY
    @bg_color = Gosu::Color::BLACK
    
    # Joy-Con接続状態表示用
    @font = Gosu::Font.new(20)
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
    handle_input
    handle_joycon_input
    
    # ジャンプクールダウン
    @jump_cooldown = [@jump_cooldown - 1, 0].max
    
    # 重力
    @player_vel_y += @gravity
    @player_y += @player_vel_y
    
    # 衝突判定
    handle_collisions
    
    # カメラの更新
    update_camera
    
    # ワールド境界
    @player_x = [@player_x, 0].max
    @player_x = [@player_x, @world_width - @player_width].min
  end
  
  def handle_joycon_input
    return unless @joycon_connected && @joycon_handle
    
    begin
      # データを読み取り
      data = @joycon_handle.read(49)
      
      return unless data && data.length >= 49 && data[0].ord == 0x30
      
      # Z軸加速度取得
      az_raw = (data[18].ord << 8) | data[17].ord
      az = (az_raw > 32767 ? az_raw - 65536 : az_raw) / 4000.0
      
      @current_accel_z = az
      
      # ジャンプ検出
      if az.abs > @jump_threshold && @on_ground && @jump_cooldown == 0
        @player_vel_y = @jump_power
        @on_ground = false
        @jump_cooldown = 30 
        puts "Joy-Conジャンプ検出！ Z軸: #{az.round(3)}G"
      end
      
    rescue => e
    end
  end
  
  def draw
    # カメラ
    translate(-@camera_x, -@camera_y) do
      # 背景を描画
      Gosu.draw_rect(-100, 0, @world_width + 200, @world_height, @bg_color)
      
      # 地面描画
      Gosu.draw_rect(0, @ground_y, @world_width, @world_height - @ground_y, @ground_color)
      
      # プラットフォーム描画
      @platforms.each do |platform|
        Gosu.draw_rect(platform[:x], platform[:y], platform[:width], platform[:height], @platform_color)
      end
      
      # プレイヤー描画
      Gosu.draw_rect(@player_x, @player_y, @player_width, @player_height, @player_color)
    end
    
    # UI表示
    status_text = @joycon_connected ? "Joy-Con: 接続中" : "Joy-Con: 未接続"
    status_color = @joycon_connected ? Gosu::Color::GREEN : Gosu::Color::RED
    @font.draw_text(status_text, 10, 10, 1, 1, 1, status_color)
    
    @font.draw_text("操作: ←→キーで移動、Joy-Conを振ってジャンプ", 10, 35, 1, 1, 1, Gosu::Color::WHITE)
    
    # デバッグ情報
    if @joycon_connected
      accel_text = "Z軸加速度: #{@current_accel_z.round(3)}G (閾値: #{@jump_threshold}G)"
      @font.draw_text(accel_text, 10, 60, 1, 1, 1, Gosu::Color::YELLOW)
      
      if @jump_cooldown > 0
        cooldown_text = "ジャンプクールダウン: #{@jump_cooldown}"
        @font.draw_text(cooldown_text, 10, 85, 1, 1, 1, Gosu::Color::RED)
      end
    end
  end
  
  private
  
  def handle_input
    # 左右移動
    if Gosu.button_down?(Gosu::KB_LEFT) || Gosu.button_down?(Gosu::KB_A)
      @player_x -= @player_speed
    end
    
    if Gosu.button_down?(Gosu::KB_RIGHT) || Gosu.button_down?(Gosu::KB_D)
      @player_x += @player_speed
    end
  end
  
  def button_down(id)
    # ESCキーで終了
    if id == Gosu::KB_ESCAPE
      close
    end
    
    # キーボードでのジャンプ
    if (id == Gosu::KB_SPACE || id == Gosu::KB_UP || id == Gosu::KB_J) && @on_ground
      @player_vel_y = @jump_power
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
    target_camera_x = @player_x - width / 2
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
