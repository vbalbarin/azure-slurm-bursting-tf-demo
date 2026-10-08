#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${DEMO_USERNAME:?DEMO_USERNAME is required}"
: "${PARTITION:?PARTITION is required}"
: "${EVIDENCE_DIR:?EVIDENCE_DIR is required}"
mkdir -p "$EVIDENCE_DIR"

job_id="$(sudo -u "$DEMO_USERNAME" sbatch --parsable \
  --partition "$PARTITION" tests/end-to-end/fixtures/burst-job.sh)"
[[ "$job_id" =~ ^[0-9]+$ ]] || { echo "Invalid Slurm job ID: $job_id" >&2; exit 2; }

output_file="/shared/home/$DEMO_USERNAME/burst-$job_id.out"
export JOB_ID="$job_id" OUTPUT_FILE="$output_file"
tests/end-to-end/verify_burst_job.sh | tee "$EVIDENCE_DIR/job-$job_id-validation.log"
sacct -j "$job_id" --json >"$EVIDENCE_DIR/job-$job_id.json"
cp --preserve=mode,timestamps "$output_file" "$EVIDENCE_DIR/"
