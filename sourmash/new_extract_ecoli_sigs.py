import sourmash
import glob
import os

# Load genome IDs
with open('../E_coli_clean.list', 'r') as f:
    genome_ids = set(line.strip().replace('./', '').replace('.fa.gz', '') for line in f if line.strip())

print(f"Looking for {len(genome_ids)} genomes...")
print(f"First few IDs: {list(genome_ids)[:5]}")

sig_files = sorted(glob.glob('sourmash_sigs/*.sig'))
print(f"Searching {len(sig_files)} signature files...")

extracted = []
found_ids = set()

for i, sig_file in enumerate(sig_files):
    if i % 50 == 0:
        print(f"Processing file {i+1}/{len(sig_files)}...")
    
    try:
        # Load ALL signatures (all k-mer sizes)
        for sig in sourmash.load_file_as_signatures(sig_file):
            # Get the source filename from signature
            source_file = getattr(sig, 'filename', '')
            
            # Extract genome ID from source file path
            # e.g., "/mnt/.../SAMD00002588.fa.gz" -> "SAMD00002588"
            if source_file:
                genome_id = os.path.basename(source_file).replace('.fa.gz', '')
            else:
                # Fallback to signature name if it exists
                sig_name = sig.name if sig.name else ''
                if not sig_name or sig_name == '** no name **':
                    continue
                genome_id = sig_name.split('.')[0].split('_')[0]
            
            # Check if this genome ID is in our list
            if genome_id in genome_ids:
                extracted.append(sig)
                found_ids.add(genome_id)
                
                # Only print progress for k=31 to avoid spam
                if len(found_ids) % 100 == 0 and sig.minhash.ksize == 31:
                    print(f"  Found {len(found_ids)} genomes so far...")
    
    except Exception as e:
        print(f"Error processing {sig_file}: {e}")
        continue

print(f"\nExtracted {len(extracted)} signatures for {len(found_ids)} genomes")
print(f"  (This includes all k-mer sizes: k=21, k=31, k=51)")

# List any missing genomes
missing = genome_ids - found_ids
if missing:
    print(f"WARNING: {len(missing)} genomes not found")
    print(f"First few missing: {list(missing)[:10]}")
    
    # Save missing IDs for debugging
    with open('missing_genomes.txt', 'w') as f:
        for gid in sorted(missing):
            f.write(f"{gid}\n")
    print(f"Full list of missing genomes saved to: missing_genomes.txt")

# Save
print("\nSaving signatures...")
with sourmash.sourmash_args.SaveSignaturesToLocation('E_coli.sigs') as save:
    for sig in extracted:
        save.add(sig)

# Verify
print("\nVerifying extraction...")
for k in [21, 31, 51]:
    count = sum(1 for sig in sourmash.load_file_as_signatures('E_coli.sigs', ksize=k))
    print(f"  k={k}: {count} signatures")

unique_genomes = len(found_ids)
print(f"\nUnique genomes extracted: {unique_genomes}")
print(f"Expected total signatures: {unique_genomes * 3} (3 k-mer sizes per genome)")

print("\nDone! Saved to E_coli.sigs")
