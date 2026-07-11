import { readdirSync } from 'node:fs';
import { extname, join } from 'node:path';
import { spawnSync } from 'node:child_process';

const sourceDirectories = ['src', 'bin'];
const files = sourceDirectories.flatMap((directory) =>
  readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isFile() && extname(entry.name) === '.js')
    .map((entry) => join(directory, entry.name)),
);

for (const file of files) {
  const result = spawnSync(process.execPath, ['--check', file], { stdio: 'inherit' });
  if (result.status !== 0) process.exit(result.status ?? 1);
}

console.log(`Checked ${files.length} JavaScript files.`);
