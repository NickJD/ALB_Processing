#!/bin/bash
#SBATCH --job-name=mmseqs2_cluster_med
#SBATCH --output=/users/3057556/jobs/ALB/mmseqs2_%j.out
#SBATCH --error=/users/3057556/jobs/ALB/mmseqs2_%j.err
#SBATCH --partition=k2-bioinf,k2-himem
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=30
#SBATCH --mem=800G
#SBATCH --time=3-00:00:00

set -euo pipefail

# Load MMseqs2
module load apps/anaconda3/2024.06/bin
source activate /mnt/scratch2/igfs-anaconda/conda-envs/mmseqs2_18.8

cd /mnt/scratch2/users/3057556/DASA/mmseqs2/


# Configuration
FASTA_FILE="/mnt/scratch2/users/3057556/DASA/pyrodigal_output/ecoli_pyrodigal_AA.fasta"
OUTPUT_PREFIX="ecoli_gene_families"
TMP_DIR="/mnt/scratch2/users/3057556/DASA/mmseqs2/mmseqs2_tmp"  # Use fast scratch space
THREADS=${SLURM_CPUS_PER_TASK}

# Clustering parameters
MIN_SEQ_ID=0.8          # 80% sequence identity (adjust as needed)
COVERAGE=0.8            # 80% coverage (adjust as needed)
CLUSTER_MODE=0          # 0=Set-Cover (greedy), 1=Connected-Component, 2=Greedy-Incremental
SENSITIVITY=5.7         # Higher = more sensitive but slower (range: 1-7.5)

mkdir -p logs
mkdir -p ${TMP_DIR}

echo "=========================================="
echo "MMseqs2 Gene Family Clustering"
echo "=========================================="
echo "Input: ${FASTA_FILE}"
echo "Threads: ${THREADS}"
echo "Parameters:"
echo "  Min sequence identity: ${MIN_SEQ_ID}"
echo "  Min coverage: ${COVERAGE}"
echo "  Cluster mode: ${CLUSTER_MODE}"
echo "  Sensitivity: ${SENSITIVITY}"
echo "=========================================="
echo ""

# Count sequences
num_seqs=$(grep -c "^>" ${FASTA_FILE})
echo "Total sequences to cluster: ${num_seqs}"
echo ""

# Run MMseqs2 easy-cluster
echo "Starting MMseqs2 clustering..."
echo "Started at: $(date)"

mmseqs easy-cluster \
  ${FASTA_FILE} \
  ${OUTPUT_PREFIX} \
  ${TMP_DIR} \
  --min-seq-id ${MIN_SEQ_ID} \
  -c ${COVERAGE} \
  --cov-mode 0 \
  --cluster-mode ${CLUSTER_MODE} \
  -s ${SENSITIVITY} \
  --threads ${THREADS} \
  --remove-tmp-files 1

echo ""
echo "Finished at: $(date)"
echo ""

# Analyze results
echo "=========================================="
echo "Clustering Results:"
echo "=========================================="

# Count clusters
num_clusters=$(cut -f1 ${OUTPUT_PREFIX}_cluster.tsv | sort -u | wc -l)
echo "Number of gene families: ${num_clusters}"

# Count singletons
num_singletons=$(cut -f1 ${OUTPUT_PREFIX}_cluster.tsv | sort | uniq -c | awk '$1==1' | wc -l)
echo "Singleton clusters: ${num_singletons}"

# Average cluster size
avg_size=$(awk '{print $1}' ${OUTPUT_PREFIX}_cluster.tsv | sort | uniq -c | \
           awk '{sum+=$1; n++} END {print sum/n}')
echo "Average gene family size: ${avg_size}"

# Largest cluster
max_size=$(awk '{print $1}' ${OUTPUT_PREFIX}_cluster.tsv | sort | uniq -c | \
           sort -k1,1rn | head -1 | awk '{print $1}')
echo "Largest gene family: ${max_size} members"

echo ""
echo "Output files:"
echo "  ${OUTPUT_PREFIX}_cluster.tsv - cluster assignments"
echo "  ${OUTPUT_PREFIX}_rep_seq.fasta - representative sequences"
echo "=========================================="


