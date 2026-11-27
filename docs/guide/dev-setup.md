# Dev setup: ทุกคนในทีมใช้เวอร์ชันเดียวกัน

บันทึกจากเครื่องที่ใช้ทำ Demo จริง (26 พ.ย. 2569) ตรวจเครื่องตัวเองเทียบกับตารางนี้ด้วย:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-dev-env.ps1
```

## 1. เวอร์ชันของแอปและ API ตอนนี้

| ส่วน | เวอร์ชัน | ดูที่ |
|---|---|---|
| แอป Android (Flutter) | `1.0.0+1` (versionName 1.0.0, versionCode 1) | `app/pubspec.yaml` → `version` |
| Package id | `com.moneyanywhere.money_anywhere` | `app/android/app/build.gradle.kts` |
| API / demo server | `0.10.0` | `contracts/package.json`, `contracts/openapi.yaml` `info.version`, `GET /v1/health` |
| ประวัติการเปลี่ยน API | | `contracts/CHANGELOG.md` |
| นโยบายผู้ช่วย AI | `2026-11-26.2` | `contracts/fixtures/assistant-policy.json` → `version` |

เปลี่ยน API: ขึ้นเลข `package.json` และ `openapi.yaml` พร้อมกัน แล้วเขียน `CHANGELOG.md` (กฎใน `.kiro/steering/contracts-api.md`)
ส่ง APK ให้คนอื่น: ขึ้น `version` ใน `app/pubspec.yaml` (เช่น `1.0.1+2`) ก่อน build

## 2. เครื่องมือที่ต้องลง (Windows)

| เครื่องมือ | เวอร์ชันที่ใช้ | ลงที่ / หมายเหตุ |
|---|---|---|
| Flutter | **3.50.1** channel stable (framework `ae9b586f34`, 2026-11-18) | `C:\src\flutter` ใส่ `C:\src\flutter\bin` ใน PATH ห้ามใช้ channel อื่น ถ้าเวอร์ชันไม่ตรง: `git -C C:\src\flutter checkout 3.50.1` |
| Dart | **3.14.0** (มากับ Flutter) | ไม่ต้องลงแยก |
| DevTools | 2.61.0 (มากับ Flutter) | |
| JDK | **OpenJDK 25.0.4** (JBR ที่มากับ Android Studio) | `JAVA_HOME=C:\Program Files\Android\Android Studio\jbr` โปรเจกต์ compile เป็น Java 17 (`JavaVersion.VERSION_17`, `JVM_17`) |
| Android SDK | | `ANDROID_HOME=D:\Android\Sdk` (ไว้ D เพราะ C เหลือน้อย) |
| ├ platform-tools (adb) | **1.0.41** (37.0.3) | ใส่ `D:\Android\Sdk\platform-tools` ใน PATH |
| ├ platforms | **android-36** (+ android-35 ที่ Gradle ลงเอง) | |
| ├ build-tools | **36.0.0** | |
| ├ NDK | **28.2.13676358** (r28c) | Gradle ลงเองตอน build ครั้งแรก |
| ├ CMake | **3.22.1** | Gradle ลงเอง |
| └ cmdline-tools | latest | ใช้ `sdkmanager` ยอมรับ license: `sdkmanager --licenses` |
| Gradle | **9.5.0** (wrapper) | `app/android/gradle/wrapper/gradle-wrapper.properties` cache ที่ `GRADLE_USER_HOME=D:\gradle-home` |
| Android Gradle Plugin | **9.3.1** | `app/android/settings.gradle.kts` |
| Kotlin (Android) | **2.4.20** | `app/android/settings.gradle.kts` |
| pub cache | | `PUB_CACHE=D:\pub-cache` |
| Node.js | **v24.22.1** | demo server ใช้ `--env-file-if-exists` (ต้อง Node 22 ขึ้นไป) |
| npm | **11.19.1** | ใน PowerShell ใช้ `npm.cmd` ไม่ใช่ `npm` |
| Git | ตัวไหนก็ได้ | |
| Visual Studio | ไม่ต้องใช้ | ใช้เฉพาะถ้าจะ build เป็นโปรแกรม Windows (ต้องมี workload "Desktop development with C++") ตอนนี้ไม่ได้ใช้ |
| Android Studio | ไม่บังคับ | ใช้แค่ JBR (JDK) ที่มากับมัน ไม่ต้องเปิด IDE |

ตัวแปรระบบที่ตั้งไว้ (System > Environment Variables > User):

```
ANDROID_HOME=D:\Android\Sdk
JAVA_HOME=C:\Program Files\Android\Android Studio\jbr
GRADLE_USER_HOME=D:\gradle-home
PUB_CACHE=D:\pub-cache
PATH += C:\src\flutter\bin;D:\Android\Sdk\platform-tools
```

เครื่องที่ path ต่างจากนี้: ตั้งตัวแปรเดียวกันตามเครื่องตัวเอง และ `FLUTTER_BIN` (path เต็มของ `flutter.bat`) สคริปต์ใน `tools/` อ่านค่าจากตัวแปรเหล่านี้ก่อน

## 3. Package ของแอป (ล็อกไว้แล้ว)

`app/pubspec.lock` อยู่ใน git: `flutter pub get` จะได้เวอร์ชันเดียวกันทุกเครื่อง ห้ามรัน `flutter pub upgrade` โดยไม่ตกลงกันก่อน

| Package | ระบุใน pubspec | ใช้ทำอะไร |
|---|---|---|
| `material_ui` | ^1.1.0 | widget (template ของ Flutter 3.50) |
| `url_launcher` | ^6.3.1 | เปิดลิงก์หน่วยงาน/ประกาศงาน |
| `flutter_map` | ^8.2.1 (ล็อก 8.3.2) | แผนที่ OpenStreetMap ไม่ต้องใช้ key |
| `latlong2` | ^0.9.1 (ล็อก 0.9.1) | พิกัดบนแผนที่ |
| `flutter_lints` (dev) | ^6.0.0 | `flutter analyze` |

Server (`contracts/`) ไม่มี dependency ตอนรัน มีแค่ devDependencies สำหรับเทสต์: `@apidevtools/swagger-parser` ^10.1.0, `ajv` ^8.17.1, `ajv-formats` ^3.0.1, `js-yaml` ^4.1.0 (`npm.cmd ci` ใน `contracts/`)

## 4. AI และไฟล์ `.env`

```powershell
copy .env.example .env      # แล้วใส่ AI_API_KEY (ขอจาก Owner ห้าม commit)
```

| ตัวแปร | ค่าที่ใช้ |
|---|---|
| `AI_BASE_URL` | `https://generativelanguage.googleapis.com/v1beta/openai` (Gemini แบบ OpenAI-compatible) |
| `AI_MODEL` | `gemini-3.5-flash-lite` (ตอบ 1–3 วิ; `gemini-flash-latest` ตอบ 503 และช้า, `gemini-2.5-*` ได้ 404 กับ key ใหม่) |
| `LIVE=1` | ดึงประกาศงานจริงจาก Agoda (Greenhouse) |
| `APP_MODE=user` | แสดงสถานะการเชื่อมระบบจริงของ ThaID และทางรัฐในแท็บ ฉัน ค่าเริ่มต้นคือ `demo` |
| `GOV_CONNECTED=1` | เปิดปุ่มเชื่อม ThaID ด้วยข้อมูลจำลองในโหมด `demo` |
| `MOCK_CATALOGUE=1` | เปิดข้อมูลจำลองชุดใหญ่ 77 รายการ |

