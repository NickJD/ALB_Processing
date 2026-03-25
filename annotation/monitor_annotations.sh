#!/bin/bash

# Monitor annotation progress in real-time

LOG_FILE="${1:-annotation_log.tsv}"
REFRESH_INTERVAL=5  # seconds

if [ ! -f "$LOG_FILE" ]; then
    echo "Log file not found: $LOG_FILE"
    exit 1
fi

echo "Monitoring annotation progress (Ctrl+C to stop)"
echo "Refreshing every $REFRESH_INTERVAL seconds"
echo ""

while true; do
    clear
    echo "=== Pyrodigal Annotation Progress ==="
    echo "Last updated: $(date)"
    echo ""
    
    # Count statuses
    total=$(tail -n +2 "$LOG_FILE" | wc -l)
    success=$(grep -c "SUCCESS" "$LOG_FILE" || echo 0)
    failed=$(grep -c "FAILED" "$LOG_FILE" || echo 0)
    corrupted=$(grep -c "Corrupted" "$LOG_FILE" || echo 0)
    
    echo "Total processed: $total"
    echo "✓ Success: $success"
    echo "✗ Failed: $failed"
    echo "⚠ Corrupted/Incomplete: $corrupted"
    
    if [ $success -gt 0 ]; then
        total_genes=$(grep "SUCCESS" "$LOG_FILE" | awk -F'\t' '{print $4}' | grep -o "[0-9]*" | awk '{sum+=$1} END {print sum}')
        avg_genes=$((total_genes / success))
        echo ""
        echo "Total genes: $total_genes"
        echo "Avg genes/genome: $avg_genes"
    fi
    
    echo ""
    echo "Recent activity (last 10):"
    echo "-------------------------"
    tail -n 10 "$LOG_FILE" | column -t -s $'\t' | tail -n 10
    
    sleep $REFRESH_INTERVAL
done


