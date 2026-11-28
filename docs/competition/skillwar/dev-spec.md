# Dev spec สำหรับสร้างทางรอดให้เทียบ Demo

สเปกนี้ถอดจาก Flutter และ API 0.15.0 ใน [commit อ้างอิง](https://github.com/otonzgd2/Money-Anywhere/tree/8efb63bb57e88fcb8cfd489d155ffe9cba025401) เมื่อรายละเอียดเก่าขัดกัน ให้ตรวจหน้าจอ Flutter และผลจาก runtime commit นี้ แล้วบันทึกข้อตกลงที่จะเปลี่ยนสำหรับวันแข่ง การสร้างครบ 100% หมายถึงผ่านทุกข้อในตารางและการตรวจ Android ด้านล่าง

## โครงระบบและลำดับสร้าง

| หน่วย | ขอบเขตและไฟล์อ้างอิงใน commit |
| --- | --- |
| Android Flutter | `app/pubspec.yaml` และ lockfile, `app/lib/main.dart`, `app/lib/api.dart`, `app/android/`, `app/assets/thang-rot/` |
| API HTTP และ config | `contracts/openapi.yaml` ครอบคลุม 50 operations, `app-config.schema.json`, `app-config.sample.json`, `mock-server.js` |
| ตรรกะสิทธิและ AI | `contracts/adapters/{money,profile-facts,chat-intent,guard,agent,ai,responses,gov-prefill-demo,demo-tax}.js` |
| ฐานงานและข้อมูลสาธารณะ | `contracts/adapters/job-catalogue.js`, `contracts/fixtures/`, `docs/entities/database-script/`, `docs/product/sources/`, `docs/mockups/{opportunity-info,job-application}.html` |
| ข้อมูลผู้ใช้ | `contracts/adapters/store.js` แบบ memory หรือ JSON layout 2 มี identity, profile, activity, runtime แยกต่อ device |

1. สร้าง shell Android, config และ client. ให้ health, consent และ privacy อ่านได้ก่อน
2. ทำ facts, consent, data sources และเครื่องคำนวณสิทธิ. เขียน contract tests ก่อนต่อ UI
3. ทำ catalogue, source detail, contact และ actions ของ saved plan
4. ทำ guided orchestration แล้วต่อ model adapter. เก็บ tests ของ intake, tool calls, fallback และการยืนยัน
5. ต่อ profile, settings, export/delete และ demo mode. เดินชุดเทียบ Demo ด้วย endpoint จริงและ Android

## Shell และ API client

- ชื่อไทย **ทางรอด** ใช้ splash พื้น `#FAFAFA` โลโก้กลาง 136 logical px และ Material 3 สีตั้งต้น `#0E9F6E` เก็บชุด asset ตาม path เดิมโครงการ ตรา ThaID, ทางรัฐ, ประกันสังคม และ D-MyTax มาจาก `app/assets/thang-rot/` โหมดตัวอักษรใหญ่คูณ 1.3
- Cold start เปิดแท็บ **โอกาส** ที่ **ทั้งหมด** แถบล่างเรียง **หน้าแรก**, **โอกาส**, **แผนของฉัน**, **ฉัน** เก็บ state ของแท็บระหว่างสลับ ใช้ lazy IndexedStack ในต้นแบบ เมื่อเปิดหน้ารายละเอียดให้ซ่อนแถบล่าง Android back จากแท็บอื่นใน shell กลับหน้าแรก รองรับเส้นทางเปิดโอกาสด้วย ID และ `districtCode`
- อ่าน `GET /v1/app-config` ก่อนเปิด Demo UI ยอมรับ mode `demo` หรือ `user` และ demo flag แบบ Boolean ใช้ timeout 5 วินาที หากขาดหรือผิดรูปให้ catalogue ใช้ต่อได้ มีปุ่ม retry สถานะ Demo เปิดเมื่อ mode และ flag อนุญาตทั้งคู่
- ส่ง `X-Device-Id` เสมอสำหรับ endpoint ผู้ใช้ เก็บ device ID สุ่มและ URL ไว้ที่ private storage ของแอป ผ่าน Android channel `money_anywhere/local_settings` ค่าเริ่ม USB `http://127.0.0.1:8080` ใช้ `API_BASE_URL`, `WIFI_API_BASE_URL` และ URL ที่ตั้งเองตาม `Api._loadBaseUrl` ทดสอบจำค่า เปลี่ยน Wi-Fi และคืนค่า USB จาก `api_settings_test.dart`
- แยก device ของ onboarding `-demo-thang-rot-onboarding`, guided demo `-demo-gov-prefill-chat`, selection `-demo-gov-prefill-selection` และ D-MyTax `-demo-dmytax` เก็บข้อมูลผู้ใช้หลักไว้ต่างหาก หน้า **ข้อมูลที่เก็บไว้** อ่าน export API ของ device หลักและแสดงสรุปใน dialog คำสั่งลบครอบคลุม device หลักและ demo scopes ทั้งสี่

## ตารางหน้าจอและพฤติกรรม

| จอ | สิ่งที่ต้องเกิด | จุดตรวจอ้างอิง |
| --- | --- | --- |
| หน้าตั้งค่าข้อมูลครั้งแรก | ถาม 4 แหล่งตามลำดับ ThaID, ทางรัฐ, ประกันสังคม, D-MyTax มีเชื่อม/ไม่เชื่อม/ไว้ทีหลัง เก็บความคืบหน้าทุกข้อแบบ atomic และเปิดต่อจากจุดเดิม | `main.dart`, `opportunity_assessment.dart`, `thang_rot_flow_test.dart` |
| ประเมินก่อนเข้าโอกาส | โหลดเฉพาะแหล่งที่เลือกบน onboarding scope แล้ว `POST /v1/money/preview` ด้วย facts จำลอง ข้ามทั้งหมดใช้ `GET /v1/money` ของผู้ใช้ แยกยอดรายเดือน ยอดครั้งเดียว และรายการรอตรวจ แสดง mock แม้กฎเป็น curated ส่วนแผนรายได้โหลดขนานและล้มแยกได้ มี timeout 8 วินาทีและ retry | `opportunity_assessment.dart` |
| หน้าแรก | ทางเข้าคุย, เช็กสิทธิเอง, และหาโอกาสตามทักษะ ฐานผู้ใช้ว่างและเปิด Demo จึงเสนอ mock profile ตามตัวเลือก ให้เลือกข้อมูลของฉันได้ สำหรับ mock chat โหลด persona เมื่อยังไม่พบและใช้ scope เดิมซ้ำ | `home_tab.dart`, `home_demo_chat_test.dart` |
| แชต | แสดงข้อความไทย, chips, สถานะกำลังตรวจ, ผลจากกฎหรือ AI และ action cards ผูก quick reply กับ `step.id` ตอนที่แสดง ส่ง `stepId` ใน payload ส่วน free text ส่ง `text` ได้ ตรวจ/ปิดบังข้อความอ่อนไหว เมื่อ conversation หายให้เริ่มใหม่โดยคง facts ที่บันทึกได้ | `chat.dart`, `thang_rot_guard_handoff_test.dart` |
| เช็กสิทธิเอง | ใช้ preview ที่ยังไม่บันทึก ปรับคำตอบและเปิดเหตุผล/เอกสาร ขอ consent ก่อนบันทึก facts หรือเริ่มแผน สิทธิที่ได้รับอยู่แยกจากเงินใหม่ | `money_check.dart`, `route_screen.dart`, `money.dart` |
| โอกาสแบบรายการ | ลำดับ **ทั้งหมด**, **สิทธิ์และสวัสดิการ** (1–3), **หางาน** (4–6), **ขายสินค้า** (7), **อื่นๆ** (8–10) งานเลือกหลายประเภทได้ รวมผลตาม ID รักษาเขต หมวด คำค้น และ pagination เมื่อกลับจากรายละเอียด ซ่อนหมดอายุและเสี่ยงตามค่าเริ่ม | `opp_tab.dart`, `opportunity_catalog.dart` |
| โอกาสแบบแผนที่ | ขอ district pins จาก API แยกหมุดรวมเขตจากตำแหน่งประกาศจริง กดหมุดไปกรองรายการ เมื่อไม่มีหมุดยังมีรายการ แผนที่ OpenStreetMap ต้องมีอินเทอร์เน็ตและแสดง attribution | `opp_tab.dart`, `opp_map.dart` |
| รายละเอียด | อ่าน item ตาม ID และเขต แสดงสถานะ แหล่งและวันตรวจ เงื่อนไข เอกสาร และ contact เก็บบริบทตอนบันทึก แยก 404/410 ออกจากข้อผิดพลาดชั่วคราว แสดง retry เมื่อเหมาะสม | `opp_screen.dart`, `plan_info.dart` |
| สมัครงาน Demo | เปิด Info ของรายการบางนาที่ backend ชี้ให้ กรณีลิงก์จริงเปิดไม่ได้ใน Demo มีตัวอย่างสมัครงานของ repo ที่ใส่ชื่อประกาศเดียวกันและป้ายจำลอง ให้เปิดเมื่อผู้ใช้กด | `job_application.dart`, `docs/mockups/job-application.html` |
| แผนของฉัน | รวมแผนจาก device หลักและสาม demo chat/selection scopes แสดงกลุ่ม active, blocked, snoozed และ finished ตามลำดับ มี progress, next step, empty, partial error และ refresh | `plans_tab.dart`, `plans_tab_test.dart` |
| ขั้นตอนและข้อมูลติดต่อ | อ่านรายละเอียด task กับ source แยกสถานะ source ออกจาก progress เปิด contact ตามชนิด เก็บงานที่ประกาศหมดอายุหรืออ่านไม่ได้ ให้ทำเครื่องหมายขั้นตอน ย้อน เลื่อน ต่อ บล็อก รายงานผล และลบ | `task_screen.dart`, `plan_contact_screen.dart`, `task_contact_test.dart` |
| เป้ารายได้ | รับจำนวนและช่วงเวลา แสดงช่วงต่ำ–สูง ความเป็นไปได้ ช่องว่าง สมมติฐาน และแยกที่มารายรับ รายการคำนวณเองยังใช้ได้ | `income_plan_screen.dart`, `GET /v1/plans/goal` |
| ฉันและโปรไฟล์ | โปรไฟล์กรอกเองหรือ facts จากบัญชีที่เชื่อม แสดงวันอ้างอิงและสถานะ conflict/stale รักษาข้อมูล identity แบบอ่านอย่างเดียว แก้ fields ที่ผู้ใช้เป็นเจ้าของ | `me_tab.dart`, `profile_overview_screen.dart`, `profile_screen.dart`, `profile_fact_details.dart` |
| บัญชี, settings และ privacy | โชว์ connected, disconnected, skipped, loading และ retry รายแหล่ง มีโหมด D-MyTax แบบสลับก่อน/หลัง เก็บแผนเดิมเมื่อขอ `keepPlans=true` ตั้ง URL และตัวอักษร จัดการ consent, memory, export และ delete | `connected_accounts.dart`, `connected_account_row.dart`, `me_tab.dart`, `profile_overview_test.dart` |

## ตรรกะแชตและสัญญาการเขียนข้อมูล

1. อ่านสถานะ consent และ normalize ข้อความภาษาไทย ตรวจข้อมูลอ่อนไหว prompt injection เรื่องนอกขอบเขต การการันตี และเงินกู้
2. จัดเจตนาเป็นสิทธิ งาน แผนรายได้ หรือความช่วยเหลือ เก็บเจตนากับ field ที่รออยู่ แยกใครเป็นเจ้าของคำขอ รับตัวเลขไทยและเลขมีจุลภาค เวลาแบบรายเดือน เงินก้อน และถึงวันกำหนดใช้วันกรุงเทพฯ
3. รวม facts ผู้ใช้กับ facts จากแหล่งที่เลือกตามที่มา อายุข้อมูลและช่วงเวลา ให้กฎตอบหรือถามเท่าที่ขาด ค่าเงินสิทธิได้จาก `money.js` และกฎตาม source ส่วน D-MyTax ได้ข้อมูลภาษีหักไว้และสถานะตรวจยอดคืน
4. เมื่อเข้าเส้นทาง model หลัง consent ให้เรียก tool ตามเจตนา เช่น `search_opportunities` แล้วให้โมเดลอธิบายผลจาก candidates ที่ได้รับ เทิร์น “ดูงานอื่น” ตัด IDs ที่เพิ่งเสนอและคงเจตนาค้นงาน รุ่นอ้างอิงส่ง ID, title, money, distanceKm และ dataStatus ให้โมเดล สำหรับ build วันแข่ง ให้ UI แสดงผลเป็นการ์ดที่ใช้ ID ไปโหลด source URL และ provenance จากรายการจริง
5. ตรวจตัวเลข URL โทรศัพท์ และ source ID เทียบกับ tool data ก่อนแสดง หาก quota, timeout หรือ model ผิดรูปให้ fallback พร้อมสถานะ ใช้ `aiStatus` จริงและเก็บ trace ของสิ่งที่เรียก
6. เมื่อต้องเขียน ให้เสนอ action ก่อน ใช้ `POST /v1/ai/conversations/{id}/actions/{actionId}` สำหรับ confirm/reject. Confirm เรียก service ปกติ Reject คงข้อมูลเดิม การยืนยันซ้ำคืนผลเดิม การตัดสินซ้ำคนละแบบคืน 409
7. API คืนผลเดิมเมื่อ replay task event ด้วย `Idempotency-Key` เดิม Flutter สร้าง key ใหม่เมื่อผู้ใช้กดอีกครั้ง การใช้ key เดิมสำหรับ retry หลังการตอบกลับขาดหายเป็นงานปรับปรุงใน build วันแข่ง Quick reply เก่ายึด step เดิมและไม่ข้ามไปตอบ step ถัดไป การถอน consent ระหว่าง call ทิ้งผลที่กำลังค้าง

## API และ fallback

| กลุ่ม | Endpoint หรือ contract | ลักษณะสำคัญ |
| --- | --- | --- |
| Bootstrap | `GET /v1/health`, `/v1/app-config`, `/v1/taxonomies`, `/v1/privacy/notice` | health เป็น readiness, config มี mode กับ flags และ noticeVersion |
| Profile | `GET/PUT /v1/me/profile`, `GET/PATCH /v1/me/facts`, `GET/POST /v1/me/consents`, settings/memory/export/delete | เก็บ facts เมื่อ core consent ปัจจุบัน การถอน gov ยกเลิกสิทธิ์ใช้ facts ที่เชื่อม |
| Demo persona | `GET/POST /v1/demo/personas/{id}`, gov-link และ callback | GET preview ไม่แก้ profile, POST เปลี่ยน persona บน device ที่ระบุ |
| Benefits | `GET /v1/money`, `POST /v1/money/preview`, `GET/PATCH /v1/money/{id}` | preview ไม่บันทึก, route มีเหตุผล เอกสาร ที่มาและช่องทาง |
| Catalogue | `GET /v1/opportunities`, `GET /v1/opportunities/{id}` | query `area=bangkok`, `districtCode` หรือ `district`, หมวด, คำค้น, `dataMode`, `limit`, `cursor`, `includeDistrictPins` ข้อมูลบางรายการต้องอนุมานเขตจากชื่อ |
| Assistant | `POST /v1/ai/conversations`, messages, actions, rankings, explanations | guided, tool-backed, guarded และ fallback เป็นคนละสถานะ ดูตัวอย่าง [API](api-examples.json) |
| Plans | `GET /v1/plans/{options,ideas,goal}`, `GET/POST /v1/tasks`, task detail/events/delete | แผนเดียวต่อรายการที่บันทึกซ้ำ รักษา district เดิมเมื่อบันทึกซ้ำจากเขตอื่น |
| Public source pages | `/docs/`, Bangkok Info, application demo, กรุงเทพฯ และ senior reports | ใช้ไฟล์ static ตาม path ที่ backend เสิร์ฟ Info สร้าง origin จาก Host ที่เรียกจริง |

เมื่อ timeout หรือ 5xx ให้คืนข้อความไทยที่บอกทางลองใหม่ เมื่อผลว่างให้เสนอการปรับตัวกรองและยังแสดงเหตุผล สำหรับ 404/410 ของประกาศที่บันทึกแล้ว ให้คง task และ progress พร้อมแสดงสถานะรายการ ถ้า tiles ใช้ไม่ได้ให้ใช้รายการ ถ้าแหล่งจำลอง refresh ไม่สำเร็จ ให้ใช้ cache ในช่วงที่ยัง valid เท่านั้น หลังหมดอายุต้องขึ้น stale และถามข้อมูลที่ขาด

## วิธีตรวจความเทียบเท่า

1. ใช้ checkout อ้างอิงและเครื่องมือรุ่นเดียวกัน รัน contract/guard/manual, `flutter test` และ `flutter analyze` ตาม [คู่มือวันงาน](event-runbook.md)
2. รัน [กรณีทดสอบ](qa-scenarios.json) บน baseline และเวอร์ชันที่สร้างใหม่ ใช้ device ใหม่หรือแยก state ระหว่างการทดสอบ เทียบ status, provenance, ผลตอบสนอง, ข้อมูลหลัง restart, และ API schema
3. เก็บภาพ Android ที่ความละเอียด text scale locale และ font เดียวกันสำหรับ splash, onboarding, catalogue list/map, detail, chat, plans, contact, profile และบัญชี เทียบสถานะปกติ, empty, loading และ error กับ baseline. HTML mockup ใช้เทียบเจตนาด้าน UI. [ภาพอ้างอิงโปรไฟล์ แผน และบัญชีจาก commit ฐาน](https://github.com/otonzgd2/Money-Anywhere/tree/8efb63bb57e88fcb8cfd489d155ffe9cba025401/docs/handoff/thang-rot-assets)
4. ทดสอบเปิดลิงก์ผ่าน Android, TalkBack, จอแคบและตัวอักษรใหญ่ ประเมินบน APK จริงเมื่อครบทุกข้อ
5. สำหรับ live AI ทดสอบสองอินพุตและหนึ่ง follow-up จาก Provider จริง ต้องได้ `aiStatus: ok`, tool call ที่ตรงเจตนา และผลอ้างอิงกับข้อมูลที่ tool ส่งให้ ความต่างของข้อความจากการสุ่มยอมรับได้

ช่องว่างที่ต้องบันทึกไว้ในผลเทียบ ได้แก่ `mock:bangkok` คาดว่ามี working SQLite ใน path ที่ fresh checkout ไม่มี และแชต “ใกล้บ้าน” อาจออกนอกเขตเพราะ search tool รุ่นอ้างอิงไม่รับ district filter คำตอบ fallback ยังมีรายการ mock ที่ไม่ขึ้นป้ายรายแถว ผลทดลองโมเดลจริงในเคสไม่มีงานมีข้อความสัญญาจะแจ้งเตือนโดยไม่มี action ให้เพิ่ม assertion ว่าข้อความอ้างการดำเนินการได้เฉพาะเมื่อมีผล service รองรับ ส่วน `tools/gov-data-demo.js` เริ่มข้ามคำถามจากหน้าเลือกเจตนาเลยและส่ง quick reply แบบไม่ผูก step ID ใช้การเดิน flow ที่เลือกเจตนาก่อนเป็นหลักฐาน
