import sourmash
import glob

# Load genome IDs
with open('../E_coli.list', 'r') as f:
    genome_ids = set(line.strip() for line in f if line.strip())

print(f"Looking for {len(genome_ids)} genomes...")

sig_files = sorted(glob.glob('sourmash_sigs/*.sig'))
print(f"Searching {len(sig_files)} signature files...")

extracted = []
found_ids = set()

for i, sig_file in enumerate(sig_files):
    if i % 50 == 0:
        print(f"Processing file {i+1}/{len(sig_files)}...")
    
    try:
        # Load all signatures from this file
        for sig in sourmash.load_file_as_signatures(sig_file):
            sig_name = sig.name
            
            # Check if any genome ID matches
            for genome_id in genome_ids:
                # Match against signature name (which starts with genome ID)
                if sig_name.startswith(genome_id):
                    extracted.append(sig)
                    found_ids.add(genome_id)
                    if len(found_ids) % 100 == 0:
                        print(f"  Found {len(found_ids)} genomes so far...")
                    break
    except Exception as e:
        print(f"Error processing {sig_file}: {e}")
        continue

print(f"\nExtracted {len(extracted)} signatures for {len(found_ids)} genomes")

# List any missing genomes
missing = genome_ids - found_ids
if missing:
    print(f"WARNING: {len(missing)} genomes not found")
    print(f"First few missing: {list(missing)[:10]}")

# Save
print("Saving signatures...")
with sourmash.sourmash_args.SaveSignaturesToLocation('E_coli.sigs') as save:
    for sig in extracted:
        save.add(sig)

print("Done! Saved to E_coli.sigs")
