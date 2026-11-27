# Handoff ให้ dev ทำแอปทางรอด

ทำข้อ 0–7 ใน [สเปกแอปทางรอด](thang-rot-spec.md) เป็นชุดเดียวใน `otonzgd2/Money-Anywhere` ตรวจรับตั้งแต่เปิดแอปจนเห็นแผนที่บันทึกแล้ว รันจาก checkout ของโปรเจกต์ เพราะชุดข้อมูลจำลองและหน้าทดลองเชื่อมแหล่งข้อมูลมีการแก้ไขอยู่ใน working tree

## เปิดไฟล์อ้างอิงและตรวจฐานโค้ด

1. เปิด [สเปกและเกณฑ์ตรวจรับ](thang-rot-spec.md) พร้อม [HTML อ้างอิงกรุงเทพฯ](../mockups/bangkok-opportunity-scope.html) ใช้หมวด เขต และโครงหน้า Info จาก HTML ส่วนรายการรวบรวมข้อมูลใน HTML เป็นบริบทสำหรับงานฐานข้อมูล
2. ใช้ภาพใน [โฟลเดอร์ assets](thang-rot-assets/) เมื่อทำ splash และ modal ภาพทั้งหมดอยู่ในชุดนี้แล้ว จัดภาพโลโก้และชื่อบริการให้อ่านได้ในจอเล็กและเมื่อเปิดตัวอักษรใหญ่
3. รัน `git status --short --branch` ก่อนแก้ ก่อนส่งต่องานนี้ checkout อยู่ที่ `e1c479a` บน `main` และมีงานค้างใน `app/lib/demo_sources_screen.dart`, `app/lib/common.dart`, `app/lib/me_tab.dart`, `contracts/adapters/gov-prefill-demo.js`, `contracts/fixtures/gov-prefill-demo.json` และไฟล์อื่น ตรวจ diff แล้วต่อยอดจากงานเดิม

## จุดเริ่มแก้ในระบบเดิม

| งาน | จุดที่มีอยู่และวิธีต่อ |
| --- | --- |
| เปิดแอปและจดจำสถานะ | `app/lib/main.dart` มี `MoneyAnywhereStartup` และ `Shell` อยู่แล้ว ใช้ startup เป็นจุดตัดสิน splash, modal และเส้นทางเข้า `OppTab` ใช้ local settings ของ `app/lib/api.dart` สำหรับสถานะ onboarding ชื่อ Android อยู่ใน `app/android/app/src/main/AndroidManifest.xml` ส่วน splash native อยู่ใน `app/android/app/src/main/res/` |
| Consent และคำตอบจำลอง | ใช้ source IDs ที่ `app/lib/demo_sources_screen.dart` และ `contracts/adapters/gov-prefill-demo.js` ใช้อยู่ `GET /v1/demo/personas/{id}` ส่งข้อมูลโชว์โปรไฟล์แต่ไม่มี `facts` เนื่องจาก `POST` เปลี่ยนข้อมูลของ device ID ให้ใช้ `Api.forDemo` พร้อม suffix เฉพาะ onboarding เพื่อแยกจากโปรไฟล์หลักและ Demo chat |
| คำนวณ | ใช้กฎจาก `contracts/adapters/money.js` ผ่าน `/v1/money/preview` และอ่านช่วงรายได้จากประกาศหรือ `/v1/plans/options` เรียกจากเส้นทาง startup โดยตรง แสดงผลใน `OppTab` ระวัง `RouteScreen` เดิมจะเขียน `facts` ที่ส่งเข้าไปหลังขอ consent จึงแสดงผลจำลองจาก preview โดยไม่ส่งไปเขียนผ่าน route เดิม |
| รายการและแผนที่ | แก้ `OppTab` ใน `app/lib/opp_tab.dart` และใช้ `OppMap` ใน `app/lib/opp_map.dart` ใช้ตารางรหัสหมวดในสเปก เพราะ `mapGroup` ใช้จัดห้าแถบโดยตรงไม่ได้ ตรวจทางลัดจาก `HomeTab` ที่ส่ง `job`, `skill` และ `all` ไปที่ `AppState.goTab` ตรวจผลค้นหาด้วยเขตและข้อมูลประกาศที่ผ่าน `contracts/adapters/job-catalogue.js` เมื่อมี SQLite |
| รายละเอียดและแผน | ย้ายจุดเปิด `OppScreen` ให้ส่งรหัสและบริบทเขตจากรายการและแผนที่ ตรวจจุดเรียกจาก `income_plan_screen.dart` และเส้นทางเปิดโดยตรงจาก `main.dart` ใช้ `saveToPlan` ใน `common.dart` เพื่อคงขั้นขอ consent และให้ `PlansTab` เห็นรายการที่บันทึก |

