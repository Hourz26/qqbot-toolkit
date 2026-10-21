import json, urllib.request, sys

def get(url):
    req = urllib.request.Request(url, headers={
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'application/vnd.github+json',
    })
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.loads(r.read().decode('utf-8'))

base = 'https://api.github.com/repos/corrinehu/dsh-workbuddy-connect'
try:
    issues = get(base + '/issues?state=all&sort=updated&direction=desc&per_page=12')
except Exception as e:
    print('ERR', e)
    sys.exit(1)

print('count', len(issues))
for it in issues:
    print('---')
    print('#%s [%s] %s' % (it['number'], it['state'], it['title']))
    print('updated', it['updated_at'], 'comments', it['comments'])
    body = (it.get('body') or '').replace('\r', '')
    print('body:', body[:300].replace('\n', ' | '))
