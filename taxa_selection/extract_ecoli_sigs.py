import sourmash
import glob

# Load genome IDs
with open('E_coli.list', 'r') as f:
    genome_ids = set(line.strip() for line in f if line.strip())

print(f"Looking for {len(genome_ids)} genomes...")

sig_files = glob.glob('sourmash_sigs/*.sig')
extracted = []
found_ids = set()

for sig_file in sig_files:
    for sig in sourmash.load_file_as_signatures(sig_file, ksize=31):
        source = getattr(sig, 'filename', '')
        
        # Check if any genome ID is in the source filename
        for genome_id in genome_ids:
            if genome_id in source:
                extracted.append(sig)
                found_ids.add(genome_id)
                print(f"Found {genome_id}: {sig.name}")
                break

print(f"\nExtracted {len(extracted)} signatures for {len(found_ids)} genomes")

with sourmash.sourmash_args.SaveSignaturesToLocation('E_coli.sigs') as save:
    for sig in extracted:
        save.add(sig)

print("Saved to E_coli.sigs")
