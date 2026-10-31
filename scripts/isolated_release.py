#!/usr/bin/env python3
"""Stage selected changes while retaining an explicitly captured dirty baseline.

The request names complete files and optional baseline files for partial staging.
Plan prints the exact staged patch; publish requires the reviewed patch hash.
Build/deploy uses a committed archive, never unrelated working-tree changes.
"""
import difflib
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parent.parent
REQUEST = ROOT / 'tmp/isolated-release-request.json'
PLAN = ROOT / 'tmp/isolated-release-plan.json'

def run(args, **kw):
    return subprocess.run(args, cwd=ROOT, check=True, **kw)

def out(args):
    return run(args, stdout=subprocess.PIPE).stdout.decode().strip()

def verify():
    assert out(['git', 'remote', 'get-url', 'origin']) == 'git@github.com:kokizzu/TeleAntiSpam2Bot.git'
    assert 'ref: refs/heads/master\tHEAD' in out(['git','ls-remote','--symref','origin','HEAD'])
    assert out(['git','branch','--show-current']) == 'master'
    assert out(['git','rev-parse','--abbrev-ref','@{upstream}']) == 'origin/master'

def patch(request):
    chunks = []
    for name in request['files']:
        baseline = request.get('baselines', {}).get(name)
        if baseline:
            before = (ROOT / baseline).read_text()
        else:
            r = subprocess.run(['git','show','HEAD:'+name],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
            before = r.stdout.decode() if r.returncode == 0 else ''
        after = (ROOT/name).read_text()
        chunks.extend(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='a/'+name if before else '/dev/null',tofile='b/'+name))
    return ''.join(chunks).encode()

def main():
    mode = sys.argv[1]
    verify()
    if mode == 'unstage':
        request = json.loads(REQUEST.read_text())
        assert sorted(out(['git','diff','--cached','--name-only']).splitlines()) == sorted(request['files'])
        run(['git','restore','--staged','--',*request['files']])
    elif mode == 'sync':
        # Fast-forward only; never create a merge commit or abandon local work.
        run(['git','pull','--ff-only','origin','master'])
    elif mode in ('plan','publish'):
        request = json.loads(REQUEST.read_text())
        delta = patch(request)
        value = {'head':out(['git','rev-parse','HEAD']), 'sha256':hashlib.sha256(delta).hexdigest(), 'request':request}
        if mode == 'plan':
            assert not out(['git','diff','--cached','--name-only']), 'preexisting staged work'
            run(['git','apply','--cached','--check'],input=delta)
            PLAN.write_text(json.dumps(value,indent=2)+'\n')
            print(delta.decode())
            print(json.dumps(value,indent=2))
            return
        assert json.loads(PLAN.read_text()) == value, 'plan changed'
        assert not out(['git','diff','--cached','--name-only']), 'preexisting staged work'
        run(['git','apply','--cached'],input=delta)
        run(['git','diff','--cached','--check'])
        assert sorted(out(['git','diff','--cached','--name-only']).splitlines()) == sorted(request['files'])
        print(out(['git','diff','--cached','--stat']))
        tree = out(['git','write-tree'])
        candidate = ROOT/'tmp'/('candidate-'+tree)
        candidate.mkdir(exist_ok=True)
        archive = run(['git','archive','--format=tar',tree],stdout=subprocess.PIPE).stdout
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(candidate, filter='data')
        for goal in ('test','test-ops'):
            subprocess.run(['make',goal],cwd=candidate,check=True)
        run(['git','commit','-m',request['message']])
        run(['git','push','origin','master'])
        print('COMMIT='+out(['git','rev-parse','HEAD']))
    elif mode == 'deploy':
        commit = out(['git','rev-parse','HEAD'])
        target = ROOT/'tmp'/('release-'+commit)
        target.mkdir(exist_ok=False)
        archive = run(['git','archive','--format=tar','HEAD'],stdout=subprocess.PIPE).stdout
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(target, filter='data')
        for goal in ('test','test-ops','build'):
            subprocess.run(['make',goal,'COMMIT='+commit[:12]],cwd=target,check=True)
        env = dict(os.environ, TELEANTISPAM_BINARY=str(target/'bin/teleantispam'))
        run(['bash','scripts/deploy.sh'],env=env)
        print('DEPLOYED_COMMIT='+commit)
    else:
        raise ValueError('mode must be plan, publish, or deploy')

if __name__ == '__main__':
    main()
