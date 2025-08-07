require 'gosu'
require 'open3'

class GameWindow < Gosu::Window
  def initialize
    # ウィンドウサイズ
    super 800, 600
    self.caption = "横スクロールアクションRPG"
    
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
    @bg_color = Gosu::Color::CYAN

    # Pythonスクリプトを起動
    @stdin, @stdout, @stderr, @wait_thread = Open3.popen3('python joycon_detector.py')
    @joycon_connected = true
    @joycon_jump_triggered = false
  end
  
  def update
    handle_input
    
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

    if @joycon_connected
      begin
        output = @stdout.read_nonblock(1024)
        if output.strip == "JUMP"
          @joycon_jump_triggered = true
        end
      rescue IO::WaitReadable
      rescue => e
        puts "Error reading from Python script: #{e}"
        @joycon_connected = false
      end
    end
    
    # Joy-Conジャンプ信号
    if @joycon_jump_triggered && @on_ground
      @player_vel_y = @jump_power
      @on_ground = false
      @joycon_jump_triggered = false
    end
  end
  
  def draw
    # カメラ
    translate(-@camera_x, -@camera_y) do
      # 背景を描画（少し広めに）
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
    
    # キーボード操作用
    # if (id == Gosu::KB_SPACE || id == Gosu::KB_UP || id == Gosu::KB_J) && @on_ground
    #   @player_vel_y = @jump_power
    #   @on_ground = false
    # end
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
    # Pythonプロセスを終了させる
    if @joycon_connected
      @stdin.close
      @stdout.close
      @stderr.close
      @wait_thread.kill
    end
    super
  end
end

# ゲームを開始
window = GameWindow.new
window.show