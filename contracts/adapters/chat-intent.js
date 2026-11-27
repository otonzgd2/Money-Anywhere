const { thaiDigits } = require('./guard');

const intentQuestion = 'อยากเริ่มจากเช็กสิทธิรับเงิน หรือวางแผนหาเงินเพิ่ม?';
const intentOptions = ['เช็กสิทธิรับเงิน', 'วางแผนหาเงินเพิ่ม'];
const benefitOptions = ['เช็กสิทธิเบี้ยผู้สูงอายุ', 'เช็กเบี้ยความพิการ', 'เช็กเงินว่างงาน', 'เช็กเงินคืนภาษี', 'ดูรายการสิทธิทั้งหมด'];
const benefitTopics = {
  old_age: /เบี้ย(?:ยังชีพ)?(?:ผู้สูงอายุ|คนชรา)|เงินผู้สูงอายุ|เบี้ย(?:งวดนี้)?ไม่เข้า|เบี้ยยังไม่เข้า/,
  disability: /เบี้ย(?:ความพิการ|คนพิการ)|เงินคนพิการ|บัตร(?:ประจำตัว)?คนพิการ/,
  unemployment: /(?:เงิน(?:ทดแทนกรณี)?|เงินทดแทน)?ว่างงาน|เงินตกงาน/,
  tax_refund: /คืนภาษี|ภาษีคืน|ภาษีหัก/,
  unpaid_wages: /ค่าจ้างค้าง|เงินเดือนค้าง/,
  child_support: /(?:เงิน)?อุดหนุนเด็ก|เงินเลี้ยงดูเด็ก/,
  social_security_retirement: /ชราภาพ/,
};
const followPayment = /เบี้ย.*(?:ไม่เข้า|ค้าง)|สถานะ(?:การ)?รับเบี้ย|ยังไม่ได้รับเบี้ย|ติดตาม(?:เงิน|เบี้ย)/;
const eligibility = /เช็[กค]สิทธิ|ตรวจสิทธิ|มีสิทธิ[์]?ไหม|ควรได้เงินอะไร|สิทธิที่อาจช่วย|อยากรู้.*สิทธิ/;
const programRequest = /(?:เงินช่วยเหลือ|โครงการ|ประกาศ).*(?:สิทธิ|รับ(?:ได้|เงิน)|เช็[กค])|(?:เช็[กค]|สิทธิ).*(?:เงินช่วยเหลือ|โครงการ)/;
const jobRequest = /หางาน|(?:หา|ขอ|มี|แนะนำ|อยาก|ช่วย).{0,24}(?:ทำ|งาน)(?:ที่|จาก)บ้าน|อยากทำงาน|ทำงาน(?:อะไร|ที่บ้าน|จากบ้าน)|(?:งาน|รายได้)(?:เสริม|เพิ่ม)|ฝึกอาชีพ/;
const targetRequest = /อยาก(?:ได้|มี)(?:เงิน|ตัง|รายได้|เพิ่ม)|อยากได้(?=\s*\d)|อยากให้ถึง|(?:ขอ|ช่วย|วางแผน)?หาเงิน|เป้าหมายรายได้|ได้เงินเพิ่ม|ต้องการ(?:เงิน|รายได้|\s*\d)|อยากได้เดือนละ/;
const expense = /ค่าเช่า(?:ห้อง|บ้าน)?|ค่าไฟ|ค่าน้ำ|ค่าเดินทาง|ค่าเทอม|ค่ากิน|ค่าใช้จ่าย/;
const monthly = /รายเดือน|เดือนละ|ต่อเดือน|\/เดือน/;
const lumpSum = /เงินก้อน|ก้อนเดียว|ครั้งเดียว/;
const otherSubject = /(?:เช็[กค]|ตรวจ|ดูสิทธิ|ช่วยดู|สมัคร).{0,28}(?:ให้|ของ)(?:คุณ)?(?:พ่อ|แม่|ลูก|ปู่|ย่า|ตา|ยาย|พี่|น้อง|สามี|ภรรยา|เพื่อน)(?!ค้า)|^(?:คุณ)?(?:แม่|พ่อ|ยาย|ตา|ลูก)(?:ฉัน|ผม|หนู)?อายุ/;
const self = /ให้(?:ฉัน|ผม|หนู|ตัวเอง)|ของ(?:ฉัน|ผม|หนู)|(?:ฉัน|ผม|หนู)อายุ|อายุของฉัน/;
const shortAnswer = /^(ใช่|ไม่ใช่|มี|ไม่มี|แล้ว|ยัง|ได้|ไม่ได้|เคย|ไม่เคย|เรียบร้อย|(?:ขึ้น|ยื่น|ทำ|ส่ง|สมัคร)แล้ว|ยังไม่(?:ได้)?(?:ขึ้น|ยื่น|ทำ|ส่ง|สมัคร)?)(?:\s*(?:ค่ะ|ครับ|คะ))?$/;
const moneyText = value => value.toLocaleString('en-US');

