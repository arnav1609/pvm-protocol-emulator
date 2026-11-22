"""Aggregate only accepted, source-matched shard jobs and recheck every successful raw log."""
import argparse
import hashlib
import json
from pathlib import Path
from seed_campaign import ROOT,judge_seed,judge_range_ledger,judge_ledger,seed_delays

def assemble(shards,expected):
    if len(shards)!=10:raise ValueError('missing shard')
    rows=[]
    for i,s in enumerate(shards):
        if s['tool']!='Vivado/XSim 2024.1' or s['sources']!=expected:raise ValueError('tool/source mismatch')
        if s['first_seed']!=i*100 or s['seed_count']!=100:raise ValueError('wrong shard range')
        judge_range_ledger(s['seeds'],i*100,100)
        if any(r.get('exit_code')!=0 for r in s['seeds']):raise ValueError('unsuccessful tool exit')
        if any(r.get('sv_seed')!=r['seed']+1 for r in s['seeds']):raise ValueError('wrong simulator seed mapping')
        rows+=s['seeds']
    judge_ledger(rows)
    if len({r['grant_delay'] for r in rows})<2 or len({r['response_delay'] for r in rows})<2:
        raise ValueError('random delay stream did not vary')
    return rows

def check_log(origin,row):
    p=(origin/row['log']).resolve()
    if not p.is_relative_to(origin.resolve()):raise ValueError('log escapes shard')
    raw=p.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=row['sha256']:raise ValueError('raw log hash mismatch')
    judge_seed(raw.decode(errors='replace'),row['seed'])
    if (row['grant_delay'],row['response_delay'])!=seed_delays(raw.decode(errors='replace'),row['seed']):raise ValueError('delay metadata mismatch')
    return p

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve()
    expected={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in
              ['rtl/riscv/picorv32_adapter.sv','sim_riscv/tb_random_latency.sv','scripts/seed_campaign.py','scripts/run_seed_shard.py']}
    shards=[];provenance=[]
    for i in range(10):
        jid=f'i24_seed_shard_{i:02d}';rec=json.loads((out.parent/jid/'result.json').read_text())
        if rec['state'] not in ('PASS_FRESH','PASS_REUSED'):raise ValueError('unaccepted shard '+jid)
        origin=out.parent.parent/rec['fresh_run']/jid
        s=json.loads((origin/'seed_results.json').read_text())
        for row in s['seeds']:check_log(origin,row)
        shards.append(s);provenance.append(dict(job=jid,source_run=rec['fresh_run'],state=rec['state']))
    rows=assemble(shards,expected)
    (out/'seed_results.json').write_text(json.dumps(dict(tool='Vivado/XSim 2024.1',sources=expected,seeds=rows,shards=provenance),indent=2)+'\n')
    print('SEED_CAMPAIGN: PASS seeds=1000 independent_processes=1000 checks_per_seed=2')

if __name__=='__main__':main()
