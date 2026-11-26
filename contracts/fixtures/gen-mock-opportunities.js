// Generates fixtures/opportunities-mock.json: a broad DEMO / MOCK catalogue that stands in for the government and
// private APIs we cannot connect to for free yet. Deterministic (seeded) so tests and demos are repeatable.
// Run: node fixtures/gen-mock-opportunities.js
// Every item is labelled mock in the app. Wages are realistic Bangkok ranges (minimum wage ~400 THB/day, 2026),
// but they are NOT real listings. Replace a provider by connecting its real API (docs/plan/open-items.md M1, M11).
const fs = require('fs');
let seed = 20261126;
const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
const pick = a => a[Math.floor(rnd() * a.length)];

// Approximate district centres (Bangkok). Pins are jittered and labelled as sample addresses.
const districts = [
  ['ปทุมวัน', 13.7446, 100.5300], ['บางกะปิ', 13.7659, 100.6470], ['ลาดพร้าว', 13.8036, 100.6076], ['บางนา', 13.6681, 100.6347],
  ['จตุจักร', 13.8285, 100.5600], ['ดินแดง', 13.7700, 100.5530], ['ห้วยขวาง', 13.7760, 100.5790], ['คลองเตย', 13.7080, 100.5840],
  ['บางรัก', 13.7300, 100.5240], ['สาทร', 13.7080, 100.5260], ['ธนบุรี', 13.7240, 100.4860], ['บางแค', 13.6960, 100.4090],
  ['มีนบุรี', 13.8130, 100.7480], ['ลาดกระบัง', 13.7220, 100.7590], ['ดอนเมือง', 13.9130, 100.5890], ['บางเขน', 13.8730, 100.5960]
];

const providers = {
  mock_doe: { org: n => 'สถานประกอบการ ' + n + ' (จำลอง)', note: 'จำลองข้อมูลจากระบบประกาศงานภาครัฐ' },
  mock_jobboard: { org: n => 'บริษัท ' + n + ' จำกัด (จำลอง)', note: 'จำลองข้อมูลจากเว็บหางานเอกชน' },
  mock_gig: { org: () => 'แพลตฟอร์มงานรายครั้ง (จำลอง)', note: 'จำลองข้อมูลจากแพลตฟอร์มงานอิสระ' }
};
const names = ['สยามบริการ', 'รุ่งเรืองฟู้ด', 'ไทยโลจิสติกส์', 'บ้านสุขใจ', 'กรีนคลีน', 'เมืองทองค้าปลีก', 'ดีดีโฮม', 'สุขภาพดีเนิร์สซิ่ง', 'ช่างเก่ง', 'ซีวิวโฮเทล', 'ฟ้าใสการ์เมนต์', 'เพื่อนบ้านมาร์ท'];

