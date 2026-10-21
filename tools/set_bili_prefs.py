import io, json, os, re, shutil

cfg_path = r'C:\Users\Hourz26\.dsh\bili-duty\config.json'
patch_path = r'C:\Users\Hourz26\.dsh\profiles\desktop\cordis.patch.yml'

KEYWORDS = ['数码', '搞笑', '抽象', '科技', '游戏', 'acg']
WORKSPACE = r'C:\Users\Hourz26\.dsh'

# ---------- 1) config.json ----------
cfg = json.load(io.open(cfg_path, 'r', encoding='utf-8'))
print('before: keywords=%r workspace=%r' % (cfg.get('keywords'), cfg.get('workspace')))
if not os.path.exists(cfg_path + '.bak-before-prefs'):
    shutil.copy2(cfg_path, cfg_path + '.bak-before-prefs')
cfg['keywords'] = KEYWORDS
cfg['workspace'] = WORKSPACE
io.open(cfg_path, 'w', encoding='utf-8', newline='\n').write(
    json.dumps(cfg, ensure_ascii=False, indent=2) + '\n')
print('after : keywords=%r workspace=%r' % (cfg.get('keywords'), cfg.get('workspace')))

# ---------- 2) strip the config block under bili-scroll in cordis.patch.yml ----------
text = io.open(patch_path, 'r', encoding='utf-8').read()
if not os.path.exists(patch_path + '.bak-before-biliprefs'):
    shutil.copy2(patch_path, patch_path + '.bak-before-biliprefs')

lines = text.split('\n')
out = []
i = 0
removed = 0
while i < len(lines):
    line = lines[i]
    if line.strip() == '- id: bili-scroll':
        out.append(line)
        i += 1
        # keep the following 'name:' line
        if i < len(lines) and lines[i].strip().startswith('name:'):
            out.append(lines[i])
            i += 1
        # drop a 'config:' block belonging to this entry
        if i < len(lines) and lines[i].strip() == 'config:':
            base_indent = len(lines[i]) - len(lines[i].lstrip())
            i += 1
            while i < len(lines):
                cur = lines[i]
                if cur.strip() == '':
                    removed += 1
                    i += 1
                    continue
                cur_indent = len(cur) - len(cur.lstrip())
                if cur_indent > base_indent:
                    removed += 1
                    i += 1
                    continue
                break
        continue
    out.append(line)
    i += 1

new_text = '\n'.join(out)
io.open(patch_path, 'w', encoding='utf-8', newline='\n').write(new_text)
print('patch: removed %d config lines' % removed)

# ---------- 3) show the resulting entry ----------
show = new_text.split('\n')
for n, l in enumerate(show):
    if l.strip() == '- id: bili-scroll':
        print('--- entry ---')
        for k in range(n, min(n + 4, len(show))):
            print('  %r' % show[k])
        break
