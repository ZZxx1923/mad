"""Wake-on-LAN: يرسل 'Magic Packet' لإيقاظ جهاز على نفس الشبكة المحلية."""
import socket


def wake(mac, broadcast="255.255.255.255", port=9):
    if not mac:
        raise ValueError("wol_mac غير مضبوط في config.json")

    clean = mac.replace(":", "").replace("-", "").replace(".", "").strip()
    if len(clean) != 12:
        raise ValueError(f"عنوان MAC غير صحيح: {mac}")

    # 6 بايت FF ثم تكرار عنوان MAC 16 مرة
    packet = bytes.fromhex("FF" * 6 + clean * 16)

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        s.sendto(packet, (broadcast, port))
    finally:
        s.close()


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("الاستخدام: python wol.py AA:BB:CC:DD:EE:FF [broadcast]")
        sys.exit(1)
    bcast = sys.argv[2] if len(sys.argv) > 2 else "255.255.255.255"
    wake(sys.argv[1], bcast)
    print("تم إرسال إشارة الإيقاظ إلى", sys.argv[1])
