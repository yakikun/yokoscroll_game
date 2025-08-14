# ファイル名: joycon_detector.py
import hid
import time
import sys

def find_joycon_r():
    for device in hid.enumerate(0x0, 0x0):
        if device['vendor_id'] == 0x057e and device['product_id'] == 0x2007:
            return device
    return None

def main():
    joycon_info = find_joycon_r()
    if not joycon_info:
        print("JOYCON_NOT_FOUND", file=sys.stderr)
        return

    try:
        h = hid.device()
        h.open(joycon_info['vendor_id'], joycon_info['product_id'])
        h.send_feature_report([0x01, 0x48, 0x00, 0x01, 0x40, 0x40, 0x00, 0x01, 0x40, 0x40, 0x00])

        accel_threshold = 5000 
        
        # クールダウン時間（秒）
        cooldown_time = 0.5 
        # 最後にジャンプを検知した時刻
        last_jump_time = 0

        while True:
            report = h.read(64)
            if report and len(report) > 18:
                accel_z_raw = int.from_bytes(report[17:19], byteorder='little', signed=True)
                
                # ジャンプを検知し、かつクールダウン期間が終了していれば
                if accel_z_raw > accel_threshold and (time.time() - last_jump_time) > cooldown_time:
                    print("JUMP")
                    sys.stdout.flush()
                    last_jump_time = time.time() # 最後のジャンプ時刻を更新

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
    finally:
        if 'h' in locals() and h.is_open():
            h.close()

if __name__ == "__main__":

    main()
