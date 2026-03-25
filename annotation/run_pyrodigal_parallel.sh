#!/bin/bash

set -e

# Configuration
GENOME_DIR="${1:-.}"  # Directory with genomes (default: current dir)
OUTPUT_DIR="annotations"
LOG_FILE="annotation_log.tsv"
PARALLEL_JOBS=4  # Adjust based on your CPU cores
FAILED_LOG="failed_genomes.txt"
CORRUPTED_LOG="corrupted_genomes.txt"
FORCE=false

# Parse options
while getopts "j:f" opt; do
    case $opt in
        j) PARALLEL_JOBS=$OPTARG ;;
        f) FORCE=true ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done
shift $((OPTIND-1))

# Update genome directory if provided after options
if [ -n "$1" ]; then
    GENOME_DIR="$1"
fi

echo "=== Pyrodigal Genome Annotation Pipeline (Resume-capable) ==="
echo "Genome directory: $GENOME_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Parallel jobs: $PARALLEL_JOBS"
if [ "$FORCE" = true ]; then
    echo "Mode: Force re-annotation"
else
    echo "Mode: Resume (skip already processed)"
fi
echo ""

# Check if pyrodigal is installed
if ! python3 -c "import pyrodigal" 2>/dev/null; then
    echo "Error: pyrodigal not found. Install with: pip install pyrodigal"
    exit 1
fi

# Check if gzip is available
if ! command -v gzip &> /dev/null; then
    echo "Error: gzip not found. Please install gzip."
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Initialize log file with header if it doesn't exist
if [ ! -f "$LOG_FILE" ]; then
    echo -e "Timestamp\tStatus\tGenome\tDetails\tOutput" > "$LOG_FILE"
    echo "Created new log file: $LOG_FILE"
else
    # Count already processed genomes
    already_processed=$(grep -c "SUCCESS" "$LOG_FILE" 2>/dev/null || echo 0)
    echo "Found existing log file with $already_processed successfully processed genomes"
fi

# Count total genomes
total_genomes=$(find "$GENOME_DIR" -name "*.fa.gz" | wc -l)
echo "Found $total_genomes total genomes in directory"

# Count how many are already done (if not forcing)
if [ "$FORCE" = false ]; then
    already_done=$(grep "SUCCESS" "$LOG_FILE" 2>/dev/null | cut -f3 | sort -u | wc -l)
    remaining=$((total_genomes - already_done))
    echo "Already processed: $already_done"
    echo "Remaining to process: $remaining"
else
    echo "Force mode: Will re-process all genomes"
fi
echo ""

# Prepare force flag for script
FORCE_FLAG=""
if [ "$FORCE" = true ]; then
    FORCE_FLAG="-f"
fi

# Clear previous failure logs
> "$FAILED_LOG"
> "$CORRUPTED_LOG"

# Run annotation in parallel using rush
echo "Starting annotation..."
start_time=$(date +%s)

# Fixed rush command - removed incorrect -v usage
find "$GENOME_DIR" -name "*.fa.gz" | \
    rush --eta -j "$PARALLEL_JOBS" -c \
    "python ./annotate_genomes.py {} -o $OUTPUT_DIR -l $LOG_FILE $FORCE_FLAG || echo {} >> $FAILED_LOG"

end_time=$(date +%s)
duration=$((end_time - start_time))

echo ""
echo "=== Annotation Complete ==="
echo "Total runtime: $duration seconds"

# Generate summary
success_count=$(grep "SUCCESS" "$LOG_FILE" | wc -l)
failed_count=$(grep "FAILED" "$LOG_FILE" | wc -l)
corrupted_count=$(grep "Corrupted or incomplete gzip" "$LOG_FILE" | wc -l)
total_genes=$(grep "SUCCESS" "$LOG_FILE" | awk -F'\t' '{print $4}' | grep -o "[0-9]*" | awk '{sum+=$1} END {print sum+0}')

echo ""
echo "Statistics:"
echo "-----------"
echo "Total genomes found: $total_genomes"
echo "Successfully annotated: $success_count"
echo "Failed: $failed_count"
echo "Corrupted/incomplete files: $corrupted_count"
if [ $success_count -gt 0 ]; then
    avg_genes=$((total_genes / success_count))
    echo "Total genes predicted: $total_genes"
    echo "Average genes per genome: $avg_genes"
fi
echo ""
echo "Output location: $OUTPUT_DIR/"
echo "Log file: $LOG_FILE"

if [ -f "$FAILED_LOG" ] && [ -s "$FAILED_LOG" ]; then
    echo "Failed genomes list: $FAILED_LOG"
fi

# Extract corrupted files to separate log
if [ $corrupted_count -gt 0 ]; then
    grep "Corrupted or incomplete gzip" "$LOG_FILE" | cut -f3 > "$CORRUPTED_LOG"
    echo "Corrupted files list: $CORRUPTED_LOG"
    echo ""
    echo "⚠ Note: $corrupted_count genome files appear to be incomplete."
    echo "  These may still be downloading. Re-run this script after downloads complete."
fi

# Create summary file
cat > annotation_summary.txt << SUMMARY
Annotation Summary
==================
Date: $(date)
Runtime: $duration seconds
Genome directory: $GENOME_DIR
Output directory: $OUTPUT_DIR

Statistics:
-----------
Total genomes found: $total_genomes
Successfully annotated: $success_count
Failed (processing errors): $failed_count
Corrupted/incomplete files: $corrupted_count
Total genes predicted: $total_genes
$([ $success_count -gt 0 ] && echo "Average genes per genome: $avg_genes")

Output files per genome:
- .gff : Gene coordinates and annotations
- .fna : Gene nucleotide sequences
- .faa : Protein sequences (amino acids)

Files:
------
Log file: $LOG_FILE
Failed genomes: $FAILED_LOG
Corrupted genomes: $CORRUPTED_LOG
SUMMARY

cat annotation_summary.txt

# Suggest next steps if there are corrupted files
if [ $corrupted_count -gt 0 ]; then
    echo ""
    echo "Suggested next steps:"
    echo "  1. Wait for downloads to complete"
    echo "  2. Re-run: $0 $GENOME_DIR"
    echo "  3. Script will automatically skip already-processed genomes"
fi


