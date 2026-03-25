#!/bin/bash
#SBATCH --job-name=derep_ecoli
#SBATCH --output=/users/3057556/jobs/ALB/pairwise_%A_%a.out
#SBATCH --error=/users/3057556/jobs/ALB/pairwise_%A_%a.err
#SBATCH --partition=k2-bioinf,k2-himem
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=20
#SBATCH --mem=900G
#SBATCH --time=3-00:00:00 

set -euo pipefail

module load apps/anaconda3/2024.06/bin
source activate /mnt/scratch2/igfs-anaconda/conda-envs/sourmash_v4.9.4

cd /mnt/scratch2/users/3057556/DASA/sourmash

SIG_FILE="E_coli.sigs"
K_SIZE=51  # Use k=51 for clustering

mkdir -p dereplicated

echo "=========================================="
echo "Comparing E. coli genomes"
echo "=========================================="
echo ""

# Step 2a: Compute pairwise distances
echo "Step 1: Computing pairwise distances (this may take a while)..."
sourmash compare \
  --ani \
  -k ${K_SIZE} \
  -p ${SLURM_CPUS_PER_TASK} \
  -o dereplicated/ecoli_comparison_51.cmp \
  --csv dereplicated/ecoli_comparison_51.csv \
  ${SIG_FILE}

echo ""
echo "Distance matrix created: ecoli_comparison.csv"