function topicRequests(raw) {
  const text = thaiDigits(raw);
  const topics = Object.entries(benefitTopics).flatMap(([id, pattern]) => {
    const match = pattern.exec(text);
    if (!match) return [];
    return [{ id, index: match.index, mode: id === 'old_age' && followPayment.test(text) ? 'payment'
      : id === 'disability' && /เงินเพิ่ม|ส่วนเพิ่ม|สวัสดิการ/.test(text) ? 'supplement' : 'eligibility' }];
  });
  if (!topics.some(topic => topic.id === 'old_age') && followPayment.test(text) && /เบี้ย/.test(text)) {
    topics.push({ id: 'old_age', index: text.indexOf('เบี้ย'), mode: 'payment' });
  }
  const income = jobRequest.exec(text) || targetRequest.exec(text);
  if (!topics.length && programRequest.test(text)) {
    topics.push({ id: 'program', index: 0, amount: parseGoal(text).amount });
  }
  if (income && (!topics.length || /(?:แล้ว|และ|กับ|ด้วย).*(?:วางแผน|หาเงิน|หางาน)|อยากได้ตัง/.test(text)
    || topics.every(topic => topic.mode === 'supplement' && jobRequest.test(text)))) {
    const start = /ไม่(?:ได้)?$/.test(text.slice(0, income.index)) ? 0 : income.index;
    const incomeText = text.slice(start);
    topics.push({ id: 'income', index: start, goal: parseGoal(incomeText),
      remote: /(?:ที่|จาก)บ้าน/.test(incomeText), limitedTravel: /เดิน(?:ทาง)?ไกลไม่ไหว|ไม่สะดวกเดินทาง|ไม่มีรถ/.test(incomeText) });
  }
  if (!topics.length && eligibility.test(text)) topics.push({ id: 'benefits', index: 0 });
  return topics.sort((a, b) => a.index - b.index);
}

const thaiNumbers = { ศูนย์: 0, หนึ่ง: 1, เอ็ด: 1, สอง: 2, ยี่: 2, สาม: 3, สี่: 4, ห้า: 5, หก: 6, เจ็ด: 7, แปด: 8, เก้า: 9 };
const thaiUnits = { สิบ: 10, ร้อย: 100, พัน: 1000, หมื่น: 10000, แสน: 100000, ล้าน: 1000000 };
const thaiTokens = new RegExp(Object.keys({ ...thaiNumbers, ...thaiUnits }).join('|'), 'g');
const thaiAmount = /(?:(?:หนึ่ง|สอง|ยี่|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า)?(?:ล้าน|แสน|หมื่น|พัน|ร้อย|สิบ))+(?:หนึ่ง|เอ็ด|สอง|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า)?/g;
const bangkokCalendar = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Bangkok' });

function wordAmount(value) {
  let amount = 0, digit;
  for (const token of value.match(thaiTokens)) {
    if (token in thaiNumbers) digit = thaiNumbers[token];
    else if (token === 'ล้าน') { amount = Math.max(1, amount + (digit ?? 0)) * thaiUnits[token]; digit = undefined; }
    else { amount += (digit ?? 1) * thaiUnits[token]; digit = undefined; }
  }
  return amount + (digit ?? 0);
}

function bangkokDay(now) {
  return bangkokCalendar.format(now);
}

function dueDate(text, today) {
  const [year, month, day] = today.split('-').map(Number);
  const iso = text.match(/(?:กำหนด|ภายใน|จ่าย|ต้องใช้|วันที่)\s*(\d{4})-(\d{2})-(\d{2})/);
  if (iso) {
    const [, y, m, d] = iso;
    const date = new Date(Date.UTC(Number(y), Number(m) - 1, Number(d))).toISOString().slice(0, 10);
    return date === iso[0].slice(-10) ? date : null;
  }
  if (/สิ้นเดือน|ปลายเดือน/.test(text)) return new Date(Date.UTC(year, month, 0)).toISOString().slice(0, 10);
  if (/พรุ่งนี้/.test(text)) return new Date(Date.UTC(year, month - 1, day + 1)).toISOString().slice(0, 10);
  if (/วันนี้/.test(text)) return today;
  return undefined;
}

