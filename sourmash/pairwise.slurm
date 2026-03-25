#!/bin/bash
#SBATCH --job-name=derep_ecoli
#SBATCH --output=/users/3057556/jobs/ALB/pairwise_%A_%a.out
#SBATCH --error=/users/3057556/jobs/ALB/pairwise_%A_%a.err
#SBATCH --partition=k2-bioinf
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=256G
#SBATCH --time=24:00:00

set -euo pipefail

module load apps/anaconda3/2024.06/bin
source activate /mnt/scratch2/igfs-anaconda/conda-envs/sourmash_v4.9.4

cd /mnt/scratch2/users/3057556/DASA/sourmash

SIG_FILE="E_coli.sigs"
K_SIZE=51  # Use k=51 for clustering

mkdir -p dereplicated

echo "=========================================="
echo "Dereplicating E. coli genomes at 99.99% ANI"
echo "=========================================="
echo ""

# Step 2a: Compute pairwise distances
echo "Step 1: Computing pairwise distances (this may take a while)..."
sourmash compare \
  --ani \
  -k ${K_SIZE} \
  -p ${SLURM_CPUS_PER_TASK} \
  -o ecoli_comparison.cmp \
  --csv ecoli_comparison.csv \
  ${SIG_FILE}

echo ""
echo "Distance matrix created: ecoli_comparison.csv"

# Step 2b: Cluster and select representatives
echo ""
echo "Step 2: Clustering genomes at 99.99% ANI threshold..."

python3 << 'EOF'
import numpy as np
import pandas as pd
from scipy.cluster.hierarchy import linkage, fcluster
from scipy.spatial.distance import squareform

# Load distance matrix
print("Loading distance matrix...")
dist_df = pd.read_csv("ecoli_comparison.csv", index_col=0)

print(f"Matrix size: {len(dist_df)} x {len(dist_df)}")

# Convert ANI similarity to distance (1 - ANI)
# For 99.99% ANI threshold, distance threshold = 1 - 0.9999 = 0.0001
distance_matrix = 1 - dist_df.values

# Convert to condensed form for clustering
condensed_dist = squareform(distance_matrix)

print("Performing hierarchical clustering...")
Z = linkage(condensed_dist, method='average')

# Cluster at 99.99% ANI (distance = 0.0001)
threshold = 0.0001
clusters = fcluster(Z, t=threshold, criterion='distance')

# Create cluster assignments
cluster_df = pd.DataFrame({
    'genome': dist_df.index,
    'cluster': clusters
})

# Select representatives (first genome in each cluster)
representatives = cluster_df.groupby('cluster').first().reset_index()

print(f"\nClustering Results:")
print(f"  Original genomes: {len(cluster_df)}")
print(f"  Clusters at 99.99% ANI: {len(representatives)}")
print(f"  Redundant genomes removed: {len(cluster_df) - len(representatives)}")
print(f"  Reduction: {100 * (1 - len(representatives)/len(cluster_df)):.1f}%")

# Cluster size statistics
cluster_sizes = cluster_df.groupby('cluster').size()
print(f"\nCluster size statistics:")
print(f"  Mean cluster size: {cluster_sizes.mean():.1f}")
print(f"  Median cluster size: {cluster_sizes.median():.0f}")
print(f"  Largest cluster: {cluster_sizes.max()}")
print(f"  Singleton clusters: {(cluster_sizes == 1).sum()}")

# Save results
cluster_df.to_csv("dereplicated/ecoli_clusters.csv", index=False)
representatives.to_csv("dereplicated/ecoli_representatives.csv", index=False)

# Save representative genome list
with open("dereplicated/representative_list.txt", 'w') as f:
    for genome in representatives['genome']:
        f.write(f"{genome}\n")

# Save cluster size distribution
cluster_sizes.to_csv("dereplicated/cluster_sizes.csv",
                     header=['count'], index_label='cluster')

print("\nFiles created:")
print("  - dereplicated/ecoli_clusters_99_99.csv")
print("  - dereplicated/ecoli_representatives_99_99.csv")
print("  - dereplicated/representative_list_99_99.txt")
print("  - dereplicated/cluster_sizes_99_99.csv")
EOF

# Step 2c: Extract representative signatures
echo ""
echo "Step 3: Extracting representative signatures..."

sourmash sig extract \
  --include-file dereplicated/representative_list.txt \
  -o dereplicated/ecoli_representatives.sig \
  ${SIG_FILE}

# Verify
rep_count=$(sourmash sig describe -k ${K_SIZE} dereplicated/ecoli_representatives.sig 2>/dev/null | wc -l)

echo ""
echo "=========================================="
echo "Dereplication complete!"
echo "  Representative genomes: ${rep_count}"
echo "  Output: dereplicated/ecoli_representatives.sig"
echo "=========================================="