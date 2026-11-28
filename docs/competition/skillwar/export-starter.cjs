const { createHash } = require('node:crypto');
const { mkdirSync, readFileSync, writeFileSync } = require('node:fs');
const { dirname, join, resolve, relative, isAbsolute, sep } = require('node:path');
const manifest = require('./starter-manifest.json');

const source = resolve(__dirname, '../../..');
const usage = 'node docs/competition/skillwar/export-starter.cjs <new-directory> [--with-reference-data] [--with-mock-inputs]';

function run([destination, ...flags]) {
  const optional = { '--with-reference-data': 'reference-data', '--with-mock-inputs': 'mock-inputs' };
  if (!destination || destination.startsWith('--') || flags.some(flag => !Object.hasOwn(optional, flag))) {
    throw new Error(usage);
  }
  const output = resolve(destination);
  const relativeOutput = relative(source, output);
  if (!relativeOutput || (!isAbsolute(relativeOutput) && relativeOutput !== '..' && !relativeOutput.startsWith('..' + sep))) {
    throw new Error('The new directory must be outside the preparation repository.');
  }

  const groups = ['blueprint', ...new Set(flags.map(flag => optional[flag]))];
  const paths = new Set(groups.flatMap(group => manifest.groups[group].paths));
  const files = [...paths].map(path => ({ path, content: readFileSync(join(source, path)) }));
  mkdirSync(output);
  const inventory = files.map(({ path, content }) => {
    const target = join(output, path);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, content, { flag: 'wx' });
    return { path, sha256: createHash('sha256').update(content).digest('hex') };
  });
  writeFileSync(join(output, 'STARTER-INVENTORY.json'), JSON.stringify({
    baseline: manifest.baseline,
    groups,
    files: inventory,
  }, null, 2) + '\n', { flag: 'wx' });
  console.log(`Wrote ${files.length} files and STARTER-INVENTORY.json to ${output}`);
}

try {
  run(process.argv.slice(2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
