import sys
import gzip
import pyrodigal

def main():
    if len(sys.argv) != 5:
        print("Usage: annotate_genome.py <genome_path> <gff_out> <dna_out> <aa_out>", file=sys.stderr)
        sys.exit(1)
    
    genome_path = sys.argv[1]
    gff_out = sys.argv[2]
    dna_out = sys.argv[3]
    aa_out = sys.argv[4]
    
    genome_id = genome_path.split('/')[-1].replace('.fa.gz', '')
    
    try:
        # Read genome
        if genome_path.endswith('.gz'):
            with gzip.open(genome_path, 'rt') as f:
                sequence_data = f.read()
        else:
            with open(genome_path, 'r') as f:
                sequence_data = f.read()
        
        # Parse FASTA
        sequences = {}
        current_header = None
        current_seq = []
        
        for line in sequence_data.strip().split('\n'):
            if line.startswith('>'):
                if current_header:
                    sequences[current_header] = ''.join(current_seq)
                current_header = line[1:].split()[0]
                current_seq = []
            else:
                current_seq.append(line.strip())
        
        if current_header:
            sequences[current_header] = ''.join(current_seq)
        
        if not sequences:
            print(f"ERROR: No sequences found in {genome_path}", file=sys.stderr)
            sys.exit(1)
        
        # Initialize Pyrodigal
        orf_finder = pyrodigal.GeneFinder(meta=False)
        
        # Train
        if len(sequences) == 1:
            training_seq = list(sequences.values())[0]
        else:
            training_seq = ''.join(sequences.values())
        
        orf_finder.train(training_seq.encode())
        
        # Write outputs
        with open(gff_out, 'w') as gff_f, \
             open(dna_out, 'w') as dna_f, \
             open(aa_out, 'w') as aa_f:
            
            gff_f.write("##gff-version 3\n")
            
            gene_counter = 1
            
            for seq_id, seq in sequences.items():
                genes = orf_finder.find_genes(seq.encode())
                
                for gene in genes:
                    gene_id = f"{genome_id}_{gene_counter:05d}"
                    
                    # GFF
                    gff_f.write(f"{seq_id}\tPyrodigal\tCDS\t{gene.begin}\t{gene.end}\t"
                               f"{gene.score:.1f}\t{'+' if gene.strand == 1 else '-'}\t"
                               f"{gene.partial_begin}{gene.partial_end}\t"
                               f"ID={gene_id};partial={'1' if gene.partial_begin or gene.partial_end else '0'}\n")
                    
                    # DNA
                    dna_f.write(f">{gene_id} # {gene.begin} # {gene.end} # "
                               f"{'+' if gene.strand == 1 else '-'} # ID={seq_id}\n")
                    dna_f.write(f"{gene.sequence()}\n")
                    
                    # Protein
                    aa_f.write(f">{gene_id} # {gene.begin} # {gene.end} # "
                              f"{'+' if gene.strand == 1 else '-'} # ID={seq_id}\n")
                    aa_f.write(f"{gene.translate()}\n")
                    
                    gene_counter += 1
        
        print(f"SUCCESS: {genome_id} - {gene_counter - 1} genes")
        sys.exit(0)
        
    except Exception as e:
        print(f"ERROR: {genome_id}: {str(e)}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
