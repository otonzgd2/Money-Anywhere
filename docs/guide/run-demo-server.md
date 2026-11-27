# รัน server สำหรับ Demo และให้มือถือเรียกได้

## เริ่ม server

```powershell
cd contracts
npm.cmd install      # ครั้งแรกครั้งเดียว
npm.cmd run mock     # สั่งดึงงานเอง หรือกำหนด LIVE=1 และ JOB_AUTO_SYNC=1 เพื่อเปิดรอบ Greenhouse/Lever
```

ตอนเริ่ม server พิมพ์ที่อยู่ให้ 3 แบบ:

- `http://localhost:8080` ใช้บนโน้ตบุ๊ก (เอกสาร API อยู่ที่ `/docs`)
- `http://10.0.2.2:8080` ใช้จาก Android emulator
- `http://192.168.x.x:8080` ใช้จากมือถือจริงที่ต่อ Wi-Fi เดียวกัน

ข้อมูลของผู้ใช้เก็บที่ `contracts/.data/state.json` ปิดแล้วเปิดใหม่ข้อมูลยังอยู่ ลบไฟล์นี้เพื่อเริ่มใหม่
ไฟล์นี้อยู่ใน `.gitignore` จะไม่ขึ้น GitHub

## มือถือต่อคนละเครือข่าย (เช่นวัน demo ที่ใช้ 4G)

ใช้ tunnel ฟรี ตัวอย่าง Cloudflare quick tunnel (ไม่ต้องสมัคร):

```powershell
winget install Cloudflare.cloudflared
cloudflared tunnel --url http://localhost:8080
```

คำสั่งจะพิมพ์ URL `https://....trycloudflare.com` ให้เอา URL นี้ไปใส่เป็น `API_BASE_URL` ของแอป
URL เปลี่ยนทุกครั้งที่รันใหม่ ยังไม่ได้ทดลองในโปรเจกต์นี้ (TB.16)

ถ้า Windows Firewall ถามตอนเริ่ม server ให้อนุญาต Private network มือถือใน Wi-Fi เดียวกันจึงจะเรียกได้

## ตรวจว่าระบบพร้อม

เปิด `http://localhost:8080/v1/health` ดูค่าเหล่านี้:

| ค่า | ความหมาย |
|---|---|
| `store: file` | เก็บข้อมูลถาวรอยู่ (`memory` = ปิดแล้วหาย) |
| `ai.provider` | `rules` = ยังไม่มี key AI ใช้กฎแทน |
| `notifier: mock` | การเตือนถูกบันทึกแต่ยังไม่ส่งเข้ามือถือ |
| `jobs` | งานตามรอบ เวลาที่รันล่าสุด และผลล่าสุด |

ตัวแปรทั้งหมดอยู่ใน `.env.example`
