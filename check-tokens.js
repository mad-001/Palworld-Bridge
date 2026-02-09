// Token diagnostic script
// Run this to see exactly what tokens the bridge is reading

const fs = require('fs');
const path = require('path');

console.log('=== Takaro Token Diagnostic ===\n');

const configPath = path.join(process.cwd(), 'TakaroConfig.txt');

if (!fs.existsSync(configPath)) {
  console.error('❌ ERROR: TakaroConfig.txt not found in current directory!');
  console.error('Current directory:', process.cwd());
  process.exit(1);
}

console.log('✅ Found TakaroConfig.txt');
console.log('Path:', configPath);
console.log();

const configContent = fs.readFileSync(configPath, 'utf-8');

// Parse config (same logic as bridge)
const config = {};
configContent.split('\n').forEach((line, index) => {
  const trimmedLine = line.trim();
  if (trimmedLine && !trimmedLine.startsWith('#')) {
    const [key, ...valueParts] = trimmedLine.split('=');
    const value = valueParts.join('=').trim();
    if (key && value) {
      config[key.trim()] = value;
    }
  }
});

console.log('=== Token Analysis ===\n');

// Check IDENTITY_TOKEN
if (config.IDENTITY_TOKEN) {
  const token = config.IDENTITY_TOKEN;
  console.log('IDENTITY_TOKEN:');
  console.log('  ✅ Found');
  console.log('  Length:', token.length, 'characters');
  console.log('  First 20 chars:', token.substring(0, 20) + '...');
  console.log('  Last 20 chars:', '...' + token.substring(token.length - 20));
  console.log('  Has spaces:', token.includes(' ') ? '⚠️ YES (BAD!)' : '✅ No');
  console.log('  Has tabs:', token.includes('\t') ? '⚠️ YES (BAD!)' : '✅ No');
  console.log('  Has newlines:', token.includes('\n') || token.includes('\r') ? '⚠️ YES (BAD!)' : '✅ No');
  console.log();
} else {
  console.log('IDENTITY_TOKEN: ❌ NOT FOUND!\n');
}

// Check REGISTRATION_TOKEN
if (config.REGISTRATION_TOKEN) {
  const token = config.REGISTRATION_TOKEN;
  console.log('REGISTRATION_TOKEN:');
  console.log('  ✅ Found');
  console.log('  Length:', token.length, 'characters');
  console.log('  First 20 chars:', token.substring(0, 20) + '...');
  console.log('  Last 20 chars:', '...' + token.substring(token.length - 20));
  console.log('  Has spaces:', token.includes(' ') ? '⚠️ YES (BAD!)' : '✅ No');
  console.log('  Has tabs:', token.includes('\t') ? '⚠️ YES (BAD!)' : '✅ No');
  console.log('  Has newlines:', token.includes('\n') || token.includes('\r') ? '⚠️ YES (BAD!)' : '✅ No');
  console.log();
} else {
  console.log('REGISTRATION_TOKEN: ❌ NOT FOUND!\n');
}

console.log('=== Other Settings ===\n');
console.log('PALWORLD_HOST:', config.PALWORLD_HOST || '(not set, will use 127.0.0.1)');
console.log('PALWORLD_PORT:', config.PALWORLD_PORT || '(not set, will use 8212)');
console.log('PALWORLD_USERNAME:', config.PALWORLD_USERNAME || '(not set)');
console.log('PALWORLD_PASSWORD:', config.PALWORLD_PASSWORD ? '***hidden***' : '(not set)');
console.log();

console.log('=== Raw Config File ===');
console.log('(Showing line-by-line with special chars visible)\n');
configContent.split('\n').forEach((line, i) => {
  const displayLine = line
    .replace(/\r/g, '\\r')
    .replace(/\t/g, '\\t');
  console.log(`Line ${i + 1}: "${displayLine}"`);
});
