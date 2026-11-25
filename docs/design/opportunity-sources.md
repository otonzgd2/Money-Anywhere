# Opportunity Sources: ฟิลด์กลางและการเชื่อมแหล่งข้อมูล (ร่างเพื่อ R&D)

สถานะ: ข้อเสนอ ยังไม่ผ่าน AI-DLC design และยังไม่ได้ Owner อนุมัติ
ใช้กับ: Money Map และหน้าผลลัพธ์ (`docs/mockups/index.html`)

## หลักการ
1. ทุกแหล่ง (API, open data, ไฟล์คัดมือ, mock) แปลงเป็น **ฟิลด์กลางชุดเดียว** ผ่าน adapter ของแต่ละเจ้า หน้าจอแสดงจากฟิลด์กลางเท่านั้น เพิ่มเจ้าใหม่ = เขียน adapter ใหม่ ไม่ต้องแก้หน้าจอ
2. แสดงเฉพาะฟิลด์ที่ทุกเจ้ามี หรือมีค่า fallback ที่ซื่อตรง (`ไม่ระบุ`) ห้ามเดาค่าแทน
3. ทุกรายการต้องมี `source_url` เพื่อกดไปดูที่ต้นทาง
4. ปักหมุดเฉพาะรายการที่ `location_precision = exact` ส่วนระดับเมืองหรือไม่มีที่ตั้งแสดงในรายการ ตามกฎ handoff ที่ห้ามปักหมุดกลางเมือง
5. ดึงสดเมื่อเปิดหน้าหรือกดรีเฟรช เก็บ cache ไว้ใช้ตอนออฟไลน์ และแสดงเวลาที่ดึงล่าสุดเสมอ

## ฟิลด์กลาง

| ฟิลด์ | บังคับ | ความหมาย |
|---|---|---|
| `id` | ใช่ | `<provider>_<provider_item_id>` |
| `provider` | ใช่ | greenhouse, lever, bma_open, osm, curated, mock |
| `data_status` | ใช่ | live, curated, open_data, mock, blocked |
| `title` | ใช่ | ชื่อโอกาส |
| `organization` | ไม่ | ผู้ประกาศ/หน่วยงาน |
| `category` | ใช่ | หนึ่งใน 10 หมวดของ requirements |
| `map_group` | ใช่ | job, skill, sell, money (4 กลุ่มบนแผนที่) |
| `location_text` | ไม่ | ที่ตั้งตามต้นทางแบบข้อความ |
| `lat`, `lng` | ไม่ | มีเฉพาะเมื่อรู้พิกัดจริง |
| `location_precision` | ใช่ | exact, city, none |
| `pay_min`, `pay_max`, `pay_unit` | ไม่ | ตามที่ต้นทางระบุเท่านั้น |
| `pay_basis` | ใช่ | official, listing, none (ห้าม AI เติม) |
| `posted_at`, `updated_at`, `expires_at` | ไม่ | ตามต้นทาง |
| `fetched_at` | ใช่ | เวลาที่แอปดึงข้อมูล |
| `source_url` | ใช่ | ลิงก์ไปดูต้นทาง |
| `attribution` | ใช่ | ข้อความที่มา/สัญญาอนุญาตที่ต้องแสดง |

## การแมปของแต่ละเจ้า

| เจ้า | สถานะหลักฐาน | title | organization | location | pay | วันที่ | source_url |
|---|---|---|---|---|---|---|---|
| Greenhouse Job Board API | เรียกจริงแล้ว ตอบ JSON (Agoda 335 ตำแหน่ง) ไม่ต้องใช้ key | `title` | `company_name` | `location.name` ข้อความ เช่น "Bangkok" → precision city | ไม่มีในข้อมูลที่เห็น → none | `updated_at`, `first_published`, `application_deadline` | `absolute_url` |
| Lever Postings API | เรียกจริงแล้ว ตอบ JSON (Coda) | `text` (ตามเอกสาร ยังไม่ได้ดูในผลจริง) | ชื่อบริษัทที่ใช้เรียก API | `categories.location` ข้อความ → precision city | ไม่ได้ตรวจ | `createdAt` | `hostedUrl` (ตามเอกสาร ยังไม่ได้ดูในผลจริง) |
| data.go.th โรงเรียนฝึกอาชีพ กทม. | หน้าชุดข้อมูลมีไฟล์ JSON/KML/GML ยังไม่ได้เปิดเนื้อหา | ชื่อโรงเรียน (คาดว่า) | กรุงเทพมหานคร | พิกัดจาก KML (คาดว่า) → exact ถ้ายืนยัน | none (ฝึกฟรี ไม่ใช่เงินสด) | ข้อมูลปี 2564 | หน้าชุดข้อมูล |
| OpenStreetMap / Overpass | ยังไม่ยืนยัน (ตอบ 502 หนึ่งครั้ง) | `tags.name` | - | `lat`, `lon` → exact | none | - | ลิงก์ osm.org ของจุดนั้น |
| Curated (ทีมคัดเอง) | ยังไม่มีข้อมูล | ทีมกรอก | ทีมกรอก | ทีมกรอกพิกัดจากที่อยู่จริง | ตามประกาศเท่านั้น | วันที่ตรวจ | URL ประกาศจริง |
| Daywork, Fastwork, JobThai, JOBBKK | มีประกาศสาธารณะ ไม่มี API ที่อนุญาต | - | - | - | - | - | ใส่เป็นลิงก์ใน Curated ได้ ห้าม scrape |
| Jobsdb, GDX/กรมการจัดหางาน | ต้องขออนุญาต | - | - | - | - | - | blocked |

## ข้อจำกัดที่ต้องรู้
- Greenhouse และ Lever ให้แค่ข้อความที่ตั้งระดับเมือง จึงขึ้นได้แค่ในรายการ ถ้าจะปักหมุดต้องมีที่อยู่สำนักงานจริงจากแหล่งที่ยืนยันได้ แล้วตั้ง precision เป็น exact เอง
- งานจาก Greenhouse และ Lever เป็นงานบริษัท/งานเทคส่วนใหญ่ ไม่ตรงกลุ่มผู้มีรายได้น้อยหรือผู้สูงอายุ งานรายวันที่ตรงกลุ่มยังต้องมาจาก Curated
- ข้อมูลงานของ Agoda มีค่า location กำกวม เช่น "Bangkok, Malaysia" adapter ต้องกรองทิ้ง
- ใน mock HTML การดึงสดอาจล้มเพราะเบราว์เซอร์บล็อก CORS แอป Flutter เรียก HTTP ตรงจึงไม่ติดปัญหานี้

## งานถัดไป
1. เปิดไฟล์ JSON/KML ของโรงเรียนฝึกอาชีพ ตรวจจำนวนรายการและพิกัด
2. ลอง Overpass ซ้ำ และกำหนด query ร้านรับซื้อของเก่า/มือสองในกรุงเทพฯ
3. หา board ของ Greenhouse/Lever ที่มีงานในกรุงเทพฯ เพิ่ม
4. เริ่มไฟล์ Curated ด้วยฟิลด์กลางชุดนี้
