import urllib.request

u = 'https://patch-diff.githubusercontent.com/raw/corrinehu/dsh-workbuddy-connect/pull/204.patch'
req = urllib.request.Request(u, headers={'User-Agent': 'Mozilla/5.0'})
data = urllib.request.urlopen(req, timeout=30).read().decode('utf-8', 'replace')

# print only the src/upstream.ts hunk
start = data.find('diff --git a/src/upstream.ts')
end = data.find('diff --git a/tests/', start)
print(data[start:end])