ไม่มี key ก็รันได้: server ใช้กฎแทน AI (`aiStatus: fallback_rules`)

โหมด `user` ปิดการเชื่อม ThaID จำลองและโปรไฟล์ตัวอย่าง แม้จะตั้ง `GOV_CONNECTED=1` หรือ `DEMO_MODE=1` ถ้ากำหนด `DATA_FILE` เอง ให้ใช้ไฟล์ใหม่สำหรับโหมด `user` แยกจากข้อมูล Demo หากไม่ได้กำหนดตัวแปรนี้ เซิร์ฟเวอร์ใช้ `contracts/.data/user/state.json` โดยอัตโนมัติ

การเชื่อมระบบจริงของ ThaID ต้องได้รับอนุมัติและคู่มือสำหรับผู้ให้บริการจากกรมการปกครอง ส่วนทางรัฐต้องมีสิทธิ์และข้อกำหนด API สำหรับข้อมูลที่ตกลงกับ สพร. หรือหน่วยงานเจ้าของบริการ

## 5. มือถือที่ใช้ทดสอบ

| | |
|---|---|
| รุ่น | Samsung **SM-S948B**, One UI 9 |
| Android | **17** (API **37**) |
| minSdk / targetSdk ของแอป | ตามค่าเริ่มต้นของ Flutter 3.50.1 (`flutter.minSdkVersion`, `flutter.targetSdkVersion`) |

