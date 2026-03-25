#!/bin/bash
#SBATCH --job-name=sourmash_sketch
#SBATCH --output=/users/3057556/jobs/ALB/sourmash_ALB_%A_%a.out
#SBATCH --error=/users/3057556/jobs/ALB/sourmash_ALB_%A_%a.err
#SBATCH --array=1-930%200
#SBATCH --partition=k2-bioinf,k2-lowpri,k2-medpri
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --mail-user=n.dimonaco@qub.ac.uk
#SBATCH --mail-type=BEGIN,END,FAIL

set -euo pipefail

module load apps/anaconda3/2024.06/bin
source activate /mnt/scratch2/igfs-anaconda/conda-envs/sourmash_v4.9.4

# Configuration
OUT_DIR="/mnt/scratch2/users/3057556/DASA/sourmash/sourmash_sigs"
BATCH_DIR="/mnt/scratch2/users/3057556/DASA/sourmash/sourmash_batchfiles"

# List file and output file for this specific array task
batch_list="${BATCH_DIR}/batch_$(printf "%05d" ${SLURM_ARRAY_TASK_ID}).list"
batch_sig="${BATCH_DIR}/$(printf "%05d" ${SLURM_ARRAY_TASK_ID}).sig"

# Verify list file exists
if [[ ! -f "${batch_list}" ]]; then
  echo "ERROR: Batch list file not found: ${batch_list}"
  exit 1
fi

# Skip if already completed
if [[ -f "${batch_sig}" ]]; then
  sig_count=$(sourmash sig describe "${batch_sig}" 2>/dev/null | wc -l || echo "0")
  if [[ ${sig_count} -gt 0 ]]; then
    echo "SKIP: Batch ${SLURM_ARRAY_TASK_ID} already complete (${sig_count} signatures)"
    exit 0
  fi
fi

# Count genomes in this batch
genome_count=$(wc -l < "${batch_list}")
echo "Task ${SLURM_ARRAY_TASK_ID}: Processing ${genome_count} genomes"
echo "Input: ${batch_list}"
echo "Output: ${batch_sig}"

# Sketch all genomes in this batch
echo "Starting sketch at $(date)"

if sourmash sketch dna \
     -p k=21,k=31,k=51,scaled=1000,abund \
     --name-from-first \
     --from-file "${batch_list}" \
     -o "${batch_sig}"; then
  
  # Verify output
  sig_count=$(sourmash sig describe "${batch_sig}" 2>/dev/null | wc -l || echo "0")
  
  echo "Completed at $(date)"
  echo "Created ${sig_count} signatures from ${genome_count} input genomes"
  
  if [[ ${sig_count} -eq 0 ]]; then
    echo "ERROR: No signatures were created!"
    exit 1
  fi
  
  if [[ ${sig_count} -ne ${genome_count} ]]; then
    echo "WARNING: Signature count (${sig_count}) != input count (${genome_count})"
  fi
  
  echo "SUCCESS"
  
else
  echo "ERROR: sourmash sketch failed"
  rm -f "${batch_sig}"
  exit 1
fi
