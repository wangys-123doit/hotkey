const { spawn } = require('child_process');
const host = process.env.LOCALAPPDATA + '\\TDuckVSCodeNativeHost\\host.cmd';
const cp = spawn(host, [], { shell: true, stdio: ['pipe','pipe','inherit'] });
const payload = JSON.stringify({ action: 'open', path: 'D:/code/jd-tduck-x-front/src/views/system/customTable/documentField.vue', line: 264, column: 1 });
const msg = Buffer.from(payload, 'utf8');
const header = Buffer.alloc(4);
header.writeUInt32LE(msg.length, 0);
let buf = Buffer.alloc(0);
cp.stdout.on('data', d => {
  buf = Buffer.concat([buf, d]);
  if (buf.length >= 4) {
    const len = buf.readUInt32LE(0);
    if (buf.length >= 4 + len) {
      const body = buf.slice(4, 4 + len).toString('utf8');
      console.log('RESP_INSTALLED', body);
      try { cp.kill(); } catch(e) {}
    }
  }
});
cp.stdin.write(Buffer.concat([header, msg]));
cp.stdin.end();
setTimeout(()=>{ try{ cp.kill(); }catch(e){} }, 4000);
