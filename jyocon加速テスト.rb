require 'hidaping'
require 'csv'

begin
  joycon = HIDAPING.open(0x057e, 0x2007)
  if joycon
    puts "Joy-Con接続成功"
    CSV.open("accel_y.csv", "w") do |csv|
      csv << ["timestamp", "accel_y"]  # ヘッダー
      loop do
        data = joycon.read_timeout(49, 0.1)
        next unless data && data.length >= 49 && data[0].ord == 0x30

        ay_raw = (data[16].ord << 8) | data[15].ord
        ay = (ay_raw > 32767 ? ay_raw - 65536 : ay_raw) / 4000.0

        csv << [Time.now.strftime("%Y-%m-%d %H:%M:%S.%L"), ay.round(5)]
        puts "Accel Y: #{ay.round(3)}G"
      end
    end
  else
    puts "Joy-Conが見つかりません"
  end
rescue => e
  puts "エラー: #{e}"
ensure
  joycon.close if joycon
end