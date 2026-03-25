#!/bin/sh
#SBATCH --job-name=cat
#SBATCH --output=/users/3057556/jobs/ALB/cat_ecoli_%A_%a.out
#SBATCH --error=/users/3057556/jobs/ALB/cat_ecoli_%A_%a.err
#SBATCH --partition=k2-bioinf,k2-lowpri
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=80:00:00
#SBATCH --mail-user=n.dimonaco@qub.ac.uk
#SBATCH --mail-type=BEGIN,END,FAIL


cd /mnt/scratch2/users/3057556/DASA/pyrodigal_output

#find Ecoli_AA_FASTA -type f -name "*.faa" -exec cat {} + | awk '/^>/ {print $1; next} {print}' > ecoli_pyrodigal_AA.fasta

find  Ecoli_DNA_FASTA  -type f -name "*.fna" -exec cat {} + | awk '/^>/ {print $1; next} {print}' > ecoli_pyrodigal_DNA.fasta

