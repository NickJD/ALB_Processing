#!/bin/bash
#SBATCH --job-name=derep_ecoli_scripts
#SBATCH --output=/users/3057556/jobs/ALB/pairwise_scrips_%A_%a.out
#SBATCH --error=/users/3057556/jobs/ALB/pairwise_scripts_%A_%a.err
#SBATCH --partition=k2-bioinf,k2-himem,k2-medpri
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=30
#SBATCH --mem=100G
#SBATCH --time=24:00:00 



module load apps/anaconda3/2024.06/bin
source activate /mnt/scratch2/igfs-anaconda/conda-envs/sourmash_branchwater_4.9.4

cd /mnt/scratch2/users/3057556/DASA/sourmash

SIG_FILE="E_coli.sigs.zip"
K_SIZE=51  # Use k=51 for clustering

mkdir -p dereplicated

echo "=========================================="
echo "Comparing E. coli genomes"
echo "=========================================="
echo ""

# Step 2a: Compute pairwise distances
echo "Step 1: Computing pairwise distances (this may take a while)..."
sourmash scripts pairwise  --ani --ksize 51 --scaled 1000 --cores 30  -o ./dereplicated/ecoli_comparison_51_scripts_new.csv E_coli.sigs.zip --write-all


echo ""
echo "Distance matrix created: ecoli_comparison.csv"

