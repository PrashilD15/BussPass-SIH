const fs = require('fs');
let content = fs.readFileSync('msrtc_data.js', 'utf8');

const routeStr = "  ['pune-station',    'nashik-cbs',      212, ['Ordinary', 'Semi Luxury'], ['Sangamner']],";
const insertStr = "\n  // Sangamner ⇄ Mumbai (via Nashik)\n  ['mumbai-central',  'sangamner',       245, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['nashik-cbs']],\n  ['mumbai-borivali', 'sangamner',       250, ['Ordinary', 'Semi Luxury', 'Shivshahi'], ['nashik-cbs']],";

if (content.includes(routeStr)) {
  content = content.replace(routeStr, routeStr + insertStr);
  fs.writeFileSync('msrtc_data.js', content);
  console.log('Patched msrtc_data.js successfully');
} else {
  console.error('Could not find anchor string in msrtc_data.js');
}
