#!/bin/bash
#SBATCH --job-name=greedy_derep
#SBATCH --output=/users/3057556/jobs/ALB/greedy_%A_%a.out
#SBATCH --error=/users/3057556/jobs/ALB/greedy_%A_%a.err
#SBATCH --partition=k2-bioinf,k2-medpri
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=24:00:00

set -euo pipefail

module load apps/anaconda3/2024.06/bin
source activate /mnt/scratch2/igfs-anaconda/conda-envs/sourmash_branchwater_4.9.4

cd /mnt/scratch2/users/3057556/DASA/sourmash/

SIG_FILE="/mnt/scratch2/users/3057556/DASA/sourmash/E_coli.sigs.zip"
ANI_THRESHOLD=0.98  # 99.99% ANI
K_SIZE=51

echo "=========================================="
echo "Greedy Dereplication (No Pairwise Comparison)"
echo "=========================================="
echo "Input: ${SIG_FILE}"
echo "ANI threshold: ${ANI_THRESHOLD}"
echo "=========================================="
echo ""

ENV=/mnt/scratch2/igfs-anaconda/conda-envs/sourmash_branchwater_4.9.4
$ENV/bin/python << 'PYEOF'
import sourmash
import sys

SIG_FILE = "/mnt/scratch2/users/3057556/DASA/sourmash/E_coli.sigs.zip"
K_SIZE = 51
ANI_THRESHOLD = 0.98

print("Loading signatures...")
signatures = []
for sig in sourmash.load_file_as_signatures(SIG_FILE, ksize=K_SIZE):
    signatures.append(sig)

print(f"Loaded {len(signatures):,} signatures")
print(f"\nStarting greedy dereplication at {ANI_THRESHOLD*100}% ANI...")
print("(This avoids all-vs-all comparison)")
print()

representatives = []
represented_indices = set()

for i, query_sig in enumerate(signatures):
    if i in represented_indices:
        continue
    
    if i % 1000 == 0:
        print(f"  Processed {i:,}/{len(signatures):,} genomes... ({len(representatives):,} reps so far)")
    
    # This genome becomes a representative
    representatives.append(query_sig)
    represented_indices.add(i)
    
    # Find all genomes similar to this representative
    for j in range(i + 1, len(signatures)):
        if j in represented_indices:
            continue
        
        # Calculate Jaccard similarity (fast, no alignment)
        similarity = query_sig.jaccard(signatures[j])
        
        # If very similar, mark as represented
        if similarity >= ANI_THRESHOLD:
            represented_indices.add(j)

print(f"\nGreedy dereplication complete!")
print(f"  Original genomes: {len(signatures):,}")
print(f"  Representative genomes: {len(representatives):,}")
print(f"  Redundant genomes removed: {len(signatures) - len(representatives):,}")
print(f"  Reduction: {100 * (1 - len(representatives)/len(signatures)):.1f}%")

# Save representatives
print("\nSaving representative signatures...")
with sourmash.sourmash_args.SaveSignaturesToLocation('ecoli_representatives_98.sig') as save:
    for sig in representatives:
        save.add(sig)

# Save list of representative names
with open('representative_names_98.txt', 'w') as f:
    for sig in representatives:
        f.write(f"{sig.name}\n")

print("\nFiles created:")
print("  - ecoli_representatives_98.sig")
print("  - representative_names_98.txt")
print("\nDone!")
PYEOF
