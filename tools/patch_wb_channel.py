import io, re, sys, os, shutil

target = r'C:\Users\Hourz26\.dsh\profiles\desktop\node_modules\dsh-workbuddy-connect\lib\host-heartbeat-SJaZ33tR.js'
bak = target + '.bak-before-channel-fix'

src = io.open(target, 'r', encoding='utf-8', newline='').read()

if 'neutralizeChannelIdentity' in src:
    print('ALREADY PATCHED')
    sys.exit(0)

if not os.path.exists(bak):
    shutil.copy2(target, bak)
    print('backup ->', bak)

HELPERS = r'''
/**
 * Neutralize the Harness identity sentence the CN gateway's channel check
 * rejects at the start of a system/developer message (upstream code 11128,
 * displayMsg.zh "请求被拦截，请重新发送"). Backport of PR #204.
 */
const CHANNEL_IDENTITY_PATTERN = /^[\s\uFEFF]*You are an?(?: AI)?(?: coding)? agent powered by [^.\n]{1,60}Harness\.?/iu;
const NEUTRAL_IDENTITY = "You are an AI agent.";
function rewriteChannelIdentityLine(text) {
	return text.replace(CHANNEL_IDENTITY_PATTERN, NEUTRAL_IDENTITY);
}
function neutralizeChannelIdentity(obj) {
	const messages = obj["messages"];
	if (!Array.isArray(messages)) return;
	for (const message of messages) {
		if (typeof message !== "object" || message === null || Array.isArray(message)) continue;
		const role = message["role"];
		if (role !== "system" && role !== "developer") continue;
		const content = message["content"];
		if (typeof content === "string") {
			message["content"] = rewriteChannelIdentityLine(content);
			continue;
		}
		if (!Array.isArray(content)) continue;
		for (const part of content) {
			if (typeof part !== "object" || part === null || Array.isArray(part)) continue;
			if (part["type"] !== "text" || typeof part["text"] !== "string") continue;
			part["text"] = rewriteChannelIdentityLine(part["text"]);
		}
	}
}
'''

anchor = '/** Rewrite `role: "developer"` messages to `role: "system"` (upstream rejects developer). */'
if anchor not in src:
    print('ANCHOR MISSING')
    sys.exit(1)
src = src.replace(anchor, HELPERS.strip('\n') + '\n' + anchor, 1)

a1 = '\tnormalizeDeveloperRole(obj);\n'
if a1 not in src:
    print('CALL SITE 1 MISSING')
    sys.exit(1)
src = src.replace(a1, a1 + '\tneutralizeChannelIdentity(obj);\n', 1)

a2 = '\tdropUnsupportedEffort(body);\n'
if a2 not in src:
    print('CALL SITE 2 MISSING')
    sys.exit(1)
src = src.replace(a2, a2 + '\tneutralizeChannelIdentity(body);\n', 1)

io.open(target, 'w', encoding='utf-8', newline='').write(src)
print('PATCHED, size', len(src.encode('utf-8')))
print('occurrences:', src.count('neutralizeChannelIdentity'))
