#!/usr/bin/env bash
set -euo pipefail
source scripts/load-local-env.sh
ssh -x -o BatchMode=yes -o ConnectTimeout=15 "${TELEANTISPAM_DEPLOY_HOST:?}" python3 - <<'PY'
import json, subprocess, urllib.request, urllib.parse
from pathlib import Path
env = {}
for line in Path('/etc/teleantispam/teleantispam.env').read_text().splitlines():
    if '=' in line and not line.startswith('#'):
        k,v=line.split('=',1); env[k]=v.strip().strip('"').strip("'")
token=env['TELEGRAM_BOT_TOKEN']
def api(method, **args):
    try:
        request=urllib.request.Request('https://api.telegram.org/bot'+token+'/'+method, data=urllib.parse.urlencode(args).encode())
        with urllib.request.urlopen(request,timeout=20) as r: return json.load(r)
    except Exception as e:
        return {'ok':False,'error_type':type(e).__name__}
for username in ['@gophers_id','@gchatf0dea3b4bot']:
    print(json.dumps({'lookup':username,'response':api('getChat',chat_id=username)}))
logs=subprocess.run(['journalctl','-u','teleantispam.service','-n','3000','-o','cat','--no-pager'],capture_output=True,text=True,check=True).stdout
for line in logs.splitlines():
    if any(term in line.casefold() for term in ['olivia','aryan','72783','gchatf0']):
        # Print only moderation account lines, never request URLs.
        if 'https://' not in line and ('user=' in line or '72783' in line): print(line)
data=json.loads(Path('/var/lib/teleantispam/state.json').read_text())
users=(data.get('chats') or {}).get('-1001116539442',{})
recent=[(uid,h) for uid,h in users.items() if any(mid >= 72770 for mid in h.get('recent_message_ids',[]))]
for uid,history in recent:
    response=api('getChatMember',chat_id=-1001116539442,user_id=uid)
    member=response.get('result') or {}
    user=member.get('user') or {}
    if any(s in json.dumps(user).casefold() for s in ['aryan','olivia']) or any(mid in history.get('recent_message_ids',[]) for mid in [72782,72786,72788]):
        print(json.dumps({'recent_member':member,'history':history}))
for a in data.get('moderation_actions',[]):
    if any(term in json.dumps(a).casefold() for term in ['olivia','aryan','72783','gchatf0']): print(json.dumps(a))
PY
python3 - <<'PY'
import concurrent.futures, importlib.util, urllib.request
from pathlib import Path
spec=importlib.util.spec_from_file_location('inspect_message','scripts/inspect-telegram-message.py')
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
def inspect(mid):
    try:
        url=f'https://t.me/gophers_id/{mid}?embed=1&mode=tme'
        with urllib.request.urlopen(url,timeout=20) as r: doc=r.read().decode()
        Path(f'tmp/message-{mid}.html').write_text(doc)
        return {'message_id':mid,'metadata':module.extract_metadata(doc),'text':module.extract_text(doc)}
    except Exception as exc: return {'message_id':mid,'error':type(exc).__name__}
for item in concurrent.futures.ThreadPoolExecutor(max_workers=6).map(inspect,range(72781,72789)):
    print(item)
PY
