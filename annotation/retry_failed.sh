#!/bin/bash

# Retry annotation for failed and corrupted genomes

LOG_FILE="${1:-annotation_log.tsv}"
GENOME_DIR="${2:-.}"
OUTPUT_DIR="annotations"
PARALLEL_JOBS=4

echo "=== Retry Failed Annotations ==="
echo ""

if [ ! -f "$LOG_FILE" ]; then
    echo "Log file not found: $LOG_FILE"
    exit 1
fi

# Get list of failed genomes
failed_list=$(mktemp)
grep "FAILED" "$LOG_FILE" | cut -f3 | sort -u > "$failed_list"
failed_count=$(wc -l < "$failed_list")

echo "Found $failed_count unique failed genomes"
echo ""

if [ $failed_count -eq 0 ]; then
    echo "No failed genomes to retry!"
    rm "$failed_list"
    exit 0
fi

echo "Retrying failed genomes..."

# Find the actual files and retry
while read genome_name; do
    genome_file=$(find "$GENOME_DIR" -name "${genome_name}.fa.gz" | head -1)
    if [ -n "$genome_file" ]; then
        echo "$genome_file"
    else
        echo "Warning: Could not find file for $genome_name" >&2
    fi
done < "$failed_list" | \
    rush -j $PARALLEL_JOBS -c \
    './annotate_genomes.py {} -o '"$OUTPUT_DIR"' -l '"$LOG_FILE"' -f'

rm "$failed_list"

echo ""
echo "Retry complete! Check $LOG_FILE for results."


