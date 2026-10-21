import urllib.request, sys

urls = [
    'https://patch-diff.githubusercontent.com/raw/corrinehu/dsh-workbuddy-connect/pull/202.patch',
    'https://patch-diff.githubusercontent.com/raw/corrinehu/dsh-workbuddy-connect/pull/204.patch',
]
for u in urls:
    print('=' * 20, u)
    try:
        req = urllib.request.Request(u, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = r.read().decode('utf-8', 'replace')
        print('len', len(data))
        print(data[:6000])
    except Exception as e:
        print('ERR', e)
