#!/usr/bin/env bash
set -euo pipefail
source scripts/load-local-env.sh
ssh -x -o BatchMode=yes -o ConnectTimeout=15 "${TELEANTISPAM_DEPLOY_HOST:?}" python3 - "${1:?plan or apply}" <<'PY'
import json, sys, urllib.request, urllib.parse, urllib.error
from pathlib import Path
mode=sys.argv[1]
env={}
for line in Path('/etc/teleantispam/teleantispam.env').read_text().splitlines():
    if '=' in line and not line.startswith('#'):
        k,v=line.split('=',1); env[k]=v.strip().strip('"').strip("'")
token=env['TELEGRAM_BOT_TOKEN']
def api(method, **args):
    req=urllib.request.Request('https://api.telegram.org/bot'+token+'/'+method,data=urllib.parse.urlencode(args).encode())
    try:
        with urllib.request.urlopen(req,timeout=20) as r: result=json.load(r)
    except urllib.error.HTTPError as exc:
        result=json.loads(exc.read())
    except Exception as exc:
        raise RuntimeError('Telegram request failed: '+type(exc).__name__) from None
    return result
def required(method, **args):
    result=api(method,**args)
    if not result.get('ok'): raise RuntimeError(json.dumps(result))
    return result['result']
chat=required('getChat',chat_id='@gophers_id')
user=required('getChat',chat_id='@gchatf0dea3b4bot')
assert chat['id']==-1001116539442 and user['id']==8151342514
self=required('getMe')
permissions=required('getChatMember',chat_id=chat['id'],user_id=self['id'])
assert permissions['status']=='administrator' and permissions.get('can_delete_messages') and permissions.get('can_restrict_members')
member=required('getChatMember',chat_id=chat['id'],user_id=user['id'])
assert member['status'] not in ('administrator','creator')
aryan=required('getChatMember',chat_id=chat['id'],user_id=7842537651)
assert aryan['status'] not in ('administrator','creator')
assert aryan['user']['first_name']=='Aryan' and aryan['user'].get('last_name')=='Yadav'
state=json.loads(Path('/var/lib/teleantispam/state.json').read_text())
history=state['chats'][str(chat['id'])]['7842537651']
assert all(mid in history['recent_message_ids'] for mid in [72782,72786]), 'Aryan ownership evidence changed'
target={'chat_id':chat['id'],'username':user['username'],'user_id':user['id'],'name':user['first_name'],'additional_ban_user_id':7842537651,'additional_ban_name':'Aryan Yadav','owned_preceding_message_ids':[72782,72786],'delete_message_ids':[72783,72785,72787],'ban':True,'revoke_messages':True}
plan=Path('/var/lib/teleantispam/reported-spam-72783-plan.json')
receipt=Path('/var/lib/teleantispam/reported-spam-72783-result.json')
if mode=='plan':
    value={'target':target,'effects':['delete exact listed spam posts','ban verified Olivia bot and Aryan Yadav, revoking both accounts group messages'],'rollback':'Bans can be reversed by unban; deleted messages cannot be restored.'}
    plan.write_text(json.dumps(value,indent=2)+'\n')
    print(json.dumps(value,indent=2))
elif mode=='apply':
    assert json.loads(plan.read_text())['target']==target, 'reviewed plan changed'
    results=[]
    for mid in target['delete_message_ids']:
        results.append({'delete_message_id':mid,'response':api('deleteMessage',chat_id=chat['id'],message_id=mid)})
    results.append({'ban_user_id':user['id'],'response':api('banChatMember',chat_id=chat['id'],user_id=user['id'],revoke_messages='true')})
    results.append({'ban_user_id':7842537651,'response':api('banChatMember',chat_id=chat['id'],user_id=7842537651,revoke_messages='true')})
    after=required('getChatMember',chat_id=chat['id'],user_id=user['id'])
    aryan_after=required('getChatMember',chat_id=chat['id'],user_id=7842537651)
    value={'target':target,'results':results,'verified_member_status':after['status'],'verified_aryan_status':aryan_after['status']}
    receipt.write_text(json.dumps(value,indent=2)+'\n')
    print(json.dumps(value,indent=2))
    assert after['status']=='kicked', 'ban verification failed'
    assert aryan_after['status']=='kicked', 'Aryan ban verification failed'
    assert all(r['response'].get('ok') for r in results), 'one or more operations failed; inspect receipt'
else: raise ValueError('expected plan or apply')
PY
