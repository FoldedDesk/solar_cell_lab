#!/usr/bin/env python3
"""Build using the tools bundled with DevEco, without modifying the SDK or user caches."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_STUDIO = Path('/Applications/DevEco-Studio.app/Contents')


def main():
    studio = Path(os.environ.get('DEVECO_STUDIO_HOME', str(DEFAULT_STUDIO))).expanduser().resolve()
    tools = studio / 'tools'
    node = tools / 'node' / ('node.exe' if os.name == 'nt' else 'bin/node')
    if not node.is_file() and shutil.which('node'):
        node = Path(shutil.which('node'))
    hvigor = tools / 'hvigor/hvigor/bin/hvigor.js'
    if not node.is_file() or not hvigor.is_file():
        sys.exit('Set DEVECO_STUDIO_HOME to the DevEco installation (macOS: .app/Contents).')
    # Hvigor rejects some non-ASCII project paths.
    # Stage sources in an owned temporary directory; copy deliverables back afterwards.
    temporary = Path(tempfile.mkdtemp(prefix='solar-cell-lab-'))
    project = temporary / 'harmonyos'
    shutil.copytree(ROOT, project, ignore=shutil.ignore_patterns(
        '.git', '.toolchain', '.hvigor', '.idea', '.DS_Store', 'build', 'node_modules', 'oh_modules', 'test-output', '__pycache__', '.venv'))
    modules = project / '.toolchain/node_modules/@ohos'
    modules.mkdir(parents=True, exist_ok=True)
    for name in ('hvigor', 'hvigor-ohos-plugin'):
        link = modules / name
        target = tools / 'hvigor' / name
        if not link.exists():
            link.symlink_to(target, target_is_directory=True)
    env = os.environ.copy()
    env['NODE_PATH'] = str(modules.parent)
    env['NODE_HOME'] = str(node.parent.parent if os.name != 'nt' else node.parent)
    env['DEVECO_SDK_HOME'] = env.get('DEVECO_SDK_HOME', str(studio / 'sdk'))
    env['HVIGOR_USER_HOME'] = str(project / '.toolchain/cache')
    java = studio / ('jbr' if os.name == 'nt' else 'jbr/Contents/Home')
    if java.is_dir():
        env['JAVA_HOME'] = str(java)
    env['PATH'] = str(node.parent) + os.pathsep + env.get('PATH', '')
    args = sys.argv[1:] or ['--mode', 'module', '-p', 'product=default', '-p', 'module=entry@default',
                           '-p', 'buildMode=debug', 'assembleHap', '--no-daemon']
    succeeded = False
    try:
        result = subprocess.run([str(node), str(hvigor), *args], cwd=project, env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        print(result.stdout, end='')
        reports = ROOT / 'test-output'
        reports.mkdir(exist_ok=True)
        (reports / 'build.log').write_text(result.stdout)
        outputs = project / 'entry/build/default/outputs'
        if result.returncode == 0 and outputs.exists():
            shutil.copytree(outputs, ROOT / 'entry/build/default/outputs', dirs_exist_ok=True)
            print('HAP outputs:', ROOT / 'entry/build/default/outputs')
        succeeded = result.returncode == 0
        return result.returncode
    finally:
        if succeeded:
            shutil.rmtree(temporary)
        else:
            print('Build diagnostics retained at:', project)


if __name__ == '__main__':
    sys.exit(main())
