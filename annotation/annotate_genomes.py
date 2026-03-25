#!/usr/bin/env python3
import sys
import gzip
import argparse
import subprocess
from pathlib import Path
from datetime import datetime
import pyrodigal

def get_successfully_processed(log_file):
    """
    Read log file and return set of successfully processed genome names
    
    Args:
        log_file: Path to log file
        
    Returns:
        Set of genome names that have been successfully processed
    """
    processed = set()
    
    if not Path(log_file).exists():
        return processed
    
    try:
        with open(log_file, 'r') as f:
            for line in f:
                if line.startswith('Timestamp'):  # Skip header
                    continue
                parts = line.strip().split('\t')
                if len(parts) >= 3 and parts[1] == 'SUCCESS':
                    genome_name = parts[2]
                    processed.add(genome_name)
    except Exception as e:
        print(f"Warning: Could not read log file: {e}", file=sys.stderr)
    
    return processed

def verify_gzip_integrity(gzip_file):
    """
    Verify that a gzip file is complete and not corrupted
    
    Args:
        gzip_file: Path to .gz file
        
    Returns:
        True if file is valid, False otherwise
    """
    try:
        # Use gzip -t to test file integrity
        result = subprocess.run(
            ['gzip', '-t', gzip_file],
            capture_output=True,
            timeout=30  # 30 second timeout
        )
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        print(f"Warning: Timeout while checking {gzip_file}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"Warning: Could not verify {gzip_file}: {e}", file=sys.stderr)
        return False

def decompress_if_needed(input_file):
    """Read genome file, handling gzip compression"""
    if input_file.endswith('.gz'):
        with gzip.open(input_file, 'rt') as f:
            return f.read()
    else:
        with open(input_file, 'r') as f:
            return f.read()

def annotate_genome(genome_file, output_dir, log_file, force=False):
    """
    Annotate a single genome with Pyrodigal
    
    Args:
        genome_file: Path to input genome (.fa or .fa.gz)
        output_dir: Directory for output files
        log_file: Path to log file
        force: If True, re-annotate even if already processed
        
    Returns:
        0 for success, 1 for failure, 2 for skipped
    """
    genome_path = Path(genome_file)
    genome_name = genome_path.stem.replace('.fa', '')  # Remove .fa or .fa.gz
    
    # Check if already successfully processed
    if not force:
        processed = get_successfully_processed(log_file)
        if genome_name in processed:
            print(f"⊙ {genome_name}: Already processed (skipping)")
            return 2
    
    # Verify gzip integrity for .gz files
    if genome_file.endswith('.gz'):
        print(f"Verifying: {genome_name}...", end=' ')
        if not verify_gzip_integrity(genome_file):
            log_message = f"{datetime.now().isoformat()}\tFAILED\t{genome_name}\tCorrupted or incomplete gzip file\t\n"
            with open(log_file, 'a') as log:
                log.write(log_message)
            print(f"✗ {genome_name}: Corrupted or incomplete gzip file", file=sys.stderr)
            return 1
        print("verified", end=' ')
    
    # Create output paths
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    gff_file = output_dir / f"{genome_name}.gff"
    fna_file = output_dir / f"{genome_name}.fna"  # nucleotide sequences
    faa_file = output_dir / f"{genome_name}.faa"  # protein sequences
    
    try:
        # Read genome sequence
        print(f"→ processing...", end=' ')
        sequence = decompress_if_needed(genome_file)
        
        # Check if sequence is empty
        if not sequence.strip():
            raise ValueError("Empty sequence file")
        
        # Initialise Pyrodigal in single mode (for complete genomes)
        # Use meta=False for isolate genomes, meta=True for metagenomes
        orf_finder = pyrodigal.GeneFinder(meta=False)
        
        # Train on the genome (automatically selects best translation table)
        orf_finder.train(sequence.encode())
        
        # Find genes
        genes = orf_finder.find_genes(sequence.encode())
        
        # Write GFF output
        with open(gff_file, 'w') as f:
            #f.write("##gff-version 3\n")
            genes.write_gff(f, sequence_id=genome_name)
        
        # Write nucleotide sequences (DNA)
        with open(fna_file, 'w') as f:
            genes.write_genes(f, sequence_id=genome_name)
        
        # Write protein sequences (amino acids)
        with open(faa_file, 'w') as f:
            genes.write_translations(f, sequence_id=genome_name)
        
        # Log success
        gene_count = len(genes)
        log_message = f"{datetime.now().isoformat()}\tSUCCESS\t{genome_name}\t{gene_count} genes\t{gff_file}\n"
        with open(log_file, 'a') as log:
            log.write(log_message)
        
        print(f"✓ {gene_count} genes")
        return 0
        
    except Exception as e:
        # Log failure
        log_message = f"{datetime.now().isoformat()}\tFAILED\t{genome_name}\t{str(e)}\t\n"
        with open(log_file, 'a') as log:
            log.write(log_message)
        
        print(f"✗ {genome_name}: {str(e)}", file=sys.stderr)
        return 1

def main():
    parser = argparse.ArgumentParser(description='Annotate bacterial genomes with Pyrodigal')
    parser.add_argument('genome', help='Input genome file (.fa or .fa.gz)')
    parser.add_argument('-o', '--output-dir', default='annotations',
                       help='Output directory (default: annotations)')
    parser.add_argument('-l', '--log-file', default='annotation_log.tsv',
                       help='Log file path (default: annotation_log.tsv)')
    parser.add_argument('-f', '--force', action='store_true',
                       help='Force re-annotation even if already processed')
    
    args = parser.parse_args()
    
    # Run annotation
    exit_code = annotate_genome(args.genome, args.output_dir, args.log_file, args.force)
    sys.exit(exit_code)

if __name__ == '__main__':
    main()
