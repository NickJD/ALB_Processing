#!/bin/bash
#SBATCH --job-name=greedy_testing
#SBATCH --output=/users/3057556/jobs/ALB/testing_%A_%a.out
#SBATCH --error=/users/3057556/jobs/ALB/testing_%A_%a.err
#SBATCH --partition=k2-bioinf,k2-medpri,k2-hipri
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=03:00:00

ENV=/mnt/scratch2/igfs-anaconda/conda-envs/sourmash_branchwater_4.9.4

$ENV/bin/python << 'PYEOF'
import sourmash
print("sourmash version:", sourmash.__version__)
PYEOF

