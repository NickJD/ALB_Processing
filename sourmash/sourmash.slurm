#!/bin/bash
#SBATCH --job-name=sourmash_sketch
#SBATCH --output=/users/3057556/jobs/ALB/sourmash_ALB_%A_%a.out
#SBATCH --error=/users/3057556/jobs/ALB/sourmash_ALB_%A_%a.err
#SBATCH --partition=k2-bioinf,k2-lowpri
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --time=200:00:00
#SBATCH --mail-user=n.dimonaco@qub.ac.uk
#SBATCH --mail-type=BEGIN,END,FAIL

set -euo pipefail

module load apps/anaconda3/2024.06/bin
source activate  /mnt/scratch2/igfs-anaconda/conda-envs/sourmash_v4.9.4

# Configuration
DATA_DIR="/mnt/scratch2/igfs-databases/AllTheBacteria/0.2"
LIST_FILE="${DATA_DIR}/genomes.list"
OUT_DIR="/mnt/scratch2/users/3057556/DASA/sourmash_sigs"
FILES_PER_TASK="${FILES_PER_TASK:-2000}"

mkdir -p "${OUT_DIR}"
mkdir -p logs

# Validate list file
if [[ ! -f "${LIST_FILE}" ]]; then
  echo "ERROR: LIST_FILE not found: ${LIST_FILE}" >&2
  exit 1
fi

total_genomes=$(wc -l < "${LIST_FILE}")
num_batches=$(( (total_genomes + FILES_PER_TASK - 1) / FILES_PER_TASK ))

echo "Total genomes: ${total_genomes}. Files per task: ${FILES_PER_TASK}. Num batches: ${num_batches}."

# Auto-submit as array if not already in one
if [[ -z "${SLURM_ARRAY_TASK_ID:-}" ]]; then
  echo "Submitting array job: 1-${num_batches}"
  sbatch --array=1-${num_batches}%200 --export=ALL "${BASH_SOURCE[0]}"
  exit 0
fi

# Calculate which genomes this task should process
start_line=$(( (SLURM_ARRAY_TASK_ID - 1) * FILES_PER_TASK + 1 ))
end_line=$(( SLURM_ARRAY_TASK_ID * FILES_PER_TASK ))

# Output signature file for this batch
batch_sig="${OUT_DIR}/batch_$(printf "%05d" ${SLURM_ARRAY_TASK_ID}).sig"

# Skip if batch already completed
if [[ -f "${batch_sig}" ]]; then
  echo "SKIP: Batch ${SLURM_ARRAY_TASK_ID} already complete (${batch_sig} exists)"
  exit 0
fi

echo "Task ${SLURM_ARRAY_TASK_ID}: Processing lines ${start_line}-${end_line}"
echo "Output: ${batch_sig}"

# Read assigned genomes
mapfile -t genomes < <(sed -n "${start_line},${end_line}p" "${LIST_FILE}")

if [[ ${#genomes[@]} -eq 0 ]]; then
  echo "No genomes assigned to this task. Exiting."
  exit 0
fi

# Create temporary signature file
tmp_sig="${batch_sig}.tmp"
rm -f "${tmp_sig}"

# Process each genome and append to batch signature
success_count=0
fail_count=0

for genome_path in "${genomes[@]}"; do
  # Skip empty lines
  [[ -z "${genome_path}" ]] && continue

  # Handle relative paths
  if [[ ! -f "${genome_path}" ]]; then
    if [[ -f "${DATA_DIR}/${genome_path}" ]]; then
      genome_path="${DATA_DIR}/${genome_path}"
    else
      echo "WARNING: File not found: ${genome_path}" >&2
      ((fail_count++))
      continue
    fi
  fi

  echo "Processing: ${genome_path}"

  # Sketch and append to batch file
  if sourmash sketch dna \
       -p k=21,k=31,k=51,scaled=1000,abund \
       --name-from-first \
       "${genome_path}" \
       -o - 2>/dev/null >> "${tmp_sig}"; then
    ((success_count++))
  else
    echo "FAILED: ${genome_path}" >&2
    ((fail_count++))
  fi
done

# Move temp to final if we got any successes
if [[ ${success_count} -gt 0 ]]; then
  mv "${tmp_sig}" "${batch_sig}"
  echo "Task ${SLURM_ARRAY_TASK_ID} complete: ${success_count} success, ${fail_count} failed"
  echo "Batch signature: ${batch_sig}"
else
  echo "Task ${SLURM_ARRAY_TASK_ID} failed: No genomes successfully sketched"
  rm -f "${tmp_sig}"
  exit 1
fi
