#!/bin/bash
# SBATCH directives (adjust % concurrency for your cluster limits)
#SBATCH --job-name=barrnap_ATB
#SBATCH --output=/users/3057556/jobs/ALB/barrnap_ALB_%A_%a.out
#SBATCH --error=/users/3057556/jobs/ALB/barrnap_ALB_%A_%a.err
#SBATCH --partition=k2-bioinf,k2-lowpri
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=10
#SBATCH --mem=16G
#SBATCH --time=200:00:00
#SBATCH --mail-user=n.dimonaco@qub.ac.uk
#SBATCH --mail-type=BEGIN,END,FAIL

set -euo pipefail

module load apps/anaconda3/2024.06/bin
source activate /mnt/scratch2/igfs-anaconda/conda-envs/barrnap_0.9

DATA_DIR=/mnt/scratch2/igfs-databases/AllTheBacteria/0.2
LIST_FILE=${DATA_DIR}/genomes.list    # create this ahead: find genomes -name '*.fa.gz' > genomes.list
OUT_DIR=${DATA_DIR}/16s_out
SCRATCH_BASE="/mnt/scratch2/users/3057556/DASA/tmp"
FILES_PER_TASK=${FILES_PER_TASK:-2000}   # adjust per-array job load



mkdir -p "${OUT_DIR}"
mkdir -p "${SCRATCH_BASE}"    # ensure scratch exists

# ---- validation & batch counting ----
if [[ ! -f "${LIST_FILE}" ]]; then
  echo "ERROR: LIST_FILE not found: ${LIST_FILE}" >&2
  exit 1
fi

total_genomes=$(wc -l < "${LIST_FILE}" | tr -d ' ')
if [[ "${total_genomes}" -eq 0 ]]; then
  echo "ERROR: LIST_FILE is empty: ${LIST_FILE}" >&2
  exit 1
fi

num_batches=$(( (total_genomes + FILES_PER_TASK - 1) / FILES_PER_TASK ))
echo "Total genomes: ${total_genomes}. Files per task: ${FILES_PER_TASK}. Num batches required: ${num_batches}."

