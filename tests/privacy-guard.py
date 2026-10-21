"""Offline synthetic positive/negative checks; never contacts any address."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
spec=importlib.util.spec_from_file_location('guard',Path(__file__).resolve().parents[1]/'scripts/check_customer_data.py')
g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
assert not g.findings('tests/fixture.json','buyer@example.com +16155550123')
assert g.findings('tests/fixture.json','buyer@'+'unapproved.invalid')
assert g.findings('tests/fixture.json','+1615'+'5550200')
assert g.findings('tests/fixture.json','615'+'-555-0200')
assert g.findings('data/auth.json','{}')
assert g.findings('src/key.txt','-----BEGIN '+'PRIVATE KEY-----')
assert not g.findings('tests/example.mjs','20261019172324')
assert not g.findings('src/contact.html','support@'+'lotcaster.net')
assert g.findings('src/contact.html','person@'+'private.invalid')
assert g.findings('tests/fixture.json','{"vin":"1HGCM82633'+'A004352"}')
assert g.findings('tests/fixture.json','{"lead_id":"1234'+'5678"}')
assert g.findings('tests/fixture.json','{"last_name":"'+('anderson'.title())+'"}')
assert g.findings('training/examples.json','{}')
# Prove pre-commit checks staged bytes even when working bytes have been cleaned.
with tempfile.TemporaryDirectory() as temp:
    subprocess.run(['git','init','-q',temp],check=True)
    p=Path(temp)/'tests/fixture.txt';p.parent.mkdir();p.write_text('buyer@'+'unapproved.invalid')
    subprocess.run(['git','-C',temp,'add','.'],check=True)
    p.write_text('buyer@example.com')
    run=subprocess.run(['python3',str(Path(g.__file__).resolve()),'--staged'],cwd=temp,capture_output=True,text=True)
    assert run.returncode==1
    assert 'unapproved.invalid' not in run.stdout
    assert 'non-approved-email' in run.stdout
    subprocess.run(['git','-C',temp,'config','user.email','audit@example.com'],check=True)
    subprocess.run(['git','-C',temp,'config','user.name','Synthetic Audit'],check=True)
    subprocess.run(['git','-C',temp,'commit','-qm','baseline contains person@'+'private.invalid'],check=True)
    p.write_text('buyer@example.com')
    subprocess.run(['git','-C',temp,'add','.'],check=True)
    subprocess.run(['git','-C',temp,'commit','-qm','sanitize fixture'],check=True)
    history=subprocess.run(['python3',str(Path(g.__file__).resolve()),'--history'],cwd=temp,capture_output=True,text=True)
    assert history.returncode==1
    assert 'private.invalid' not in history.stdout
    assert 'commit-non-approved-email' in history.stdout
print('PASS: 15 privacy-guard checks including staged/history scanning and redacted output')
