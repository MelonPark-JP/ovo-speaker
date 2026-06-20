#!/usr/bin/env python3
"""OVO (USBデジタルスピーカー) をamidi経由で直接MIDI制御するコマンドラインツール。
ブラウザのWeb MIDI APIに依存しないため、Firefoxなど非対応ブラウザの環境でも使える。
alsa-utilsのamidiコマンドのみを使用し、追加のインストールは不要。

対話メニュー: python3 ovo_cli.py
一発実行(スクリプトや `!` 経由でも使える): python3 ovo_cli.py status / led-brightness 5 等
"""
import argparse
import re
import subprocess
import sys

WAIT = 0.4


def find_port():
    out = subprocess.run(["amidi", "-l"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "OVO" in line:
            m = re.search(r"(hw:\d+,\d+,\d+)", line)
            if m:
                return m.group(1)
    return None


def raw_send(port, hex_bytes, wait=WAIT):
    """hex_bytesを送信し、wait秒間の応答を3バイトずつのメッセージのリストとして返す。"""
    proc = subprocess.run(
        ["amidi", "-p", port, "-S", hex_bytes, "-d", "-t", str(wait)],
        capture_output=True, text=True, timeout=wait + 3,
    )
    tokens = proc.stdout.split()
    values = [int(t, 16) for t in tokens]
    return [values[i:i + 3] for i in range(0, len(values) - 2, 3)]


def find_msg(msgs, controller_list):
    for m in msgs:
        if m[0] == 0xB0 and m[1] in controller_list:
            return m[1], m[2]
    return None, None


def query_option(port, idx):
    msgs = raw_send(port, f"B0 18 {idx:02X}")
    ctrl, val = find_msg(msgs, [0x19])
    if val is None:
        return None
    return (val >> 4) & 7


def send_option(port, idx, value):
    raw_send(port, f"B0 17 {((value & 7) << 4) + idx:02X}", wait=0.15)


def query_local_volume(port):
    msgs = raw_send(port, "B0 40 00")
    ctrl, val = find_msg(msgs, [0x41, 0x42])
    if val is None:
        return None
    return val + 100 if ctrl == 0x42 else val


def send_local_volume(port, value):
    if value >= 100:
        raw_send(port, f"B0 0B {(value - 100) & 0x7F:02X}", wait=0.15)
    else:
        raw_send(port, f"B0 07 {value & 0x7F:02X}", wait=0.15)


def query_analog_volume(port):
    msgs = raw_send(port, "B0 40 02")
    ctrl, val = find_msg(msgs, [0x4F, 0x50])
    if val is None:
        return None
    return val + 100 if ctrl == 0x50 else val


def send_analog_volume(port, value):
    if value >= 100:
        raw_send(port, f"B0 0C {(value - 100) & 0x7F:02X}", wait=0.15)
    else:
        raw_send(port, f"B0 08 {value & 0x7F:02X}", wait=0.15)


def query_led_brightness(port):
    msgs = raw_send(port, "B0 29 00")
    _, val = find_msg(msgs, [0x2A])
    return val


def send_led_brightness(port, value):
    raw_send(port, f"B0 24 {value & 0x0F:02X}", wait=0.15)


def query_led_pattern(port):
    msgs = raw_send(port, "B0 2B 00")
    _, val = find_msg(msgs, [0x2C])
    return val


def send_led_pattern(port, value):
    raw_send(port, f"B0 25 {value & 0x0F:02X}", wait=0.15)


def query_peq_enabled(port):
    msgs = raw_send(port, "B0 34 00")
    _, val = find_msg(msgs, [0x35])
    if val is None:
        return None
    return bool(val & 1)


def send_peq_enable(port, enabled):
    raw_send(port, f"B0 30 {1 if enabled else 0:02X}", wait=0.15)


def ask_int(prompt, lo, hi, default=None):
    suffix = f" [現在: {default}, Enterで維持]" if default is not None else ""
    while True:
        s = input(f"{prompt} ({lo}-{hi}){suffix}(qで戻る): ").strip()
        if s.lower() == "q":
            return None
        if s == "" and default is not None:
            return default
        try:
            v = int(s)
            if lo <= v <= hi:
                return v
        except ValueError:
            pass
        print("無効な値です。")


def ask_onoff(prompt, default=None):
    suffix = f" [現在: {'ON' if default else 'OFF'}, Enterで維持]" if default is not None else ""
    while True:
        s = input(f"{prompt} (on/off){suffix}(qで戻る): ").strip().lower()
        if s == "q":
            return None
        if s == "" and default is not None:
            return default
        if s in ("on", "1"):
            return True
        if s in ("off", "0"):
            return False
        print("on か off を入力してください。")


def fmt_bool(v):
    if v is None:
        return "不明（応答なし）"
    return "ON" if v else "OFF"


def fmt_val(v, unit=""):
    return "不明（応答なし）" if v is None else f"{v}{unit}"


LR_LABELS = {0: "通常", 1: "L/R反転", 2: "左のみ", 3: "右のみ"}


def show_status(port):
    print("\n=== 現在の設定 ===")
    print(f"LOCAL VOLUME      : {fmt_bool(query_option(port, 0))}")
    print(f"  レベル           : {fmt_val(query_local_volume(port))}")
    av = query_analog_volume(port)
    print(f"ANALOG VOLUME     : {fmt_val(av) if av is not None else '応答なし（アナログ入力未使用時は正常）'}")
    print(f"AUTO GAIN         : {fmt_bool(query_option(port, 1))}")
    print(f"BASS BOOST        : {fmt_val(query_option(port, 2))}")
    print(f"HIGH BOOST        : {fmt_val(query_option(port, 3))}")
    lr = query_option(port, 4)
    print(f"L/R SETTING       : {LR_LABELS.get(lr, '不明') if lr is not None else '不明（応答なし）'}")
    print(f"LOW POWER         : {fmt_bool(query_option(port, 5))}")
    print(f"PLAYER CONTROL    : {fmt_bool(query_option(port, 6))}")
    print(f"LED 輝度          : {fmt_val(query_led_brightness(port))}")
    print(f"LED パターン      : {fmt_val(query_led_pattern(port))}")
    print(f"イコライザ(PEQ)   : {fmt_bool(query_peq_enabled(port))}")
    print()


MENU = """
=== OVO 設定 CLI ===
 1) 現在の設定を表示
 2) LOCAL VOLUME (ON/OFF)
 3) LOCAL VOLUME レベル (0-200)
 4) ANALOG VOLUME レベル (0-126)
 5) AUTO GAIN (ON/OFF)
 6) BASS BOOST (0-3)
 7) HIGH BOOST (0-3)
 8) L/R SETTING (0:通常 1:反転 2:左のみ 3:右のみ)
 9) LOW POWER (ON/OFF)
10) PLAYER CONTROL (ON/OFF)
11) LED 輝度 (0-8)
12) LED パターン (0-3)
13) イコライザ(PEQ) ON/OFF
 0) 終了
"""


def connect():
    port = find_port()
    if not port:
        print("OVOが見つかりません。USBでデジタル入力モードで接続してから再実行してください。")
        print("(確認コマンド: amidi -l)")
        sys.exit(1)
    return port


def run_menu():
    port = connect()
    print(f"OVOに接続しました ({port})")

    while True:
        print(MENU)
        try:
            choice = input("番号を選択: ").strip()
        except EOFError:
            print("\n標準入力が閉じているため対話メニューを終了します。")
            print("一発実行したい場合は `python3 ovo_cli.py -h` でサブコマンド一覧を確認してください。")
            break
        port = find_port() or port  # 抜き挿しで番号が変わっても追従
        try:
            if choice == "0":
                break
            elif choice == "1":
                show_status(port)
            elif choice == "2":
                cur = query_option(port, 0)
                v = ask_onoff("LOCAL VOLUME", default=bool(cur) if cur is not None else None)
                if v is not None:
                    send_option(port, 0, 1 if v else 0)
            elif choice == "3":
                v = ask_int("LOCAL VOLUME レベル", 0, 200, default=query_local_volume(port))
                if v is not None:
                    send_local_volume(port, v)
            elif choice == "4":
                v = ask_int("ANALOG VOLUME レベル", 0, 126, default=query_analog_volume(port))
                if v is not None:
                    send_analog_volume(port, v)
            elif choice == "5":
                cur = query_option(port, 1)
                v = ask_onoff("AUTO GAIN", default=bool(cur) if cur is not None else None)
                if v is not None:
                    send_option(port, 1, 1 if v else 0)
            elif choice == "6":
                v = ask_int("BASS BOOST", 0, 3, default=query_option(port, 2))
                if v is not None:
                    send_option(port, 2, v)
            elif choice == "7":
                v = ask_int("HIGH BOOST", 0, 3, default=query_option(port, 3))
                if v is not None:
                    send_option(port, 3, v)
            elif choice == "8":
                v = ask_int("L/R SETTING", 0, 3, default=query_option(port, 4))
                if v is not None:
                    send_option(port, 4, v)
            elif choice == "9":
                cur = query_option(port, 5)
                v = ask_onoff("LOW POWER", default=bool(cur) if cur is not None else None)
                if v is not None:
                    send_option(port, 5, 1 if v else 0)
            elif choice == "10":
                cur = query_option(port, 6)
                v = ask_onoff("PLAYER CONTROL", default=bool(cur) if cur is not None else None)
                if v is not None:
                    send_option(port, 6, 1 if v else 0)
            elif choice == "11":
                v = ask_int("LED 輝度", 0, 8, default=query_led_brightness(port))
                if v is not None:
                    send_led_brightness(port, v)
            elif choice == "12":
                v = ask_int("LED パターン", 0, 3, default=query_led_pattern(port))
                if v is not None:
                    send_led_pattern(port, v)
            elif choice == "13":
                v = ask_onoff("イコライザ(PEQ)", default=query_peq_enabled(port))
                if v is not None:
                    send_peq_enable(port, v)
            else:
                print("無効な選択です。")
        except subprocess.TimeoutExpired:
            print("amidiの応答がタイムアウトしました。USB接続を確認してください。")


def onoff(s):
    if s.lower() in ("on", "1"):
        return True
    if s.lower() in ("off", "0"):
        return False
    raise argparse.ArgumentTypeError("on か off を指定してください")


def build_parser():
    p = argparse.ArgumentParser(
        description="OVO USBスピーカーをamidi経由で直接MIDI制御するCLI。"
        "引数なしで実行すると対話メニュー、サブコマンドを指定すると一発実行します。"
    )
    sub = p.add_subparsers(dest="command")

    sub.add_parser("menu", help="対話メニューを起動する")
    sub.add_parser("status", help="現在の設定を一覧表示する")

    s = sub.add_parser("local-volume", help="LOCAL VOLUMEのON/OFF")
    s.add_argument("value", type=onoff)

    s = sub.add_parser("local-volume-level", help="LOCAL VOLUMEレベル (0-200)")
    s.add_argument("value", type=int)

    s = sub.add_parser("analog-volume-level", help="ANALOG VOLUMEレベル (0-126)")
    s.add_argument("value", type=int)

    s = sub.add_parser("auto-gain", help="AUTO GAINのON/OFF")
    s.add_argument("value", type=onoff)

    s = sub.add_parser("bass-boost", help="BASS BOOST (0-3)")
    s.add_argument("value", type=int)

    s = sub.add_parser("high-boost", help="HIGH BOOST (0-3)")
    s.add_argument("value", type=int)

    s = sub.add_parser("lr-setting", help="L/R SETTING (0:通常 1:反転 2:左のみ 3:右のみ)")
    s.add_argument("value", type=int)

    s = sub.add_parser("low-power", help="LOW POWERのON/OFF")
    s.add_argument("value", type=onoff)

    s = sub.add_parser("player-control", help="PLAYER CONTROLのON/OFF")
    s.add_argument("value", type=onoff)

    s = sub.add_parser("led-brightness", help="LED輝度 (0-8)")
    s.add_argument("value", type=int)

    s = sub.add_parser("led-pattern", help="LEDパターン (0-3)")
    s.add_argument("value", type=int)

    s = sub.add_parser("peq", help="イコライザ(PEQ)のON/OFF")
    s.add_argument("value", type=onoff)

    return p


def main():
    parser = build_parser()
    args = parser.parse_args()

    if args.command is None:
        if sys.stdin.isatty():
            run_menu()
        else:
            print("標準入力がターミナルではないため対話メニューは使えません。")
            print("サブコマンドを指定して一発実行してください（例: python3 ovo_cli.py status）。\n")
            parser.print_help()
        return

    if args.command == "menu":
        run_menu()
        return

    port = connect()

    if args.command == "status":
        show_status(port)
    elif args.command == "local-volume":
        send_option(port, 0, 1 if args.value else 0)
    elif args.command == "local-volume-level":
        send_local_volume(port, args.value)
    elif args.command == "analog-volume-level":
        send_analog_volume(port, args.value)
    elif args.command == "auto-gain":
        send_option(port, 1, 1 if args.value else 0)
    elif args.command == "bass-boost":
        send_option(port, 2, args.value)
    elif args.command == "high-boost":
        send_option(port, 3, args.value)
    elif args.command == "lr-setting":
        send_option(port, 4, args.value)
    elif args.command == "low-power":
        send_option(port, 5, 1 if args.value else 0)
    elif args.command == "player-control":
        send_option(port, 6, 1 if args.value else 0)
    elif args.command == "led-brightness":
        send_led_brightness(port, args.value)
    elif args.command == "led-pattern":
        send_led_pattern(port, args.value)
    elif args.command == "peq":
        send_peq_enable(port, args.value)

    if args.command != "status":
        print("設定しました。")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n中断しました。")
    except subprocess.TimeoutExpired:
        print("amidiの応答がタイムアウトしました。USB接続を確認してください。")