# Auto-submit as a Slurm array if not already running in one
if [[ -z "${SLURM_ARRAY_TASK_ID:-}" ]]; then
  # avoid infinite resubmission loops: require sbatch and positive num_batches
  if ! command -v sbatch >/dev/null 2>&1; then
    echo "SLURM_ARRAY_TASK_ID is not set and sbatch not found. Submit manually with: sbatch --array=1-${num_batches}%200 ${BASH_SOURCE[0]}" >&2
    exit 1
  fi
  if (( num_batches <= 0 )); then
    echo "No batches to submit (num_batches=${num_batches}). Exiting." >&2
    exit 1
  fi

  # try to determine cluster MaxArraySize to avoid invalid --array ranges
  max_array_size=1000   # fallback default
  if command -v scontrol >/dev/null 2>&1; then
    parsed=$(scontrol show config 2>/dev/null | sed -n 's/.*MaxArraySize *= *\([0-9]*\).*/\1/p' | head -n1 || true)
    if [[ -n "${parsed}" && "${parsed}" =~ ^[0-9]+$ ]]; then
      max_array_size=${parsed}
    fi
  fi

  if (( max_array_size < 1 )); then
    max_array_size=1000
  fi

  echo "SLURM_ARRAY_TASK_ID is not set. Auto-submitting ${BASH_SOURCE[0]} as array(s) covering 1-${num_batches} with max array chunk ${max_array_size} (preferred concurrency %200)." >&2

  # export a marker to help avoid accidental loops
  export _AUTO_SUBMIT=1

  # submission helper that tries various fallbacks on failure
  submit_range() {
    local start=$1 end=$2
    local try_chunk="$3"   # human-readable for logs
    local conc_str="$4"    # either "%200" or ""
    local out status

    echo "Attempting sbatch --array=${start}-${end}${conc_str} ${BASH_SOURCE[0]}" >&2
    out=$(sbatch --array=${start}-${end}${conc_str} --export=ALL "${BASH_SOURCE[0]}" 2>&1) && status=0 || status=$?
    if (( status == 0 )); then
      echo "Submitted range ${start}-${end}${conc_str}: ${out}" >&2
      return 0
    fi

    echo "sbatch failed for range ${start}-${end}${conc_str}: ${out}" >&2

    # if sbatch error mentions invalid array spec, indicate caller to try fallback
    if echo "${out}" | grep -qi "Invalid job array specification"; then
      return 2
    fi

    # otherwise propagate non-recoverable failure
    return 1
  }

  start=1
  # initial chunk guess: don't exceed both num_batches and max_array_size
  chunk=$(( max_array_size < num_batches ? max_array_size : num_batches ))

  while (( start <= num_batches )); do
    end=$(( start + chunk - 1 ))
    if (( end > num_batches )); then end=${num_batches}; fi

    # Try sequence of fallbacks:
    # 1) preferred: include concurrency %200
    # 2) try without concurrency if invalid spec
    # 3) reduce chunk to 100, then 10, then 1 and retry (with and without concurrency)
    if submit_range "${start}" "${end}" "${chunk}" "%200"; then
      : # success, nothing more
    else
      rc=$?
      if (( rc == 2 )); then
        # invalid spec: try without concurrency first
        if submit_range "${start}" "${end}" "${chunk}" ""; then
          :
        else
          rc2=$?
          # If still invalid or failed, attempt smaller chunk sizes
          smaller_attempted=0
          for new_chunk in 100 10 1; do
            if (( new_chunk >= chunk )); then
              continue
            fi
            smaller_attempted=1
            sub_end=$(( start + new_chunk - 1 ))
            if (( sub_end > num_batches )); then sub_end=${num_batches}; fi
            if submit_range "${start}" "${sub_end}" "${new_chunk}" "%200"; then
              # advance start to after sub_end and break to outer loop
              start=$(( sub_end + 1 ))
              break
            fi
            # if invalid spec, try without concurrency for this smaller chunk
            if submit_range "${start}" "${sub_end}" "${new_chunk}" ""; then
              start=$(( sub_end + 1 ))
              break
            fi
            # otherwise try next smaller chunk
          done

          if (( smaller_attempted == 1 && start > end )); then
            # we advanced inside the loop; continue outer while
            continue
          fi

          # if we didn't advance, check last rc2: if non-recoverable failure, abort
          if (( rc2 != 2 )); then
            echo "ERROR: sbatch failed with non-recoverable error while submitting ${start}-${end}. Aborting." >&2
            echo "Last sbatch output: ${out}" >&2
            exit 1
          fi

          # if we reach here and didn't submit anything, fall through to abort
          echo "ERROR: unable to submit any valid array chunk for start=${start}. Aborting." >&2
          echo "Try manually: sbatch --array=1-${num_batches}%200 ${BASH_SOURCE[0]}" >&2
          exit 1
        fi
      else
        echo "ERROR: sbatch failed for ${start}-${end} with unexpected error. Aborting." >&2
        echo "Last sbatch output: ${out}" >&2
        exit 1
      fi
    fi

    # if we reached here and submission succeeded for the full chunk, advance
    start=$(( end + 1 ))
    # be polite to the scheduler when issuing many submissions
    sleep 0.2
  done

  exit 0
fi

# if array task id present, ensure it's within range
if (( SLURM_ARRAY_TASK_ID > num_batches )); then
  echo "SLURM_ARRAY_TASK_ID (${SLURM_ARRAY_TASK_ID}) > num_batches (${num_batches}). Nothing to do for this index." >&2
  exit 0
fi
# ---- end validation ----

# ensure barrnap is available
if ! command -v barrnap >/dev/null 2>&1; then
  echo "ERROR: barrnap not found in PATH. Exiting." >&2
  exit 1
fi

# compute chunk indices for this array task
start=$(( (SLURM_ARRAY_TASK_ID - 1) * FILES_PER_TASK + 1 ))
end=$(( SLURM_ARRAY_TASK_ID * FILES_PER_TASK ))

# read assigned lines safely
mapfile -t files < <(sed -n "${start},${end}p" "${LIST_FILE}" || true)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No files assigned to this task (start=${start}, end=${end}). Exiting."
  exit 0
fi

# track current workdir for cleanup on unexpected exit
workdir=""
trap 'if [[ -n "${workdir}" && -d "${workdir}" ]]; then rm -rf "${workdir}"; fi' EXIT

