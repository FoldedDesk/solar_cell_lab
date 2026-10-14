import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { LabSession } from '../model/Lab';
import { utf8 } from '../model/Export';

export class SessionStore {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }

  load(): LabSession {
    try {
      const path = `${this.context.filesDir}/session-v1.json`;
      if (!fileIo.accessSync(path)) { return new LabSession(); }
      if (fileIo.statSync(path).size > 2 * 1024 * 1024) { throw new Error('本地实验文件过大'); }
      return LabSession.decode(fileIo.readTextSync(path));
    } catch (error) { throw new Error(`无法读取实验：${(error as Error).message}`); }
  }

  save(session: LabSession): void {
    try {
      const path = `${this.context.filesDir}/session-v1.json`;
      const temp = path + '.tmp';
      writeFile(temp, utf8(JSON.stringify(session)));
      fileIo.renameSync(temp, path);
    } catch (error) { throw new Error(`无法保存实验：${(error as Error).message}`); }
  }
}

function writeFile(path: string, bytes: Uint8Array): void {
  try {
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      let offset = 0;
      while (offset < bytes.length) {
        const buffer = bytes.slice(offset).buffer as ArrayBuffer;
        const written = fileIo.writeSync(file.fd, buffer);
        if (written <= 0) { throw new Error('文件写入未完成'); }
        offset += written;
      }
      fileIo.fsyncSync(file.fd);
    } finally { fileIo.closeSync(file); }
  } catch (error) { throw new Error(`写入文件失败：${(error as Error).message}`); }
}

export async function saveDocument(context: common.UIAbilityContext, name: string, extension: string,
  bytes: Uint8Array): Promise<boolean> {
  const options = new picker.DocumentSaveOptions();
  options.newFileNames = [name];
  options.fileSuffixChoices = [extension.toUpperCase() + '|.' + extension];
  const paths = await new picker.DocumentViewPicker(context).save(options);
  if (paths.length === 0) { return false; }
  writeFile(paths[0], bytes);
  return true;
}