function parseGoal(raw, today) {
  const text = thaiDigits(raw);
  const dates = Array.from(text.matchAll(/\d{4}-\d{2}-\d{2}/g), match => [match.index, match.index + match[0].length]);
  const kind = monthly.test(text) && !lumpSum.test(text) ? 'monthly'
    : lumpSum.test(text) || (expense.test(text) && /สิ้นเดือน|พรุ่งนี้|จ่าย|ภายใน|ต้องใช้/.test(text)) ? 'once' : undefined;
  const amounts = [
    ...Array.from(text.matchAll(/[-−+]?\s*\d[\d,]*(?:\.\d+)?/g), match => ({ index: match.index, end: match.index + match[0].length, value: Number(match[0].replace(/[,\s]/g, '').replace('−', '-')) })),
    ...Array.from(text.matchAll(thaiAmount), match => ({ index: match.index, end: match.index + match[0].length, value: wordAmount(match[0]) })),
  ].sort((a, b) => a.index - b.index).filter(({ index, end }) =>
    !dates.some(([first, last]) => index < last && end > first) &&
    !/อายุ\s*$|วันที่\s*$|ภายใน\s*$/.test(text.slice(0, index)) &&
    !/^\s*(?:ปี|วัน(?!ละ)|ชั่วโมง|โมง|[-/]\d)/.test(text.slice(end)));
  const goalSignals = /อยาก(?:ได้|มี)(?:เงิน|ตัง|รายได้|เพิ่ม)?|อยากให้ถึง|ขอแก้เป็น|เปลี่ยนเป็น|ต้องการ|หาเงิน|(?:เงิน)?ก้อน/;
  const matchesGoal = amounts.filter(({ index }) => goalSignals.test(text.slice(0, index).split(/แต่|หรือ|แล้ว|และ/).at(-1)));
  const chosen = amounts.length === 1 ? amounts[0] : matchesGoal.length === 1 && !/หรือ/.test(text) ? matchesGoal[0] : undefined;
  const deadline = today ? dueDate(text, today) : undefined;
  return {
    kind, amount: chosen?.value, deadline, expense: text.match(expense)?.[0],
    ambiguous: amounts.length > 1 && (!chosen || /อยากให้ถึง/.test(text)),
    denied: /ไม่(?:ได้)?(?:อยาก|ต้องการ)|ไม่เอา(?:ยอด|เป้า)|ยกเลิกเป้า/.test(text),
    skip: /^(?:ข้าม|(?:ยัง)?ไม่แน่ใจ|(?:ยัง)?ไม่รู้|ดูทางเลือก)|ยังไม่รู้ว่าอยากได้เท่าไหร่/.test(text),
  };
}

function answerValue(step, raw) {
  const text = thaiDigits(raw).replace(/\s*(?:ค่ะ|ครับ|คะ|จ้ะ)$/u, '').trim();
  if (step.options?.includes(text)) return step.type === 'bool' ? step.options[0] === text : text;
  if (step.fact === 'ageBand') {
    const age = /^(?:อายุ\s*)?(\d{1,3})\s*(?:ปี)?(?:แล้ว)?$/.exec(text);
    if (age && Number(age[1]) <= 120) {
      const n = Number(age[1]);
      return n < 60 ? 'ต่ำกว่า 60' : n >= 90 ? '90 ขึ้นไป' : Math.floor(n / 10) * 10 + '-' + (Math.floor(n / 10) * 10 + 9);
    }
  }
  if (step.type === 'bool') {
    if (/^(?:ใช่|มี|ได้รับ(?:อยู่แล้ว)?|ได้(?:รับ)?(?:แล้ว)?|เคย|ครบ|เป็น)$/.test(text)) return true;
    if (/^(?:ไม่ใช่|ไม่มี|ไม่(?:ได้)?รับ|ไม่ได้|ยัง(?:ไม่(?:ได้)?(?:รับ)?)?|ไม่เคย|ไม่ครบ|ไม่เป็น)$/.test(text)) return false;
  }
  if (step.type === 'number') {
    if (/^(?:ไม่มี|ไม่ค้าง|ไม่เคย|ศูนย์)$/.test(text)) return 0;
    const number = /^(-?\d[\d,]*(?:\.\d+)?)\s*(?:บาท|วัน|ปี|เดือน)?$/.exec(text);
    if (number) return Number(number[1].replace(/,/g, ''));
  }
  if (step.type === 'text' && step.fact === 'registryDistrict' && /^(?:เขต|อำเภอ)?\s*[\p{Script=Thai}\s]{2,40}$/u.test(text)) return text;
  return undefined;
}

module.exports = { intentQuestion, intentOptions, benefitOptions, expense, jobRequest, monthly, lumpSum, otherSubject, self,
  shortAnswer, moneyText, topicRequests, parseGoal, bangkokDay, answerValue };
