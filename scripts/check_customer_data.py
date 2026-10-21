#!/usr/bin/env python3
"""Redacting repository privacy guard for LotCaster.

Reports only path, line, and finding type. ``--staged`` scans the index;
``--history`` also scans commit messages and every reachable text blob. A clean
result is evidence, not a privacy guarantee: human provenance review and an
independent scanner remain required.
"""
import argparse, base64, json, re, subprocess
from pathlib import Path, PurePosixPath

EMAIL=re.compile(r'(?<![\w.+-])[\w.+-]+@(?:[\w-]+\.)+[A-Za-z]{2,}(?![\w.-])')
PHONE=re.compile(r'(?<![\w])(?:\+?1[-. ]?)?\(?[2-9]\d{2}\)?[-. ]?\d{3}[-. ]?\d{4}(?![\w])')
VIN=re.compile(r'\b[A-HJ-NPR-Z0-9]{17}\b')
SSN=re.compile(r'(?<!\d)\d{3}-\d{2}-\d{4}(?!\d)')
PRIVATE_KEY=re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----')
CRM_ID=re.compile(r'''(?ix)\b(?:lead|task|customer|deal|activity|opportunity|owner|message)(?:[_\s-]*(?:id|in))?["']?\s*[:=#]?\s*["']?(\d{6,12})\b''')
NAME_FIELD=re.compile(r'''(?ix)["']?(?:first_?name|last_?name|customer_?name|buyer_?name|full_?name)["']?\s*[:=]\s*["']([A-Z][A-Za-z'-]+(?:\s+[A-Z][A-Za-z'-]+){0,2})["']''')
GENERIC_NAME_FIELD=re.compile(r'''(?ix)["']?name["']?\s*[:=]\s*["']([A-Z][A-Za-z'-]+(?:\s+[A-Z][A-Za-z'-]+){0,2})["']''')
SENSITIVE_PATH=re.compile(r'(?i)(?:^|/)(?:training|fine[-_]?tune|datasets?|memories|transcripts?|exports?|captures?)(?:/|$)')
OPERATIONAL_FILES={'auth.json','team.json','customers.csv','contacts.csv','transcripts.json','messages.json','leads.csv'}
SYNTHETIC_NAMES={'alex','audit','buyer','casey','customer','example','forbidden','jamie','jordan','manager','original','owner','pat','recent','retry','riley','sales','sam','synthetic','taylor','test'}
PUBLIC_ROLE_EMAILS={'hello@lotcaster.net','leads@lotcaster.net','privacy@lotcaster.net','support@lotcaster.net'}

def run(*args): return subprocess.check_output(args)
def is_fixture(path):
    parts={p.lower() for p in PurePosixPath(path).parts}
    return bool(parts & {'tests','fixtures','__tests__','testdata'}) or 'template' in PurePosixPath(path).stem.lower()
def synthetic_email(value):
    address=value.lower();domain=address.rsplit('@',1)[1]
    role=address.rsplit('@',1)[0]
    return address in PUBLIC_ROLE_EMAILS or (domain in {'lotcaster.com','lotcaster.net'} and role in {'contact','hello','info','leads','legal','noreply','privacy','sales','security','support'}) or domain in {'example.com','example.org','example.net','example.test'} or domain.endswith(('.example','.test'))
def synthetic_phone(value):
    digits=re.sub(r'\D','',value)[-10:]
    return len(digits)==10 and digits[3:6]=='555' and 100<=int(digits[6:])<=199
def synthetic_name(value):
    tokens={x.lower() for x in re.findall(r"[A-Za-z'-]+",value)}
    return bool(tokens) and tokens<=SYNTHETIC_NAMES

