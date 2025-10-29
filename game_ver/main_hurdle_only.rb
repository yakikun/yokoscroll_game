require 'gosu'

# ハードルを飛び越すだけの最小限ゲーム
class HurdleOnlyWindow < Gosu::Window
  def initialize
    super 800, 600
    self.caption = "ハードルジャンプ練習"

    @ground_y = 500

    # プレイヤー
    @player_x = 100.0
    @player_w = 32
    @player_h = 48
    @player_y = @ground_y - @player_h
    @player_vel_y = 0.0
    @gravity = 0.6
    @jump_power = -12.0
    @on_ground = true

    # スクロール（地面は固定、障害物を左に動かす）
    @scroll_speed = 5.0

    # ハードル
    @hurdles = []
    @spawn_counter = 0
    @spawn_interval = 90 # フレーム間隔（ランダム化あり）

    @font = Gosu::Font.new(20)
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

    # 衝突判定
    @hurdles.each do |h|
      if rect_collision?(@player_x, @player_y, @player_w, @player_h, h[:x], h[:y], h[:w], h[:h])
        @game_over = true
      end
    end
  end

  def draw
    # 背景
    Gosu.draw_rect(0, 0, width, height, Gosu::Color::BLACK, 0)

    # 地面
    Gosu.draw_rect(0, @ground_y, width, height - @ground_y, Gosu::Color::GREEN, 0)

    # プレイヤー（矩形）
    Gosu.draw_rect(@player_x, @player_y, @player_w, @player_h, Gosu::Color::BLUE, 1)

    # ハードル描画
    @hurdles.each do |h|
      Gosu.draw_rect(h[:x], h[:y], h[:w], h[:h], Gosu::Color::FUCHSIA, 1)
    end

    # UI
    @font.draw_text("スコア: #{@score}", 10, 10, 2, 1, 1, Gosu::Color::YELLOW)
    if @game_over
      @font.draw_text("GAME OVER - Rでリスタート", width/2 - 140, height/2 - 10, 3, 1, 1, Gosu::Color::RED)
    else
      @font.draw_text("スペース/上キーでジャンプ", 10, 40, 2, 1, 1, Gosu::Color::WHITE)
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
    end
  end

  def jump
    @player_vel_y = @jump_power
    @on_ground = false
  end

  def spawn_hurdle
    w = rand(20..40)
    h = rand(40..80)
    x = width + 50
    y = @ground_y - h
    @hurdles << { x: x, y: y, w: w, h: h }
  end

  def rect_collision?(ax, ay, aw, ah, bx, by, bw, bh)
    ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by
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
end

# 実行
window = HurdleOnlyWindow.new
window.show
