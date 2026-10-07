"""Wake-on-LAN: sends a 'magic packet' to wake a device on the same local network."""
import socket


def wake(mac, broadcast="255.255.255.255", port=9):
    if not mac:
        raise ValueError("wol_mac is not set in config.json")

    clean = mac.replace(":", "").replace("-", "").replace(".", "").strip()
    if len(clean) != 12:
        raise ValueError(f"invalid MAC address: {mac}")

    # 6 bytes of FF followed by the MAC repeated 16 times
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
        print("Usage: python wol.py AA:BB:CC:DD:EE:FF [broadcast]")
        sys.exit(1)
    bcast = sys.argv[2] if len(sys.argv) > 2 else "255.255.255.255"
    wake(sys.argv[1], bcast)
    print("Magic packet sent to", sys.argv[1])
