import concurrent.futures
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
repo = root / "source"
sys.path.insert(0, str(repo / "tb_rtl"))
from pvm_run import judge, parse

evidence = root / "runs"
evidence.mkdir()
reg = json.loads((repo / "tb_rtl/pvm_jobs.json").read_text())
jobs = [job for job in reg["jobs"] if not job.get("negative") and "trace_of" not in job]
assert len(jobs) == 25
version = subprocess.check_output(["verilator", "--version"], text=True).strip()
sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
print(sha, version, flush=True)

def run_job(job):
    name = job["id"]
    output = evidence / name
    output.mkdir()
    build = output / "obj"
    argv = [
        "verilator", "--binary", "--timing", "--language", "1364-2005",
        "--x-assign", "unique", "--x-initial", "unique",
        "-Wno-fatal", "-CFLAGS", "-O0", "-j", "1", "--top-module", job["top"],
        "--Mdir", str(build), "-o", "sim",
        *("-D" + flag for flag in job.get("defines", [])),
        *("-I" + path for path in job.get("include_dirs", [])),
        *job["sources"],
    ]
    results = []
    try:
        with (output / "build.log").open("w") as stream:
            stream.write(shlex.join(argv) + "\n")
            stream.flush()
            compiled = subprocess.run(argv, cwd=repo, stdout=stream, stderr=subprocess.STDOUT, timeout=900)
        if compiled.returncode:
            return name, [{"seed": seed, "verdict": "COMPILE_FAIL"} for seed in (1, 2)]
        for seed in (1, 2):
            args = [str(build / "sim"), "+verilator+rand+reset+2", f"+verilator+seed+{seed}"]
            with (output / f"seed-{seed}.log").open("w") as log:
                log.write(shlex.join(args) + "\n")
                log.flush()
                try:
                    result = subprocess.run(args, cwd=output, stdout=log, stderr=subprocess.STDOUT,
                                            timeout=job.get("sim_timeout", 600))
                except subprocess.TimeoutExpired:
                    results.append({"seed": seed, "verdict": "TIMEOUT"})
                    continue
            parsed = parse((output / f"seed-{seed}.log").read_text(errors="replace"))
            verdict = judge(job, parsed) if result.returncode == 0 else "SIM_ERROR"
            results.append({"seed": seed, "verdict": verdict, **parsed})
        return name, results
    except subprocess.TimeoutExpired:
        return name, [{"seed": seed, "verdict": "COMPILE_TIMEOUT"} for seed in (1, 2)]
    finally:
        # Only keep the commands and raw logs. Generated objects take several GB.
        if build.exists():
            shutil.rmtree(build)

results = {}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    futures = [pool.submit(run_job, job) for job in jobs]
    for f in concurrent.futures.as_completed(futures):
        name, seeds = f.result()
        results[name] = seeds
        print(name, " ".join(f"{r['seed']}:{r['verdict']}" for r in seeds), flush=True)

(root / "results.json").write_text(json.dumps({"sha": sha, "version": version, "results": results}, indent=2) + "\n")
passed = sum(entry["verdict"] == "PASS_FRESH" for job in results.values() for entry in job)
print(f"SUMMARY {passed}/{len(jobs) * 2} seeded checks passed", flush=True)
sys.exit(passed != len(jobs) * 2)
