# Handoff ให้ dev ทำแอปทางรอด

แบบ UI ปัจจุบันและรายการปรับทุกหน้าที่ผู้ใช้เข้าถึงได้อยู่ใน [handoff เปลี่ยน UI ทางรอดทั้งระบบ](thang-rot-ui-refresh.md) ใช้รายละเอียดด้านล่างประกอบการคงพฤติกรรมเดิม

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

## นำ UI โปรไฟล์และบัญชีที่เชื่อมต่อจาก DEMO เข้า Flutter

ทำสองหน้าพร้อมกันใน checkout `D:/Money-Anywhere` จาก `main` ที่ตรวจล่าสุดด้วย commit `ce7318c` ใช้ [DEMO ล่าสุด](../mockups/index.html) กับ [สเปกโปรไฟล์และเกณฑ์ AC-18–AC-23](thang-rot-spec.md#โปรไฟล์และบัญชีที่เชื่อมต่อ) เปิด DEMO ผ่าน **ลองเปิดแอปครั้งแรก** แล้วเข้าแท็บ **ฉัน** ตรวจ diff ก่อนแก้ เพราะสเปกและ DEMO ล่าสุดอยู่ใน working tree

| จุดแก้ | วิธีต่อ |
| --- | --- |
| `app/lib/me_tab.dart` | วางส่วน **บัญชีที่เชื่อมต่อ** บนแท็บ **ฉัน** ใช้ไอคอนเดิมกับลำดับจาก `DemoSource.values` แสดงจำนวนจากสถานะที่ยืนยันแล้ว 4 แถว และกางเฉพาะบริการที่เชื่อมสำเร็จ ให้ลิงก์จากโปรไฟล์กลับมาที่หัวข้อนี้โดยตรง คงเมนูจัดการเดิมและ `SourcesScreen` สำหรับหน้า **แหล่งข้อมูลของแอป** |
| `app/lib/profile_overview_screen.dart` และ `app/lib/profile_screen.dart` | ใช้การ์ดและตำแหน่งปุ่มตาม DEMO ให้หน้าโปรไฟล์หลักเลือกโหมดจาก snapshot เดียวกับแท็บ **ฉัน** ใช้ `ProfileDemo.fromResponse` และ `ThaidProfileIdentity` ตามความเหมาะสม เปลี่ยนทางโหลด `ProfileSnapshot._loadExample` ที่ขอข้อมูลครบสี่แหล่งโดยปริยายออกจากโปรไฟล์ผู้ใช้ เปิดตัวอย่างเดิมได้ผ่านทางเข้า DEMO ที่ตั้งใจเลือก |
| `app/lib/main.dart`, `app/lib/api.dart` และ `app/lib/opportunity_assessment.dart` | ใช้ค่าที่บันทึกผ่าน `Api.onboardingChoices` (`y` เชื่อม, `n` ข้าม, ลำดับ `thaid`, `tangRat`, `socialSecurity`, `dMyTax`) ร่วมกับผลโหลดเพื่อสร้างสถานะต่อบริการ ใช้ร่วมกันทั้งสองหน้ารวมถึงหลังเปิดแอปใหม่ เก็บเฉพาะคำตอบและข้อมูลที่จำเป็น ให้ผลจากคำขอเก่าหมดอายุเมื่อเปลี่ยนชุดที่เลือก โหมด ฐาน URL หรือหลังลบข้อมูล |
| `app/lib/thaid.dart`, `contracts/mock-server.js` และ adapters ที่เกี่ยวข้อง | ใช้ `/v1/me/gov-link` สำหรับสถานะเชื่อม ThaID ที่ระบบรองรับ แยกค่าจาก ThaID ไว้ในผลจาก provider และเก็บค่าที่ผู้ใช้เคยกรอกด้วยสัญญาโปรไฟล์กับ facts เดิม ตรวจผู้เรียกเดิมก่อนปรับรูปแบบการเขียน |

**การดึงข้อมูลจำลอง** เปิดตามเงื่อนไขเดียวกับ startup และ feature flag ใช้ `GET /v1/demo/personas/gov-prefill?sources=…` โดยส่งเฉพาะ source ID ที่ผู้ใช้เลือกเสมอ การละ `sources` จะได้ตัวอย่างทุกบริการ ข้ามการเรียกนี้หากไม่มีบริการที่เลือก ตรวจ `dataStatus: mock` แล้วจับคู่ `sources[].field` ได้แก่ `identity`, `disabilityCard`, `ss33` และ `taxWithheld` ตามลำดับ ใช้ `identity` ของ ThaID สำหรับชื่อ อายุ และเขตตามสิทธิ์ ใช้ `checkedAt` เมื่อมีผลจริงใน payload ค่าที่แหล่งรายงานว่ายังไม่มีข้อมูลแสดงตามนั้น ส่วนแหล่งที่ควรได้รับผลแต่ไม่มี response รายบริการให้แสดงว่าโหลดไม่ได้ ห้ามใช้ `POST /v1/demo/personas/*` เพื่ออ่านโปรไฟล์หรือรายการบัญชี เพราะคำขอนี้เขียนทับ state ของ device ที่รับคำขอ

**การบันทึกโปรไฟล์** คง consent และ validation เดิม ใช้ `GET/PUT /v1/me/profile` และ `/v1/me/facts` ตามเจ้าของข้อมูล ตรวจว่า `PUT` เดิมแทนที่ทั้งโปรไฟล์ การบันทึกเฉพาะงานและรายได้ต้องรักษาค่าที่ไม่ได้แก้ไว้ และต้องไม่ส่ง claims จาก ThaID กลับเป็นค่าที่ผู้ใช้กรอก `displayName` ที่ผู้ใช้ตั้งเอง เขตที่อาศัย และช่วงอายุที่กรอกต้องแยกออกจาก claims ของ ThaID ทาง API ต้องรักษาค่าจาก provider เมื่อมีคำขอแก้จากไคลเอนต์ การยกเลิกเชื่อมหรือลบความยินยอมต้องล้างค่าจาก provider ใน UI และคืนแบบแก้ไขจากค่าที่ผู้ใช้เคยกรอก แจ้งผลสำเร็จหลังข้อมูลบันทึกสำเร็จทุกส่วน และรองรับการลองใหม่เมื่อบันทึกบางส่วนไม่ผ่าน

**การแยกโหมดและการล้างข้อมูล** ในโหมด `user` ใช้ข้อมูลที่ยืนยันได้จากตัวเชื่อมที่มีจริงในระบบ คำตอบ onboarding และข้อมูลจำลองไม่ใช้ยืนยันบัญชีจริง รักษาเส้นทาง consent, refresh, disconnect และ Demo scenario เดิม เมื่อ **ลบข้อมูลทั้งหมด** สำเร็จ ให้ล้างตัวเลือก onboarding และ snapshot รวมถึง state ของ demo device ที่ startup สร้างไว้ตามขอบเขตเดิมของการลบ ตรวจว่าไม่มีผลโหลดเก่ากลับมาเขียน snapshot หลังลบ

ส่งงานส่วนนี้เป็นชุดเดียว รัน `flutter analyze`, `flutter test` และ `npm.cmd test` ใน `contracts/` หากแตะสัญญาหรือ mock server ตรวจ AC-18–AC-23 บน Android เทียบภาพอ้างอิง รวมจอแคบ ขนาดตัวอักษรใหญ่ และการเปิดใหม่ รายงานผลและกรณีที่ตรวจไม่ได้ งานนี้ใช้ API ที่มีอยู่ ไม่ต้องตั้งฐานข้อมูลหรือเปิดการเชื่อมกับหน่วยงานใหม่

## ตรวจส่งมอบชุดเดียว

- ใน `app/` รัน `flutter analyze` และ `flutter test` ตรวจกรณีในสเปกบน Android อย่างน้อยหนึ่งรอบตั้งแต่ cold start, ข้ามทุกแหล่ง, เลือกบางแหล่ง, เลือกตัวกรองงานสองประเภท, เปิดรายละเอียด และบันทึกแผน
- ถ้าแก้ API หรือ mock server ให้รัน `npm.cmd test` ใน `contracts/` ทดสอบทั้งข้อมูลที่ API อ่านจาก DB เดิมได้และสภาวะที่ยังไม่มี DB ยืนยันด้วยว่า fixture แผนที่ไม่ทำให้ UI เข้าใจว่าเป็นพิกัดจริง
- รายงานผลตรวจ ข้อสมมติที่ต้องเปลี่ยน และไฟล์ที่แก้ใน dev session ใช้ [คู่มือตั้งค่าใน repo](../guide/dev-setup.md) หากต้องหา Flutter SDK หรือคำสั่งเปิด demo server
