require('./runtime.cjs');
const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const directory = fs.mkdtempSync(path.resolve('test-output/files-'));
const context = { filesDir: directory };
let selectedPaths = [];
let failWrites = false;
let openFiles = 0;
const fileIo = {
  OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
  accessSync: fs.existsSync,
  statSync: fs.statSync,
  readTextSync: p => fs.readFileSync(p, 'utf8'),
  renameSync: fs.renameSync,
  openSync: p => { openFiles++; return { fd: fs.openSync(p, 'w+') }; },
  writeSync: (fd, bytes) => {
    if (failWrites) throw new Error('disk full');
    // Exercise short writes rather than letting an incomplete export pass unnoticed.
    const buffer = Buffer.from(bytes);
    return fs.writeSync(fd, buffer, 0, Math.min(7, buffer.length));
  },
  fsyncSync: fs.fsyncSync,
  closeSync: file => { fs.closeSync(file.fd); openFiles--; }
};
const originalLoad = Module._load;
Module._load = function(request, parent, isMain) {
  if (request === '@kit.CoreFileKit') return {
    fileIo,
    picker: { DocumentSaveOptions: class {}, DocumentViewPicker: class { async save() { return selectedPaths; } } }
  };
  return originalLoad.call(this, request, parent, isMain);
};
const { SessionStore, saveDocument } = require('../entry/src/main/ets/services/Files.ets');
Module._load = originalLoad;
const { LabSession } = require('../entry/src/main/ets/model/Lab.ets');
const { utf8 } = require('../entry/src/main/ets/model/Export.ets');

test('local state round trip, atomic replacement, corruption and failed saves', () => {
  const store = new SessionStore(context);
  assert.equal(store.load().ivRows.length, 0);
  const session = new LabSession(); session.loadStandard(); store.save(session);
  assert.equal(store.load().ivRows.length, 14);
  const before = fs.readFileSync(path.join(directory, 'session-v1.json'), 'utf8');
  session.clearRows(); failWrites = true; assert.throws(() => store.save(session)); failWrites = false;
  assert.equal(fs.readFileSync(path.join(directory, 'session-v1.json'), 'utf8'), before);
  assert.equal(openFiles, 0);
  store.save(session); assert.equal(store.load().ivRows.length, 0);
  fs.writeFileSync(path.join(directory, 'session-v1.json'), 'broken'); assert.throws(() => store.load());
  assert.equal(fs.readFileSync(path.join(directory, 'session-v1.json'), 'utf8'), 'broken');
});

test('file picker cancellation, Unicode export and short writes', async () => {
  const bytes = utf8('太阳能电池 Ω\n25.2 mA');
  selectedPaths = []; assert.equal(await saveDocument(context, '测试.csv', 'csv', bytes), false);
  selectedPaths = [path.join(directory, '测试.csv')];
  assert.equal(await saveDocument(context, '测试.csv', 'csv', bytes), true);
  assert.deepEqual(fs.readFileSync(selectedPaths[0]), Buffer.from(bytes)); assert.equal(openFiles, 0);
  failWrites = true;
  await assert.rejects(saveDocument(context, '测试.csv', 'csv', bytes));
  failWrites = false; assert.equal(openFiles, 0);
});

after(() => fs.rmSync(directory, { recursive: true, force: true }));
