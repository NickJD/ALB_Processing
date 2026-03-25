#!/bin/bash
#SBATCH --job-name=sourmash_extract
#SBATCH --output=/users/3057556/jobs/ALB/sourmash_extract_ALB_%A_%a.out
#SBATCH --error=/users/3057556/jobs/ALB/sourmash_extract_ALB_%A_%a.err
#SBATCH --partition=k2-bioinf,k2-himem
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=600G
#SBATCH --time=3-00:00:00
#SBATCH --mail-user=n.dimonaco@qub.ac.uk
#SBATCH --mail-type=BEGIN,END,FAIL


module load apps/anaconda3/2024.06/bin
source activate /mnt/scratch2/igfs-anaconda/conda-envs/sourmash_v4.9.4

cd /mnt/scratch2/users/3057556/DASA/sourmash

/mnt/scratch2/igfs-anaconda/conda-envs/sourmash_v4.9.4/bin/python ./new_extract_ecoli_sigs.py 