// [title, category, unit, min, max, skills, conditions, providers, forOlder]
const jobs = [
  ['แม่บ้านทำความสะอาดสำนักงาน', 'job_full', 'บาท/เดือน', 12000, 13500, ['ทำความสะอาด'], ['จ.-ศ. 08:00-17:00', 'มีประกันสังคม'], ['mock_doe', 'mock_jobboard']],
  ['พนักงานล้างจานร้านอาหาร', 'job_part', 'บาท/วัน', 400, 450, ['ทำความสะอาด', 'ทำอาหาร'], ['กะเย็น 16:00-22:00', 'ไม่ต้องมีประสบการณ์'], ['mock_jobboard']],
  ['ผู้ช่วยกุ๊กร้านอาหาร', 'job_full', 'บาท/เดือน', 13000, 16000, ['ทำอาหาร'], ['มีที่พักให้บางสาขา'], ['mock_doe', 'mock_jobboard']],
  ['พนักงานขายหน้าร้าน (พาร์ตไทม์)', 'job_part', 'บาท/ชั่วโมง', 50, 65, ['ขายหน้าร้าน'], ['เลือกกะได้ 4-6 ชม./วัน'], ['mock_jobboard']],
  ['แคชเชียร์ซูเปอร์มาร์เก็ต', 'job_full', 'บาท/เดือน', 12500, 14000, ['ขายหน้าร้าน'], ['ทำงานเป็นกะ', 'มีประกันสังคม'], ['mock_doe']],
  ['พนักงานแพ็คสินค้าคลังออนไลน์', 'job_part', 'บาท/วัน', 400, 480, [], ['รับรายวัน จ่ายทุกสัปดาห์', 'ไม่ต้องมีประสบการณ์'], ['mock_doe', 'mock_jobboard']],
  ['ไรเดอร์ส่งอาหาร (รับงานผ่านแอป)', 'freelance', 'บาท/วัน ก่อนหักค่าน้ำมัน', 500, 900, ['ขับมอเตอร์ไซค์', 'ส่งของ/ส่งอาหาร'], ['ใช้รถของตัวเอง', 'รายได้ขึ้นกับจำนวนงาน'], ['mock_gig']],
  ['พนักงานขับรถส่งของ', 'job_full', 'บาท/เดือน', 15000, 18000, ['ขับรถยนต์'], ['ใบขับขี่ท.1 หรือส่วนบุคคล'], ['mock_doe', 'mock_jobboard']],
  ['รปภ. หมู่บ้านและคอนโด', 'job_full', 'บาท/เดือน', 11000, 13000, ['รปภ.'], ['กะ 12 ชม.', 'รับอายุถึง 60 ปี'], ['mock_doe'], true],
  ['ผู้ดูแลผู้สูงอายุ (Caregiver)', 'job_full', 'บาท/เดือน', 15000, 20000, ['ดูแลผู้สูงอายุ'], ['มีใบผ่านอบรม 70 ชม. จะพิจารณาก่อน'], ['mock_doe', 'mock_jobboard']],
  ['พี่เลี้ยงเด็กรายวัน', 'job_part', 'บาท/วัน', 450, 600, ['เลี้ยงเด็ก'], ['ดูแลเด็กเล็กที่บ้านผู้ว่าจ้าง'], ['mock_gig']],
  ['ช่างซ่อมบำรุงอาคาร', 'job_full', 'บาท/เดือน', 14000, 18000, ['ช่างซ่อม'], ['มีความรู้ไฟฟ้าเบื้องต้น'], ['mock_doe']],
  ['ผู้ช่วยช่างแอร์', 'job_part', 'บาท/วัน', 450, 600, ['ช่างซ่อม'], ['สอนงานให้'], ['mock_jobboard']],
  ['พนักงานกรอกข้อมูล (พาร์ตไทม์)', 'job_part', 'บาท/ชั่วโมง', 60, 80, ['กรอกข้อมูล', 'Excel/ตาราง', 'พิมพ์เอกสาร'], ['ทำที่ออฟฟิศ 4 ชม./วัน'], ['mock_jobboard']],
  ['แอดมินตอบแชทร้านออนไลน์ (ทำที่บ้าน)', 'freelance', 'บาท/เดือน', 6000, 9000, ['ขายของออนไลน์', 'พิมพ์เอกสาร'], ['ทำที่บ้าน ต้องมีมือถือและอินเทอร์เน็ต'], ['mock_gig'], true],
  ['ครูสอนการบ้านเด็กประถม', 'job_part', 'บาท/ชั่วโมง', 150, 250, ['สอนพิเศษ'], ['สอนที่บ้านนักเรียน'], ['mock_gig'], true],
  ['ติวภาษาอังกฤษออนไลน์', 'freelance', 'บาท/ชั่วโมง', 200, 350, ['ภาษาอังกฤษ', 'สอนพิเศษ'], ['สอนผ่านวิดีโอคอล'], ['mock_gig']],
  ['พนักงานคอลเซ็นเตอร์', 'job_full', 'บาท/เดือน', 13000, 15000, ['พิมพ์เอกสาร'], ['มีประกันสังคม', 'อบรมก่อนเริ่มงาน'], ['mock_jobboard']],
  ['คนสวนรายวัน', 'job_part', 'บาท/วัน', 400, 500, ['ทำสวน'], ['งานกลางแจ้ง'], ['mock_gig'], true],
  ['ช่างเย็บผ้าโรงงาน', 'job_full', 'บาท/วัน', 400, 480, ['เย็บผ้า'], ['ทำงาน จ.-ส.'], ['mock_doe']],
  ['ผู้ช่วยช่างตัดผม', 'job_part', 'บาท/วัน', 400, 550, ['ตัดผม'], ['สอนงานให้'], ['mock_jobboard']],
  ['พนักงานต้อนรับโรงแรม (สื่อสารภาษาจีน)', 'job_full', 'บาท/เดือน', 15000, 19000, ['ภาษาจีน', 'ภาษาอังกฤษ'], ['มีค่าบริการเพิ่ม'], ['mock_jobboard']],
  ['คนงานก่อสร้างรายวัน', 'job_part', 'บาท/วัน', 400, 500, [], ['จ่ายรายสัปดาห์'], ['mock_doe']],
  ['พนักงานโรงงานอาหาร (กะ)', 'job_full', 'บาท/เดือน', 12000, 15000, ['ทำอาหาร'], ['มีรถรับส่งบางจุด', 'มีประกันสังคม'], ['mock_doe']],
  ['พนักงานต้อนรับห้างสรรพสินค้า (รับผู้สูงอายุ)', 'job_part', 'บาท/ชั่วโมง', 50, 60, ['ขายหน้าร้าน'], ['รับอายุ 55-65 ปี', '4 ชม./วัน'], ['mock_doe'], true],
  ['พนักงานทั่วไป (ไม่ระบุค่าจ้าง)', 'job_full', null, 0, 0, [], ['ประกาศไม่ระบุค่าจ้าง ต้องสอบถามผู้ประกาศ'], ['mock_doe']]
];

