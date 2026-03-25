SIG_FILES=$(ls sourmash_sigs/*.sig)

while read genome_id; do
  echo "Extracting ${genome_id}..."
  sourmash sig extract \
    --include "${genome_id}" \
    ${SIG_FILES} \
    -o "tmp_extractions/${genome_id}.sig"
done < E_coli.list
