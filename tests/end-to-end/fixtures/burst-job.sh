#!/usr/bin/env bash
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --output=/shared/home/%u/burst-%j.out
set -euo pipefail

region="$(curl --fail --silent --show-error --noproxy '*' \
  -H Metadata:true \
  'http://169.254.169.254/metadata/instance/compute/location?api-version=2025-04-07&format=text')"
printf 'job_id=%s\nexecution_node=%s\nexecution_region=%s\n' \
  "${SLURM_JOB_ID:?}" "$(hostname --fqdn)" "$region"
