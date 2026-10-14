const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
fs.mkdirSync(path.join(__dirname, '../test-output'), { recursive: true });
const studio = process.env.DEVECO_STUDIO_HOME || '/Applications/DevEco-Studio.app/Contents';
const typescript = require(process.env.SOLAR_TYPESCRIPT_PATH ||
  path.join(studio, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));

// Only framework-free ArkTS and the file service are executed in Node. The native
// UI and all ArkTS restrictions are separately checked by the official HAP build.
Module._extensions['.ets'] = (module, filename) => {
  const result = typescript.transpileModule(fs.readFileSync(filename, 'utf8'), {
    fileName: filename.replace(/\.ets$/, '.ts'),
    compilerOptions: { module: typescript.ModuleKind.CommonJS, target: typescript.ScriptTarget.ES2021 },
    reportDiagnostics: true
  });
  const errors = result.diagnostics.filter(d => d.category === typescript.DiagnosticCategory.Error);
  if (errors.length) throw new Error(errors.map(d => typescript.flattenDiagnosticMessageText(d.messageText, '\n')).join('\n'));
  module._compile(result.outputText, filename);
};