def findings(path,content):
    result=[];fixture=is_fixture(path)
    if PurePosixPath(path).name.lower() in OPERATIONAL_FILES: result.append((1,'operational-data-file'))
    if SENSITIVE_PATH.search(path): result.append((1,'training-memory-or-export-path'))
    for number,line in enumerate(content.splitlines(),1):
        if re.search(r'\b(?:sk_live_|sk-proj-|sb_secret_)[A-Za-z0-9_-]{12,}',line): result.append((number,'secret-shaped-value'))
        for token in re.finditer(r'eyJ[A-Za-z0-9_-]+\.([A-Za-z0-9_-]+)\.[A-Za-z0-9_-]+',line):
            try:
                payload=json.loads(base64.urlsafe_b64decode(token[1]+'='*(-len(token[1])%4)))
                if payload.get('role')=='service_role': result.append((number,'privileged-jwt'))
            except (ValueError,UnicodeDecodeError,json.JSONDecodeError): pass
        if PRIVATE_KEY.search(line): result.append((number,'private-key'))
        for match in EMAIL.finditer(line):
            if not synthetic_email(match[0]): result.append((number,'non-approved-email'))
        for match in PHONE.finditer(line):
            raw=match[0]
            context=fixture or bool(re.search(r'(?i)phone|mobile|cell|tel|sms|recipient',line)) or bool(re.search(r'[()+. -]',raw))
            if context and not synthetic_phone(raw): result.append((number,'non-reserved-phone'))
        for match in VIN.finditer(line):
            if not match[0].upper().startswith(('TESTV1N','SYNTH')): result.append((number,'vin-shaped-value'))
        for match in CRM_ID.finditer(line):
            if not match[1].startswith(('98','99')): result.append((number,'non-synthetic-crm-id'))
        if fixture:
            if SSN.search(line): result.append((number,'ssn-shaped-fixture-value'))
            for match in NAME_FIELD.finditer(line):
                if not synthetic_name(match[1]): result.append((number,'non-synthetic-name-field'))
            for match in GENERIC_NAME_FIELD.finditer(line):
                prefix=line[max(0,match.start()-100):match.start()]
                if re.search(r'(?i)customer|buyer|contact|\blead\b',prefix) and not synthetic_name(match[1]):
                    result.append((number,'non-synthetic-name-field'))
    return sorted(set(result))

def text_files(staged):
    command=['git','diff','--cached','--name-only','--diff-filter=ACMR','-z'] if staged else ['git','ls-files','--cached','--others','--exclude-standard','-z']
    for path in sorted(set(run(*command).decode().split('\0'))-{''}):
        raw=run('git','show',':'+path) if staged else Path(path).read_bytes() if Path(path).is_file() and not Path(path).is_symlink() else None
        if raw is None: continue
        try: content=raw.decode('utf-8')
        except UnicodeDecodeError: yield path,None;continue
        yield (path,None) if '\0' in content else (path,content)

def history_findings():
    result=[];commits=blobs=binary=0;seen_blobs=set()
    for commit in run('git','rev-list','--all').decode().splitlines():
        commits+=1;message=run('git','show','-s','--format=%B',commit).decode('utf-8','replace')
        for _,kind in findings('COMMIT_MESSAGE',message): result.append((commit[:12],0,'commit-'+kind))
        for item in run('git','ls-tree','-r','-z',commit).split(b'\0'):
            if not item: continue
            meta,path_bytes=item.split(b'\t',1);path=path_bytes.decode('utf-8','replace');fields=meta.split()
            if fields[1]!=b'blob' or fields[2] in seen_blobs: continue
            seen_blobs.add(fields[2])
            raw=run('git','show',f'{commit}:{path}')
            try: content=raw.decode('utf-8')
            except UnicodeDecodeError: binary+=1;continue
            if '\0' in content: binary+=1;continue
            blobs+=1
            for line,kind in findings(path,content): result.append((commit[:12]+'/'+path,line,kind))
    return sorted(set(result)),commits,blobs,binary

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--staged',action='store_true');parser.add_argument('--history',action='store_true');args=parser.parse_args()
    failures=[];count=binary=0
    for path,content in text_files(args.staged):
        if content is None: binary+=1;continue
        count+=1;failures.extend((path,line,kind) for line,kind in findings(path,content))
    meta=''
    if args.history:
        old,commits,blobs,old_binary=history_findings();failures.extend(old);meta=f' History: {commits} commits, {blobs} text blobs, {old_binary} binary blobs skipped.'
    unique=sorted(set(failures))
    for path,line,kind in unique: print(f'{path}:{line}: {kind} (value withheld)')
    print(f'Privacy guard: {count} current text files checked; {binary} binary files skipped; {len(unique)} findings.{meta}')
    print('Human provenance review and an independent scanner remain required.')
    return bool(unique)
if __name__=='__main__': raise SystemExit(main())