for i in "${files[@]}"; do
  # trim whitespace and remove CR which can come from Windows-formatted files
  i="$(echo -n "${i}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [[ -z "$i" ]]; then continue; fi
  echo "$(date --iso-8601=seconds) Processing: $i" >&2

  # derive base name robustly and strip common extensions
  base=$(basename "$i")
  # remove CR/whitespace again just in case
  base="${base//$'\r'/}"
  base="$(echo -n "${base}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  # strip known extensions reliably
  for ext in ".fa.gz" ".fna.gz" ".fasta.gz" ".fna" ".fa" ".fasta" ".gz"; do
    if [[ "${base}" == *"${ext}" ]]; then
      base="${base%${ext}}"
    fi
  done

  # ensure no leftover path components and replace any slashes/unsafe chars
  base="${base##*/}"
  base="${base//\//_}"
  base="$(echo -n "${base}" | sed 's/[^A-Za-z0-9._-]/_/g')"

  # final fallback
  if [[ -z "${base}" ]]; then
    base="sample_${RANDOM}"
  fi

  # resolve input path: prefer the exact path, then DATA_DIR/<path>, then DATA_DIR/<basename>
  src="${i}"
  if [[ ! -e "${src}" ]]; then
    if [[ -e "${DATA_DIR}/${i}" ]]; then
      src="${DATA_DIR}/${i}"
    elif [[ -e "${DATA_DIR}/$(basename "${i}")" ]]; then
      src="${DATA_DIR}/$(basename "${i}")"
    fi
  fi

  # debug: show sanitized base and final paths (include resolved source)
  out_fa="${OUT_DIR}/${base}_16S.fasta.gz"
  out_gff="${OUT_DIR}/${base}_16S.gff.gz"
  echo "DEBUG: sanitized base='${base}', src='${src}', out_fa='${out_fa}', out_gff='${out_gff}'" >&2

  # always write directly under OUT_DIR (do not create per-sample subdirs)
  # skip if outputs already present (resume)
  if [[ -s "${out_fa}" && -s "${out_gff}" ]]; then
    echo "$(date --iso-8601=seconds) SKIP: outputs exist for ${base}" >&2
    continue
  fi

  # prepare per-sample temp dir
  workdir=$(mktemp -d "${SCRATCH_BASE}/${base}_barrnap_XXXX")
  if [[ ! -d "${workdir}" ]]; then
    echo "$(date --iso-8601=seconds) ERROR: failed to create workdir for ${base}" >&2
    workdir=""
    continue
  fi

  # decompress or copy to temp fasta (handle gz and plain files) using resolved src
  tmp_fa="${workdir}/${base}.fa"
  if [[ "${src}" == *.gz ]]; then
    if ! gunzip -c "${src}" > "${tmp_fa}"; then
      echo "$(date --iso-8601=seconds) ERROR: failed to decompress ${src}" >&2
      rm -rf "${workdir}"; workdir=""; continue
    fi
  else
    if ! cp -v "${src}" "${tmp_fa}"; then
      echo "$(date --iso-8601=seconds) ERROR: failed to copy ${src}" >&2
      rm -rf "${workdir}"; workdir=""; continue
    fi
  fi

  threads=${SLURM_CPUS_PER_TASK:-10}
  # run barrnap; write sequence to file and GFF to file
  if ! barrnap --kingdom bac --threads "${threads}" --outseq "${workdir}/${base}_16S.fasta" "${tmp_fa}" > "${workdir}/${base}_16S.gff"; then
    echo "$(date --iso-8601=seconds) ERROR: barrnap failed for ${base}" >&2
    rm -rf "${workdir}"; workdir=""; continue
  fi

  # compress outputs atomically (ensure OUT_DIR exists)
  mkdir -p "${OUT_DIR}"
  if [[ -f "${workdir}/${base}_16S.fasta" ]]; then
    gzip -c "${workdir}/${base}_16S.fasta" > "${out_fa}.tmp" && mv -f "${out_fa}.tmp" "${out_fa}"
  fi
  if [[ -f "${workdir}/${base}_16S.gff" ]]; then
    gzip -c "${workdir}/${base}_16S.gff" > "${out_gff}.tmp" && mv -f "${out_gff}.tmp" "${out_gff}"
  fi

  echo "$(date --iso-8601=seconds) DONE: outputs written for ${base}" >&2

  # per-iteration cleanup
  rm -rf "${workdir}"
  workdir=""
done

# end of script

