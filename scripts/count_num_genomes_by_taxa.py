import os
import glob
from collections import defaultdict

# Files
taxa_list_file = "list_of_wanted_taxa.list"  # File with taxa names
genome_metadata_file = "species_calls.tsv"  # genome_id -> species mapping
genome_directory = "/mnt/scratch2/igfs-databases/AllTheBacteria/0.2/genomes"  # Directory with genome files

# Read taxa of interest
print("Loading taxa of interest...")
with open(taxa_list_file, 'r') as f:
    taxa_of_interest = set(line.strip() for line in f if line.strip())

print(f"Looking for {len(taxa_of_interest)} taxa:")
for taxon in sorted(taxa_of_interest):
    print(f"  - {taxon}")
print()

# Read genome metadata (genome_id -> species)
print("Loading genome metadata...")
genome_to_species = {}
with open(genome_metadata_file, 'r') as f:
    header = next(f)  # Skip header
    for line in f:
        parts = line.strip().split('\t')
        if len(parts) >= 2:
            genome_id = parts[0]
            species = parts[1]
            genome_to_species[genome_id] = species

print(f"Loaded metadata for {len(genome_to_species):,} genomes")
print()

# Find genome files
print("Scanning genome directory...")
genome_files = glob.glob(f"{genome_directory}/*.fa.gz") + \
               glob.glob(f"{genome_directory}/*.fna.gz") + \
               glob.glob(f"{genome_directory}/*.fasta.gz") + \
               glob.glob(f"{genome_directory}/*.fa") + \
               glob.glob(f"{genome_directory}/*.fna")

print(f"Found {len(genome_files):,} genome files")
print()

# Count genomes per taxon
taxon_counts = defaultdict(list)
unmatched_files = []

print("Matching genomes to taxa...")
for genome_file in genome_files:
    # Extract genome ID from filename
    basename = os.path.basename(genome_file)
    # Remove extensions
    genome_id = basename.replace('.fa.gz', '').replace('.fna.gz', '') \
        .replace('.fasta.gz', '').replace('.fa', '') \
        .replace('.fna', '')

    # Look up species
    if genome_id in genome_to_species:
        species = genome_to_species[genome_id]

        # Check if this species is in our taxa of interest
        if species in taxa_of_interest:
            taxon_counts[species].append(genome_id)
    else:
        unmatched_files.append(basename)

# Print results
print("\n" + "=" * 70)
print("RESULTS: Genomes per Taxon")
print("=" * 70)
print(f"{'Taxon':<40} {'Count':>10}")
print("-" * 70)

total_genomes = 0
for taxon in sorted(taxa_of_interest):
    count = len(taxon_counts[taxon])
    total_genomes += count
    print(f"{taxon:<40} {count:>10,}")

print("-" * 70)
print(f"{'TOTAL':<40} {total_genomes:>10,}")
print("=" * 70)

# Taxa with zero genomes
missing_taxa = [t for t in taxa_of_interest if len(taxon_counts[t]) == 0]
if missing_taxa:
    print(f"\nWARNING: {len(missing_taxa)} taxa with no genomes found:")
    for taxon in sorted(missing_taxa):
        print(f"  - {taxon}")

# Save detailed results
print("\nSaving detailed results...")

# Save counts summary
with open('taxon_genome_counts.txt', 'w') as f:
    f.write(f"Taxon\tCount\n")
    for taxon in sorted(taxa_of_interest):
        count = len(taxon_counts[taxon])
        f.write(f"{taxon}\t{count}\n")

print("Saved: taxon_genome_counts.txt")

# Save genome IDs per taxon
for taxon in taxa_of_interest:
    if len(taxon_counts[taxon]) > 0:
        safe_name = taxon.replace(' ', '_').replace('/', '_')
        filename = f"{safe_name}_genomes.txt"
        with open(filename, 'w') as f:
            for genome_id in sorted(taxon_counts[taxon]):
                f.write(f"{genome_id}\n")
        print(f"Saved: {filename} ({len(taxon_counts[taxon])} genomes)")

print("\nDone!")