SQLite ใน checkout นี้เป็นฐานประกาศงานแบบเลือกเปิดผ่าน `JOB_DB_FILE` โดย `contracts/mock-server.js` ส่งข้อมูลผ่าน opportunity API อยู่แล้ว ฝั่ง Flutter ใช้ API ต่อได้โดยไม่เปิด SQLite เอง ถ้าต้องเติมฟิลด์ที่ API ยังไม่ส่ง ให้เพิ่มเฉพาะพารามิเตอร์ที่ UI ต้องใช้และรักษา payload เดิมที่ caller อื่นใช้อยู่

## ข้อ 7 จากแผนของฉัน

ดู [สเปก Info และข้อมูลติดต่อ](thang-rot-plan-info-spec.md) และ [DEMO แผน 10 หมวด](../mockups/index.html#plan-demo) ต่อจาก TaskScreen และ PlanContactScreen ให้ใช้ข้อมูลต้นทางชุดเดียวทั้งสองหน้า คงขั้นตอนและความคืบหน้าเดิมของแผน ตรวจ AC-10–AC-13 ร่วมกับข้อ 0–6

## นำ UI รายการแผนจาก DEMO เข้า Flutter

งานส่งต่อรอบนี้แก้แท็บ **แผนของฉัน** ใน `app/lib/plans_tab.dart` ให้ตรงกับ [สเปกหน้ารายการ](thang-rot-plan-info-spec.md) และ [ภาพอ้างอิง](thang-rot-assets/plan-list-reference.png) ใช้เส้นทางเปิด `TaskScreen` และ API ที่มีอยู่ ขอบเขตหน้ารายละเอียดและข้อมูลติดต่ออยู่ในข้อ 7 เดิม

ตรวจ AC-14–AC-17 ตรวจป้าย Demo และรายการจากทุกโปรไฟล์ที่ `PlansTab` โหลดอยู่แล้ว หากเติมหมวดใน TaskList ให้ทำเป็นฟิลด์ optional และใช้แคตตาล็อกเดิม พฤติกรรมตอนหมวดหายต้องยังเปิดแผนได้ รัน Flutter analyze, Flutter test และตรวจ Android เทียบกับ DEMO

## ตรวจส่งมอบชุดเดียว

- ใน `app/` รัน `flutter analyze` และ `flutter test` ตรวจกรณีในสเปกบน Android อย่างน้อยหนึ่งรอบตั้งแต่ cold start, ข้ามทุกแหล่ง, เลือกบางแหล่ง, เลือกตัวกรองงานสองประเภท, เปิดรายละเอียด และบันทึกแผน
- ถ้าแก้ API หรือ mock server ให้รัน `npm.cmd test` ใน `contracts/` ทดสอบทั้งข้อมูลที่ API อ่านจาก DB เดิมได้และสภาวะที่ยังไม่มี DB ยืนยันด้วยว่า fixture แผนที่ไม่ทำให้ UI เข้าใจว่าเป็นพิกัดจริง
- รายงานผลตรวจ ข้อสมมติที่ต้องเปลี่ยน และไฟล์ที่แก้ใน dev session ใช้ [คู่มือตั้งค่าใน repo](../guide/dev-setup.md) หากต้องหา Flutter SDK หรือคำสั่งเปิด demo server
