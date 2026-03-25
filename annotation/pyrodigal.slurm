#!/bin/bash
#SBATCH --job-name=pyrodigal_annotate
#SBATCH --output=/users/3057556/jobs/ALB/pyrodigal_%A_%a.out
#SBATCH --error=/users/3057556/jobs/ALB/pyrodigal_%A_%a.err
#SBATCH --array=0-930%200
#SBATCH --partition=k2-bioinf,k2-lowpri,k2-medpri
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=24:00:00
#SBATCH --mail-user=n.dimonaco@qub.ac.uk
#SBATCH --mail-type=BEGIN,END,FAIL

set -euo pipefail

module load apps/anaconda3/2024.06/bin
source activate /mnt/scratch2/igfs-anaconda/conda-envs/pyrodigal_3.6.3

# Configuration
BATCH_DIR="/mnt/scratch2/users/3057556/DASA/pyrodigal_output/pyrodigal_batchfiles"
OUT_BASE="/mnt/scratch2/users/3057556/DASA/pyrodigal_output"
PYTHON_SCRIPT="/mnt/scratch2/users/3057556/DASA/pyrodigal_output/run_pyrodigal.py"

# Output directories
GFF_DIR="${OUT_BASE}/GFF"
DNA_DIR="${OUT_BASE}/DNA_FASTA"
AA_DIR="${OUT_BASE}/AA_FASTA"
LOG_DIR="${OUT_BASE}/logs"

mkdir -p "${GFF_DIR}" "${DNA_DIR}" "${AA_DIR}" "${LOG_DIR}"

# Batch file for this task
batch_list="${BATCH_DIR}/batch_$(printf "%05d" ${SLURM_ARRAY_TASK_ID}).list"

if [[ ! -f "${batch_list}" ]]; then
  echo "ERROR: Batch file not found: ${batch_list}"
  exit 1
fi

genome_count=$(wc -l < "${batch_list}")

echo "=========================================="
echo "Task ${SLURM_ARRAY_TASK_ID} started at $(date)"
echo "Processing ${genome_count} genomes from ${batch_list}"
echo "Python script: ${PYTHON_SCRIPT}"
echo "=========================================="
echo ""

# Counters
success_count=0
fail_count=0
skip_count=0

# Process each genome
while IFS= read -r genome_path; do
  # Skip empty lines
  [[ -z "${genome_path}" ]] && continue

  # Extract genome ID
  genome_id=$(basename "${genome_path}" .fa.gz)

  # Output files
  gff_out="${GFF_DIR}/${genome_id}.gff"
  dna_out="${DNA_DIR}/${genome_id}_genes.fna"
  aa_out="${AA_DIR}/${genome_id}_proteins.faa"

  # Skip if already done
  if [[ -f "${gff_out}" ]] && [[ -f "${dna_out}" ]] && [[ -f "${aa_out}" ]]; then
    ((skip_count++))
    continue
  fi

  # Check input exists
  if [[ ! -f "${genome_path}" ]]; then
    echo "WARNING: Not found: ${genome_path}" >&2
    ((fail_count++))
    continue
  fi

  # Run Python script
  if python3 "${PYTHON_SCRIPT}" "${genome_path}" "${gff_out}" "${dna_out}" "${aa_out}" 2>&1; then
    ((success_count++))
    if (( success_count % 100 == 0 )); then
      echo "Progress: ${success_count} genomes annotated"
    fi
  else
    ((fail_count++))
    # Clean up partial outputs
    rm -f "${gff_out}" "${dna_out}" "${aa_out}"
  fi

done < "${batch_list}"

echo ""
echo "=========================================="
echo "Task ${SLURM_ARRAY_TASK_ID} completed at $(date)"
echo "Success: ${success_count}"
echo "Failed: ${fail_count}"
echo "Skipped: ${skip_count}"
echo "Total in batch: ${genome_count}"
echo "=========================================="

# Save summary
echo "${SLURM_ARRAY_TASK_ID},${success_count},${fail_count},${skip_count}" >> "${LOG_DIR}/task_summary.csv"

exit 0
