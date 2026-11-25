// Standard-tool checks: OpenAPI 3.0 validity (swagger-parser) and app-config against its JSON Schema (Ajv 2020-12).
// Run: node validate-contracts.js   (inside contracts/, after npm install)
const path = require('path');
const fs = require('fs');
const SwaggerParser = require('@apidevtools/swagger-parser');
const Ajv2020 = require('ajv/dist/2020');

(async () => {
  let failed = false;
  try {
    const api = await SwaggerParser.validate(path.join(__dirname, 'openapi.yaml'));
    const ops = Object.values(api.paths).reduce((n, p) => n + Object.keys(p).filter(k => ['get', 'post', 'put', 'patch', 'delete'].includes(k)).length, 0);
    console.log('PASS openapi.yaml is valid OpenAPI ' + api.openapi + ' (' + ops + ' operations)');
  } catch (e) { failed = true; console.log('FAIL openapi.yaml: ' + e.message); }

  const ajv = new Ajv2020({ allErrors: true, strict: false });
  const schema = JSON.parse(fs.readFileSync(path.join(__dirname, 'app-config.schema.json'), 'utf8'));
  const validate = ajv.compile(schema);
  const files = process.argv.slice(2).length ? process.argv.slice(2) : [path.join(__dirname, 'app-config.sample.json')];
  for (const f of files) {
    const ok = validate(JSON.parse(fs.readFileSync(f, 'utf8')));
    if (ok) console.log('PASS ' + path.basename(f) + ' matches app-config.schema.json');
    else { failed = true; console.log('FAIL ' + path.basename(f) + ':\n  ' + validate.errors.map(e => e.instancePath + ' ' + e.message).join('\n  ')); }
  }
  console.log(failed ? 'RESULT: FAIL' : 'RESULT: PASS');
  process.exit(failed ? 1 : 0);
})();
