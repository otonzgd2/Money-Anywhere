# ตั้งค่า Apify และทดสอบนำเข้างานลง SQLite

ใช้คู่มือนี้เมื่อรับช่วงการนำเข้างานของ Money Anywhere จาก Apify เริ่มจาก JobThai และ JobBKK ทีละแหล่ง ทดสอบด้วยมือหนึ่งรอบ และตรวจจำนวนที่เพิ่มใน SQLite ที่แอปใช้ ให้ปิดการตั้งเวลาใน Apify และใช้ `JOB_AUTO_SYNC=0` ตลอดการทดสอบ

## เริ่มจาก Task ที่มีอยู่

| แหล่งและรหัสใน Backend | Task ใน Apify | ค่าที่บันทึกไว้ |
| --- | --- | --- |
| JobThai (`jobthai`) | [`3c5FDIctB8GZeXGnE`](https://console.apify.com/actors/tasks/3c5FDIctB8GZeXGnE/input) | Actor `listingworks/jobthai-scraper` สูงสุด 5 รายการ ปิดการดึงหน้ารายละเอียดเพิ่มเติม |
| JobBKK (`jobbkk`) | [`awTQiJe0BCYRGZGrK`](https://console.apify.com/actors/tasks/awTQiJe0BCYRGZGrK/input) | Actor `mai_amm/jobbkk-scraper` สูงสุด 5 รายการ เปิดคำขอพร้อมกันได้ครั้งละ 1 หน้า |

ก่อนส่งต่อ ทั้งสอง Task มี 0 runs ฐาน `docs/entities/database-script/catalogue.db` มี 146 แถว และมี 0 แถวจากแต่ละแหล่ง ตรวจใหม่ก่อนเริ่มเสมอ Fastwork รอ Actor ที่รองรับ [Jobboard ฝั่งผู้จ้าง](https://jobboard.fastwork.co/) และสิทธิ์จากต้นทาง ส่วน [Actor ที่พบใน Store](https://apify.com/mai_amm/fastwork-thailand-scraper) ใช้กับรายการบริการฟรีแลนซ์ ข้าม JSearch ตามขอบเขตงาน

หากต้องสร้าง Task ใหม่หลังได้รับสิทธิ์ ให้เปิด Actor ที่ตรงกับแหล่ง แล้วเลือก **Save as a new task → Continue** เปิดหน้า Task และบันทึก Input ด้วย **Save** ตรวจจำนวนสูงสุด ขอบเขต URL และการเข้าถึงตามที่ต้นทางอนุญาต เก็บ Task ID จาก URL หลัง `/actors/tasks/` และตรวจแท็บ **Runs** [คู่มือ Actor Tasks](https://docs.apify.com/actors/running/tasks)

## ขอสิทธิ์และตั้ง Token

1. ขอฟีด API, JSON หรือ CSV จากเจ้าของแหล่ง หากจะใช้ Apify ให้ขอคำยืนยันสำหรับวิธีเก็บข้อมูลผ่าน Apify โดยตรง ระบุว่าจะทดสอบสูงสุด 5 ประกาศต่อแหล่ง เก็บฟิลด์ใด แสดงฟิลด์ใดในแอป และลิงก์กลับอย่างไร ขอเงื่อนไขเครดิต อายุข้อมูล การใช้เชิงพาณิชย์ และรอบดึงที่ยอมรับด้วย [นโยบายแหล่งข้อมูล](job-source-policy.md)
2. ติดต่อ JobThai ที่ `sale@jobthai.com` และ JobBKK ที่ `sales@jobbkk.com` เมื่อได้รับคำตอบ ให้เจ้าของโครงการยืนยันขอบเขตและบันทึกเอกสารอ้างอิง เกณฑ์เดียวกันใช้กับฟีดที่ต้นทางส่งให้โดยตรง [ช่องทาง JobThai](https://www.jobthai.com/jobthai-app-static-page-assets/file/rate-card-en-11-11-68.pdf) · [ช่องทาง JobBKK](https://www.jobbkk.com/jobs/lists/84/contact_us.asp)
3. หากใช้ Apify ให้เจ้าของบัญชีเปิด **Settings → API & Integrations → Personal API tokens → Create a new token** ให้สิทธิ์อ่านผลจาก Task และ Dataset ที่ใช้เท่าที่จำเป็น รัน Task จาก Console ด้วยมือได้โดยใช้บัญชีที่เข้าสู่ระบบ [หน้าตั้งค่า Apify](https://console.apify.com/settings/integrations) · [คู่มือ Token](https://docs.apify.com/integrations/api)
4. ให้เจ้าของเครื่องตั้ง `APIFY_JOB_FEEDS_TOKEN` ใน environment ของ Backend ถ้าใช้ `npm.cmd --prefix .\contracts run mock` ให้เพิ่มบรรทัด `APIFY_JOB_FEEDS_TOKEN=<ค่า Token>` ด้วยตนเองในไฟล์ `.env` ที่ราก repo ซึ่ง Git ignore ไว้ AI ใช้ชื่อตัวแปรได้และให้เก็บค่าไว้ในเครื่อง งดเปิดไฟล์ `.env` เพื่ออ่านค่า งดใส่ค่าในแชต URL ตัวอย่าง หรือ Git ส่งค่าให้ Apify ผ่าน `Authorization: Bearer` เท่านั้น

หากยังขาดสิทธิ์ ให้หยุดที่แหล่งนั้นก่อนกด **Start** หากขาด Token ให้เจ้าของเครื่องตั้งค่าตามข้อ 4 ก่อนเรียก Dataset API การเข้าสู่ระบบ Apify ช่วยเปิดหน้า Task ได้ สิทธิ์ใช้ประกาศต้องได้รับจากต้นทาง

## ขอรายละเอียดค่าบริการจาก JobThai และ JobBKK

เพิ่มย่อหน้าต่อไปนี้ก่อนคำขอบคุณในอีเมลถึงทั้งสองแหล่ง ค่าบริการ API หรือฟีดจากเจ้าของประกาศให้ยึดตามคำตอบหรือใบเสนอราคาของแต่ละแหล่ง

> สำหรับการทดสอบด้วยมือหนึ่งรอบ จำนวนไม่เกิน 5 ประกาศ รบกวนแจ้งว่าสามารถทดลองได้โดยไม่มีค่าใช้จ่ายหรือไม่ครับ หากมีค่าใช้จ่าย ขอทราบค่าทดลองและค่าเปิดสิทธิ์เข้าถึงข้อมูล หากมี API หรือฟีดสำหรับใช้งานต่อหลังจบทดสอบ รบกวนแนบอัตราค่าบริการ โควตา ค่าใช้เกินโควตา และระบุว่าราคารวม VAT แล้วหรือยังครับ

## ประมาณค่า Apify สำหรับรอบทดสอบ

อัตราที่ตรวจเมื่อ 27 พฤศจิกายน 2569 คำนวณจาก Task ที่บันทึกไว้ ทดสอบด้วยมือแหล่งละหนึ่งรอบและได้ครบ 5 รายการ ตัวเลขเป็น USD และรวมค่าเริ่มรันตาม RAM ที่ตั้งไว้

| Task | ค่าต่อผลลัพธ์ | ค่าเริ่มรัน | ประมาณการรวมต่อ Task |
| --- | ---: | ---: | ---: |
| [JobThai](https://api.apify.com/v2/acts/8HqaH268SE2eHToV4) | 0.001 | 0.00020 ที่ RAM 4 GB | 0.00520 |
| [JobBKK](https://api.apify.com/v2/acts/8qmxdmawkzznbjJ1l) | 0.01 | 0.00005 ที่ RAM 1 GB | 0.05005 |
| **รวมสอง Task** | | | **0.05525** |

ก่อนเริ่มรอบทดสอบ ให้ตรวจ **Pricing** ของ Actor และ **Maximum cost per run** ใน Task ค่าอ่าน Dataset หลังรันคิดตามการใช้งานของ Apify และอยู่นอกประมาณการนี้ [วิธีคิดค่าบริการ Apify](https://docs.apify.com/actors/store#pricing-models)

## ทดสอบนำเข้าด้วยมือหนึ่งรอบ

1. ตรวจว่า checkout มี `contracts/adapters/job-file-feed.js` และ `contracts/adapters/job-sync.js` และว่า Backend รองรับ `JOB_DB_FILE` กับ `JOB_FEEDS_FILE` หากขาดไฟล์ ให้เปิด checkout ที่มีตัวนำเข้า งานส่งต่อนี้บันทึกวิธีใช้และอ้างอิงโค้ดตัวนำเข้าที่อยู่ในเครื่องตอนตรวจ
2. ยืนยันพาธ `JOB_DB_FILE` ของ Backend ที่แอปใช้ แล้วรันคำสั่งนับท้ายคู่มือเพื่อบันทึกจำนวนก่อนเริ่ม เมื่อได้รับสิทธิ์แล้วจึงลงทะเบียนแหล่งใน `job_source` ด้วย `provider` ที่ตรงกับตาราง ตั้ง `direction='pull'` และ `data_status='live'` บันทึก `terms_url`, `attribution`, `checked_by`, `checked_on` และผลสิทธิ์เชิงพาณิชย์ตามหลักฐาน ตั้ง `approved=1`, `can_store=1` และ `can_redisplay=1` เฉพาะแหล่งที่ผ่านการยืนยัน [สเปค job_source](../entities/database-spec/job_source.md)
3. เปิด Task ที่ได้รับอนุญาตใน Apify ตรวจค่ารันและค่าใช้จ่าย แล้วกด **Start** หนึ่งครั้ง รอ `SUCCEEDED` และจด Run ID, Dataset ID และจำนวนที่ Apify คืน ใช้ Dataset ของรอบนั้นเพื่อให้ผลตรวจย้อนกลับไปยังรอบเดียวกันได้ อ่านผ่าน `GET https://api.apify.com/v2/datasets/<dataset-id>/items?format=json&limit=5` หรือใช้ฟีดที่เจ้าของแหล่งส่งให้ตามเงื่อนไขที่อนุมัติ หากรอบล้มเหลวหรือผลว่าง ให้รายงานผลตามจริงและหยุดแหล่งนั้น [Apify Dataset API](https://docs.apify.com/api/v2/dataset-items-get)
4. ตรวจผลจริงแล้วแปลงเฉพาะฟิลด์ที่ได้รับอนุญาตเป็น `OpportunityInput` เก็บ `externalId` ที่คงเดิมจากรหัสต้นทางหรือ URL ประกาศแบบถาวร ใช้ `title`, `sourceUrl`, `mapGroup: "job"` และรหัส `category` จากหมวดงานใน `contracts/fixtures/reference.json` เพิ่ม `organization`, พื้นที่ และวันจากข้อมูลจริงเมื่อมี ใช้ `money: { "basis": "none" }` เมื่อไม่มีค่าจ้างที่อ้างได้ ตรวจรหัสซ้ำและตัดข้อมูลติดต่อส่วนบุคคลออกก่อนบันทึกไฟล์ [สัญญาข้อมูล OpportunityInput](../../contracts/openapi.yaml)
5. หาก Dataset ดิบใช้ชื่อฟิลด์ต่างจากสัญญา ให้เขียนอาร์เรย์ที่แปลงแล้วเป็น JSON UTF-8 แยกแหล่งในโฟลเดอร์ชั่วคราว สร้าง `feeds.json` ในโฟลเดอร์เดียวกันโดยใส่เฉพาะแหล่งที่ได้รับอนุญาตและมีไฟล์พร้อม ตัวอย่างฟีดไฟล์สำหรับ JobThai ใช้คีย์ดังนี้ เปลี่ยน `provider` และชื่อไฟล์สำหรับ JobBKK

   ```json
   [
     {
       "provider": "jobthai",
       "format": "json",
       "file": "./jobthai.opportunities.json",
       "enabled": true
     }
   ]
   ```

6. หากฟีดออนไลน์อยู่ในรูป `OpportunityInput` แล้ว ให้ใช้การตั้งค่าออนไลน์แทนไฟล์ ตัด `file` ออก ตั้ง `job_source.fetch_url` เป็น HTTPS ของฟีด และใช้ `"auth": { "type": "bearer", "env": "APIFY_JOB_FEEDS_TOKEN" }` สำหรับ Apify ถ้าใช้ผลล่าสุดของ Task ให้ตรวจว่าเป็น Run ID เดียวกับรอบทดสอบ URL ใช้รูปแบบ `https://api.apify.com/v2/actor-tasks/<task-id>/runs/last/dataset/items?status=SUCCEEDED&format=json` [Apify Task Dataset API](https://docs.apify.com/api/v2/actor-task-runs-last-dataset-items-get)
7. เปิด Backend ด้วย `JOB_DB_FILE` ที่ตรวจแล้วและ `JOB_FEEDS_FILE` ที่เตรียมไว้ กำหนด `JOB_AUTO_SYNC=0` และ `LIVE=0` ใช้พอร์ตที่ว่างหากเปิด Backend ทดสอบแยก เครื่องนี้ใช้คำสั่งต่อไปนี้จากราก repo โดยแทนพาธและพอร์ตตามเครื่อง ตรวจว่าพาธฐานตรงกับฐานของแอปก่อนรัน [ขั้นตอนเปิด Backend](job-ingest-procedure.md)

   ```powershell
   $env:JOB_DB_FILE = (Resolve-Path 'docs/entities/database-script/catalogue.db').Path
   $env:JOB_FEEDS_FILE = (Resolve-Path '<โฟลเดอร์ชั่วคราว>/feeds.json').Path
   $env:JOB_AUTO_SYNC = '0'
   $env:LIVE = '0'
   $env:JOBICY_SYNC = '0'
   $env:PORT = '8091'
   npm.cmd --prefix .\contracts run mock
   ```

8. ใช้ PowerShell อีกหน้าต่าง เรียก `POST /v1/sources/jobthai/refresh` และ `POST /v1/sources/jobbkk/refresh` ทีละแหล่งที่พร้อม ตัวอย่างใช้ `Invoke-WebRequest -UseBasicParsing -Method Post -Uri 'http://127.0.0.1:8091/v1/sources/jobthai/refresh'` ค่า `202` หมายถึง Backend รับคำสั่งแล้ว รอให้ `job_file_refresh_<provider>` ใน `GET /v1/health` แสดงผลรอบ และนับใน SQLite อีกครั้ง

## นับผลในฐานจริง

เปิด SQLite แบบอ่านอย่างเดียว รัน SQL ต่อไปนี้ก่อนและหลังทดสอบ คำสั่งแสดง 0 ได้แม้แหล่งนั้นยังไม่มีทะเบียน

```sql
WITH target(provider) AS (VALUES ('jobthai'), ('jobbkk'))
SELECT target.provider,
       COUNT(p.id) AS postings,
       s.state,
       s.last_run_id,
       s.last_fetched_at,
       s.last_run_stat
FROM target
LEFT JOIN job_source AS s ON s.provider = target.provider
LEFT JOIN job_posting AS p
       ON p.provider = target.provider AND p.map_group = 'job'
GROUP BY target.provider, s.state, s.last_run_id, s.last_fetched_at, s.last_run_stat
ORDER BY target.provider;
```

รายงานแยกแหล่งด้วย Run ID, จำนวนจาก Apify, จำนวนก่อนและหลัง และจำนวนเพิ่ม เปรียบเทียบผลต่างกับ `last_run_stat.new` ของรอบที่ตรวจ เปิดอ่านตัวอย่าง `source_url` และสถานะจาก `job_posting` เพื่อยืนยันว่ามีประกาศจริงครบตามที่รายงาน หากขาดเงื่อนไขก่อนรัน ให้ระบุว่า **ยังไม่ได้ทดสอบ** พร้อมระบุสิ่งที่ขาด การเปิดรอบทุก 5 นาทีเป็นงานถัดไปหลังเจ้าของโครงการตรวจผล