const trainings = [
  ['ทำขนมไทยเพื่ออาชีพ', ['ทำขนม/เบเกอรี่']], ['ช่างซ่อมเครื่องใช้ไฟฟ้าในบ้าน', ['ช่างซ่อม']], ['นวดแผนไทยเพื่อสุขภาพ 150 ชม.', []],
  ['ตัดผมชายเบื้องต้น', ['ตัดผม']], ['ตัดเย็บเสื้อผ้า', ['เย็บผ้า']], ['ขายของออนไลน์และไลฟ์สดขายของ', ['ขายของออนไลน์']],
  ['ทำอาหารกล่องขายในชุมชน', ['ทำอาหาร']], ['บาริสต้า ชงกาแฟ', []], ['ผู้ดูแลผู้สูงอายุ 70 ชม.', ['ดูแลผู้สูงอายุ']], ['Excel เบื้องต้นสำหรับงานสำนักงาน', ['Excel/ตาราง']],
  ['ช่างเชื่อมโลหะ ระดับ 1', ['ช่างซ่อม']], ['ภาษาอังกฤษสำหรับงานบริการ', ['ภาษาอังกฤษ']]
];
const sells = [
  ['ตลาดนัดชุมชน เปิดให้จองแผงวันเสาร์-อาทิตย์', 'ค่าเช่าแผงแล้วแต่ตลาด รายได้ขึ้นกับยอดขาย', ['จองแผงล่วงหน้า']],
  ['จุดรับซื้อขวด กระดาษ ของเก่า', 'ราคารับซื้อตามวัน ต้องสอบถามร้าน', ['โทรถามราคาก่อนไป']],
  ['ร้านรับฝากขายของมือสอง', 'แบ่งรายได้ตามที่ตกลงกับร้าน', ['นำของไปให้ร้านประเมิน']],
  ['ตลาดเกษตรกรและผักปลอดสาร', 'รายได้ขึ้นกับผลผลิต', ['ต้องลงทะเบียนผู้ขาย']],
  ['ตลาดนัดคนพิการและผู้สูงอายุ (แผงฟรี)', 'แผงฟรี รายได้ขึ้นกับยอดขาย', ['สำหรับคนพิการและผู้สูงอายุ']]
];
const funds = [
  ['ทุนประกอบอาชีพสำหรับผู้มีรายได้น้อย', 3000, 5000, ['มีบัตรสวัสดิการแห่งรัฐ', 'ไม่ต้องคืน']],
  ['อุปกรณ์ประกอบอาชีพสำหรับคนพิการ', 5000, 10000, ['มีบัตรประจำตัวคนพิการ', 'ให้เป็นอุปกรณ์ ไม่ใช่เงินสด']],
  ['ทุนการศึกษาบุตรครอบครัวรายได้น้อย', 2000, 5000, ['บุตรกำลังเรียน', 'ไม่ต้องคืน']],
  ['เงินช่วยเหลือครอบครัวเปราะบางรายครั้ง', 1000, 3000, ['ผ่านการเยี่ยมบ้านของเจ้าหน้าที่', 'ไม่ต้องคืน']]
];

