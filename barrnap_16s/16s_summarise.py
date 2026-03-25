#!/usr/bin/env python3

import os
import gzip
import argparse
from collections import defaultdict, Counter

def parse_gff_16s_lengths(gff_path):
    """
    Parse a gzipped GFF file and return list of 16S rRNA lengths.
    """
    lengths = []

    with gzip.open(gff_path, "rt") as f:
        for line in f:
            if line.startswith("#"):
                continue

            parts = line.strip().split("\t")
            if len(parts) < 9:
                continue

            feature_type = parts[2]
            start = int(parts[3])
            end = int(parts[4])
            attributes = parts[8]

            # Barrnap typically labels as rRNA and includes product=16S ribosomal RNA
            if feature_type == "rRNA" and "16S" in attributes:
                length = abs(end - start) + 1
                lengths.append(length)

    return lengths


def main():
    parser = argparse.ArgumentParser(
        description="Analyse distribution of predicted 16S rRNA lengths from Barrnap GFF (.gz) files."
    )
    parser.add_argument("input_dir", help="Directory containing .gff.gz files")
    parser.add_argument("--log", default="16s_length_distribution.log",
                        help="Output log file")

    args = parser.parse_args()

    genome_stats = {}
    all_lengths = []

    print("Scanning directory...")
    for root, _, files in os.walk(args.input_dir):
        for file in files:
            if file.endswith(".gff.gz"):
                gff_path = os.path.join(root, file)
                genome_id = os.path.basename(file).replace(".gff.gz", "")

                lengths = parse_gff_16s_lengths(gff_path)
                genome_stats[genome_id] = lengths
                all_lengths.extend(lengths)

    total_genomes = len(genome_stats)

    # Per-genome classification
    full_length_genomes = 0
    truncated_genomes = 0
    no_16s_genomes = 0
    multi_copy_genomes = 0

    for genome, lengths in genome_stats.items():
        if len(lengths) == 0:
            no_16s_genomes += 1
            continue

        if len(lengths) > 1:
            multi_copy_genomes += 1

        max_len = max(lengths)

        if max_len >= 1400:
            full_length_genomes += 1
        else:
            truncated_genomes += 1

    # Length distribution bins
    bins = Counter()
    for length in all_lengths:
        if length < 500:
            bins["<500"] += 1
        elif length < 1000:
            bins["500-999"] += 1
        elif length < 1400:
            bins["1000-1399"] += 1
        elif length < 1600:
            bins["1400-1599"] += 1
        else:
            bins[">=1600"] += 1

    # Write log
    with open(args.log, "w") as out:
        out.write("=== 16S Length Distribution Analysis ===\n\n")
        out.write(f"Total genomes analysed: {total_genomes}\n")
        out.write(f"Total 16S sequences detected: {len(all_lengths)}\n\n")

        out.write("Per-genome classification:\n")
        out.write(f"Genomes with >=1400 bp 16S: {full_length_genomes} "
                  f"({full_length_genomes/total_genomes:.3f})\n")
        out.write(f"Genomes with only truncated (<1400 bp): {truncated_genomes} "
                  f"({truncated_genomes/total_genomes:.3f})\n")
        out.write(f"Genomes with multiple 16S copies: {multi_copy_genomes} "
                  f"({multi_copy_genomes/total_genomes:.3f})\n")
        out.write(f"Genomes with no 16S detected: {no_16s_genomes} "
                  f"({no_16s_genomes/total_genomes:.3f})\n\n")

        out.write("Length bins (all detected 16S copies):\n")
        for bin_name in sorted(bins.keys()):
            out.write(f"{bin_name}: {bins[bin_name]}\n")

        if all_lengths:
            out.write("\nSummary statistics (all copies):\n")
            out.write(f"Min length: {min(all_lengths)}\n")
            out.write(f"Max length: {max(all_lengths)}\n")
            out.write(f"Mean length: {sum(all_lengths)/len(all_lengths):.2f}\n")

    print(f"Analysis complete. Results written to {args.log}")


if __name__ == "__main__":
    main()

