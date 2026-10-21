import io, os, shutil, subprocess, tempfile

target = r'C:\Users\Hourz26\.dsh\profiles\desktop\node_modules\dsh-workbuddy-connect\lib\host-heartbeat-SJaZ33tR.js'
tmpdir = tempfile.mkdtemp(prefix='wbcheck-')

# 1) syntax check: copy to .mjs and node --check
copy = os.path.join(tmpdir, 'bundle.mjs')
shutil.copy2(target, copy)
r = subprocess.run(['node', '--check', copy], capture_output=True, text=True)
print('node --check rc=', r.returncode)
print(r.stdout.strip(), r.stderr.strip())

# 2) behavioral test: slice the helper block out of the patched file
src = io.open(target, 'r', encoding='utf-8').read()
start = src.index('/**\n * Neutralize the Harness identity sentence')
end = src.index('/** Rewrite `role: "developer"` messages', start)
helpers = src[start:end]

test = helpers + r'''
function run(name, body, check) {
  const before = JSON.stringify(body);
  neutralizeChannelIdentity(body);
  const ok = check(body);
  console.log((ok ? 'PASS ' : 'FAIL ') + name);
  if (!ok) { console.log('  before:', before.slice(0, 200)); console.log('  after :', JSON.stringify(body).slice(0, 200)); }
}

const ID = 'You are an AI agent powered by DeepSeek Harness.';
const arr = [];
const push = (b) => arr.push(b);

// 1 system string opening with identity -> rewritten
push({ messages: [{ role: 'system', content: ID + '\n\nYou are helpful.' }, { role: 'user', content: 'hi' }] });
// 2 identity after prose -> untouched
push({ messages: [{ role: 'system', content: 'Intro.\n' + ID }] });
// 3 user message with identity -> untouched
push({ messages: [{ role: 'user', content: ID }] });
// 4 array content text part -> rewritten
push({ messages: [{ role: 'system', content: [{ type: 'text', text: ID + ' rest' }] }] });
// 5 developer role -> rewritten
push({ messages: [{ role: 'developer', content: ID + ' x' }] });
// 6 no identity -> untouched
push({ messages: [{ role: 'system', content: 'You are a helpful assistant.' }] });

run('system opener rewritten', arr[0], b => b.messages[0].content.startsWith('You are an AI agent.'));
run('prose-prefixed untouched', arr[1], b => b.messages[0].content === 'Intro.\n' + ID);
run('user msg untouched', arr[2], b => b.messages[0].content === ID);
run('array form rewritten', arr[3], b => b.messages[0].content[0].text.startsWith('You are an AI agent.'));
run('developer rewritten', arr[4], b => b.messages[0].content.startsWith('You are an AI agent.'));
run('neutral untouched', arr[5], b => b.messages[0].content === 'You are a helpful assistant.');
'''
p = os.path.join(tmpdir, 'test.mjs')
io.open(p, 'w', encoding='utf-8').write(test)
r2 = subprocess.run(['node', p], capture_output=True, text=True)
print(r2.stdout.strip())
if r2.returncode != 0:
    print('STDERR:', r2.stderr.strip())
print('tmp:', tmpdir)
