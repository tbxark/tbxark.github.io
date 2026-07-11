import fs from "fs";
import path from "path";
import { parseArgs } from "./utils.js";

const argv = parseArgs();
const apiDir = argv.s || './api';
const outputFile = argv.t || './src/data.js';
const files = ['blogs.json', 'exes.json', 'repos.json'];

let jsContent = '// Auto-generated file - DO NOT EDIT\n';
jsContent += `// Generated on ${new Date().toISOString()}\n\n`;

for (const file of files) {
    const filePath = path.join(apiDir, file);
    const varName = path.basename(file, '.json');

    try {
        const content = fs.readFileSync(filePath, 'utf8');
        const data = JSON.parse(content);
        jsContent += `window.${varName} = ${JSON.stringify(data)};\n\n`;
        console.log(`✓ Loaded ${varName}: ${data.length} items`);
    } catch (error) {
        console.error(`✗ Error reading ${file}:`, error.message);
        jsContent += `window.${varName} = [];\n\n`;
    }
}

fs.writeFileSync(outputFile, jsContent);
console.log(`✓ Generated ${outputFile}`);
