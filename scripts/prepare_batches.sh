#!/usr/bin/env bash
set -euo pipefail

# Usage: prepare_batches.sh <manifest.txt> <lines_per_batch> <out_dir>
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <manifest.txt> <lines_per_batch> <out_dir>"
  exit 1
fi

MANIFEST="$1"
LINES_PER_BATCH="$2"
OUT_DIR="$3"

mkdir -p "${OUT_DIR}"

total=$(wc -l < "${MANIFEST}" | tr -d ' ')
if [ "${total}" -eq 0 ]; then
  echo "Empty manifest: ${MANIFEST}"
  exit 1
fi

num_batches=$(( (total + LINES_PER_BATCH - 1) / LINES_PER_BATCH ))
# compute zero-pad width for batch numbering (enough digits for num_batches)
pad=${#num_batches}
# ensure minimum width to handle millions if needed
if [ "${pad}" -lt 7 ]; then pad=7; fi

# Use split to create temporary pieces then rename them
tmp_prefix="$(mktemp -u batchsplit_XXXX)"
split -l "${LINES_PER_BATCH}" -d -a ${pad} --additional-suffix=.txt "${MANIFEST}" "${OUT_DIR}/${tmp_prefix}"

# rename to genome_batch_0000001.txt style
i=1
for f in "${OUT_DIR}/${tmp_prefix}"*".txt"; do
  newname=$(printf "genome_batch_%0${pad}d.txt" "${i}")
  mv -v "${f}" "${OUT_DIR}/${newname}"
  i=$((i+1))
done

echo "Prepared ${num_batches} batch files in ${OUT_DIR} (pad=${pad})"
