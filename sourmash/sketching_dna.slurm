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
source activate /mnt/scratch2/igfs-anaconda/conda-envs/sourmash_v4.9.4

# Configuration
DATA_DIR="/mnt/scratch2/igfs-databases/AllTheBacteria/0.2"
LIST_FILE="${DATA_DIR}/genomes.list"
OUT_DIR="/mnt/scratch2/users/3057556/DASA/sourmash_sigs"
FILES_PER_TASK="${FILES_PER_TASK:-2000}"

mkdir -p "${OUT_DIR}"
mkdir -p /users/3057556/jobs/ALB

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
  # Verify the file is valid and not empty
  sig_count=$(sourmash sig describe "${batch_sig}" 2>/dev/null | wc -l || echo "0")
  if [[ ${sig_count} -gt 0 ]]; then
    echo "SKIP: Batch ${SLURM_ARRAY_TASK_ID} already complete (${batch_sig} exists with ${sig_count} signatures)"
    exit 0
  else
    echo "WARNING: ${batch_sig} exists but appears invalid, recreating..."
    rm -f "${batch_sig}"
  fi
fi

echo "Task ${SLURM_ARRAY_TASK_ID}: Processing lines ${start_line}-${end_line}"
echo "Output: ${batch_sig}"

# Read assigned genomes
mapfile -t genomes < <(sed -n "${start_line},${end_line}p" "${LIST_FILE}")

if [[ ${#genomes[@]} -eq 0 ]]; then
  echo "No genomes assigned to this task. Exiting."
  exit 0
fi

# Create list of genome files for this batch
batch_list="${OUT_DIR}/batch_$(printf "%05d" ${SLURM_ARRAY_TASK_ID}).list"
rm -f "${batch_list}"

# Verify all genome files exist and create clean list
verified_count=0
for genome_path in "${genomes[@]}"; do
  # Skip empty lines
  [[ -z "${genome_path}" ]] && continue

  # Handle relative paths
  full_path="${genome_path}"
  if [[ ! -f "${full_path}" ]]; then
    if [[ -f "${DATA_DIR}/${genome_path}" ]]; then
      full_path="${DATA_DIR}/${genome_path}"
    else
      echo "WARNING: File not found, skipping: ${genome_path}" >&2
      continue
    fi
  fi

  # Verify file is readable
  if [[ -r "${full_path}" ]]; then
    echo "${full_path}" >> "${batch_list}"
    ((verified_count++))
  else
    echo "WARNING: File not readable, skipping: ${full_path}" >&2
  fi
done

if [[ ${verified_count} -eq 0 ]]; then
  echo "ERROR: No valid genome files found for this task"
  rm -f "${batch_list}"
  exit 1
fi

echo "Verified ${verified_count} genome files for processing"
echo "First few genomes:"
head -5 "${batch_list}"

# Sketch all genomes in this batch in ONE sourmash call
# This is the correct way - do NOT sketch one at a time and append
echo "Sketching ${verified_count} genomes..."

if sourmash sketch dna \
     -p k=21,k=31,k=51,scaled=1000,abund \
     --name-from-first \
     --from-file "${batch_list}" \
     -o "${batch_sig}"; then

  # Verify output
  sig_count=$(sourmash sig describe "${batch_sig}" 2>/dev/null | wc -l || echo "0")

  echo "Task ${SLURM_ARRAY_TASK_ID} complete: ${sig_count} signatures created from ${verified_count} input files"

  if [[ ${sig_count} -eq 0 ]]; then
    echo "ERROR: No signatures were created!" >&2
    echo "Check the batch list file: ${batch_list}"
    exit 1
  fi

  # Warn if signature count doesn't match input count
  if [[ ${sig_count} -ne ${verified_count} ]]; then
    echo "WARNING: Created ${sig_count} signatures but expected ${verified_count}"
    echo "Some genomes may have failed to sketch"
  fi

  # Clean up temp list only if successful
  rm -f "${batch_list}"

else
  echo "ERROR: sourmash sketch failed for batch ${SLURM_ARRAY_TASK_ID}" >&2
  echo "Batch list preserved at: ${batch_list}"
  rm -f "${batch_sig}"
  exit 1
fi

echo "Batch signature: ${batch_sig}"
echo "SUCCESS"