เปิดใช้งาน (เมนูไทย): ตั้งค่า > ข้อมูลโทรศัพท์ > ข้อมูลซอฟต์แวร์ > แตะ "หมายเลขรุ่น" 7 ครั้ง > ตัวเลือกสำหรับนักพัฒนา > เปิด "การแก้ไขจุดบกพร่อง USB"

ปัญหาที่เจอจริง:
- **ต้องปิด "ตัวบล็อกอัตโนมัติ (Auto Blocker)"** (ตั้งค่า > ความปลอดภัยและความเป็นส่วนตัว > ตัวบล็อกอัตโนมัติ) ไม่งั้นต่อ USB / ติดตั้งแอปไม่ได้ / แอปต่อ server ไม่ได้
- เสียบสายแล้วกด "อนุญาต" บนจอมือถือ ทุกครั้งที่เสียบใหม่ต้อง `adb reverse tcp:8080 tcp:8080`
- ติดตั้งต้องใส่ `--user 0` (Samsung Secure Folder เป็น user แยก)
- ระหว่างติดตั้งให้ปลดล็อกจอไว้ บางครั้งมีหน้าต่างถามบนมือถือ

ใช้ Wi-Fi แทนสาย: ในแอป ฉัน > ที่อยู่ server ใส่ `http://<IP ของคอม>:8080` (คอมกับมือถือ Wi-Fi เดียวกัน, อนุญาต node ใน Windows Firewall)

## 6. คำสั่งที่ใช้ทุกวัน

| ทำอะไร | คำสั่ง (จาก root ของ repo) |
|---|---|
| ตรวจเครื่อง | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-dev-env.ps1` |
| เปิด server อย่างเดียว | `cd contracts; npm.cmd run mock` |
| เทสต์ API + สร้างเอกสาร API | `cd contracts; npm.cmd run check` (ต้องผ่านทุกข้อ ตอนนี้ 139/139) |
| เทสต์ mock HTML | `cd contracts; $env:JSDOM_PATH="$env:TEMP\jsd"; node ..\docs\mockups\smoke-test.js` |
| เทสต์แอป | `cd app; flutter analyze; flutter test` (ตอนนี้ 14/14) |
| มือถือต่อ server ไม่ได้ (ถูกบล็อก / ถอดสาย) ไม่ต้อง build ใหม่ | ปิดตัวบล็อกอัตโนมัติ เสียบสาย แล้ว `powershell -NoProfile -ExecutionPolicy Bypass -File tools\reconnect.ps1` (เปิด server ถ้าดับ, `adb reverse`, เปิดแอปใหม่) |
| build + รีสตาร์ต server + ติดตั้งลงมือถือ | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-and-install.ps1` แล้วดู `contracts\.data\build-app.log` |
| ทดสอบ flow ทั้งหมดบนคอม (ไม่ต้องใช้มือถือ) | server เปิดอยู่ แล้ว `node tools\e2e-flows.js` ดูผลที่ `contracts\.data\e2e-out.txt` (ตอนนี้ 28/28) |

build ครั้งแรกบนเครื่องใหม่ใช้ ~4 นาที (โหลด Gradle + NDK) ครั้งต่อไป 15–60 วินาที
ถ้า `flutter` ค้าง: มี `flutter test` ตัวเก่าค้างถือ lock อยู่ ปิด process `dart.exe` / `flutter_tester.exe` ใน Task Manager แล้วรันใหม่

## 7. ไฟล์ที่ไม่อยู่ใน git (แต่ละเครื่องมีของตัวเอง)

| ไฟล์ | ทำไม |
|---|---|
| `.env` | มี API key |
| `contracts/.data/` | log, ข้อมูลผู้ใช้ทดสอบ, ไฟล์ชั่วคราว |
| `app/build/`, `app/.dart_tool/` | ผล build |
| `app/android/local.properties` | path ของ Flutter และ SDK บนเครื่องนั้น (Flutter สร้างให้เอง) |

เอกสารที่เกี่ยวข้อง: `docs/guide/rebuild-playbook.md` (สร้างแอปใหม่วัน Demo), `docs/guide/run-demo-server.md`, `docs/design/ui-states.md`