const items = [];
const at = (dName) => {
  const d = districts.find(x => x[0] === dName) || pick(districts);
  return { district: d[0], lat: +(d[1] + (rnd() - 0.5) * 0.03).toFixed(6), lng: +(d[2] + (rnd() - 0.5) * 0.03).toFixed(6) };
};
let n = 0;
for (const [title, category, unit, min, max, skills, conditions, provs, older] of jobs) {
  for (const prov of provs) {
    const copies = prov === 'mock_gig' ? 1 : 2;
    for (let i = 0; i < copies; i++) {
      const loc = at(pick(districts)[0]), name = pick(names);
      items.push({
        provider: prov, externalId: 'j' + (++n), title, organization: providers[prov].org(name), category, mapGroup: 'job', skills, forOlder: !!older,
        location: prov === 'mock_gig' && /ออนไลน์|ทำที่บ้าน/.test(title + conditions.join(' ')) ? { precision: 'none', text: 'ทำที่บ้าน / ออนไลน์' } : { precision: 'exact', text: 'เขต' + loc.district + ' (ที่อยู่ตัวอย่าง)', lat: loc.lat, lng: loc.lng },
        money: unit ? { basis: 'listing', min, max, unit } : { basis: 'none', knownText: 'ประกาศไม่ระบุค่าจ้าง ต้องสอบถามผู้ประกาศ' },
        conditions: [...conditions, providers[prov].note], ageDays: Math.floor(rnd() * 20)
      });
    }
  }
}
trainings.forEach(([title, skills], i) => {
  const loc = at(pick(districts)[0]), start = new Date(Date.UTC(2026, 11, 1 + Math.floor(rnd() * 40)));
  items.push({ provider: 'mock_dsd', externalId: 't' + (i + 1), title: 'ฝึกอาชีพฟรี: ' + title, organization: 'สถาบันพัฒนาฝีมือแรงงาน เขต' + loc.district + ' (จำลอง)', category: 'skill', mapGroup: 'skill', skills,
    location: { precision: 'exact', text: 'เขต' + loc.district + ' (ที่อยู่ตัวอย่าง)', lat: loc.lat, lng: loc.lng },
    money: { basis: 'none', knownText: 'ฝึกฟรี ไม่ใช่เงินสด บางหลักสูตรมีอาหารกลางวันหรือค่าเดินทาง (จำลอง)' },
    conditions: ['เริ่ม ' + start.toISOString().slice(0, 10) + ' (วันที่จำลอง)', 'อายุ 18 ปีขึ้นไป', 'จำลองข้อมูลจากระบบหลักสูตรฝึกอาชีพภาครัฐ'], ageDays: Math.floor(rnd() * 10) });
});
sells.forEach(([title, known, conditions], i) => {
  const loc = at(pick(districts)[0]);
  items.push({ provider: 'mock_market', externalId: 's' + (i + 1), title, organization: 'ตลาด/ร้านในเขต' + loc.district + ' (จำลอง)', category: 'sell', mapGroup: 'sell', skills: i === 3 ? ['ทำสวน'] : [],
    location: { precision: 'exact', text: 'เขต' + loc.district + ' (ที่อยู่ตัวอย่าง)', lat: loc.lat, lng: loc.lng }, money: { basis: 'none', knownText: known },
    conditions: [...conditions, 'จำลองข้อมูลจากรายชื่อตลาดและจุดรับซื้อ'], ageDays: Math.floor(rnd() * 30) });
});
funds.forEach(([title, min, max, conditions], i) => items.push({ provider: 'mock_fund', externalId: 'f' + (i + 1), title: title + ' (จำลอง)', organization: 'หน่วยงานให้ทุน (จำลอง)', category: 'grant', mapGroup: 'money', skills: [],
  location: { precision: 'none', text: 'ยื่นที่สำนักงานเขตหรือออนไลน์ (จำลอง)' }, money: { basis: 'listing', min, max, unit: 'บาท ครั้งเดียว ตามโครงการ (จำลอง)' },
  conditions: [...conditions, 'ข้อมูลจำลอง ยังไม่ได้ตรวจกับหน่วยงานจริง ต้องผ่านการพิจารณา'], ageDays: Math.floor(rnd() * 30) }));

const out = { note: 'GENERATED by gen-mock-opportunities.js. DEMO / MOCK only: not real listings, employers, courses or funds.', providers: Object.keys({ ...providers, mock_dsd: 1, mock_market: 1, mock_fund: 1 }), items };
fs.writeFileSync(__dirname + '/opportunities-mock.json', JSON.stringify(out, null, 1));
console.log('wrote ' + items.length + ' items');
