import argparse
import json

VERBOSE = False

def output(file, format):
    if format == 'tsv':
        return '\t'.join(str(dim) for dim in file['embedding']) + '\n'
    
    raise ValueError(f'Invalid output format {format}')

META_FIELDS = ['key', 'sysname', 'snapshot', 'text']
def meta_output(file, format):

    data = [file[field] for field in META_FIELDS ]
    if format == 'tsv':
        return '\t'.join(str(field).replace('\n', '\\n').replace('\t','\\t') for field in data) + '\n'
    
    raise ValueError(f'Invalid output format {format}')

def meta_header(format):
    if format == 'tsv':
        return '\t'.join(str(field) for field in META_FIELDS) + '\n'
    
    raise ValueError(f'Invalid output format {format}')



NAME_TOKEN = '<NAME>'
META_PREFIX = 'metadata-'

def main(filename, outfile_pattern, format):

    if NAME_TOKEN not in outfile_pattern:
        raise ValueError(f"Please include the token {NAME_TOKEN} in the output file pattern.")
    
    embed_handles = {}
    meta_handles = {}

    # clear out file

    with open(filename, 'r') as fin:
        for file in fin:
            data = json.loads(file)
            filename = data['filename'].split('/')[-1]

            # Emedding data
            if filename not in embed_handles:
                outfile_name = outfile_pattern.replace(NAME_TOKEN, filename)
                with open(outfile_name, 'w') as fout:
                    fout.write('') # clear
                embed_handles[filename] = open(outfile_name, 'a')
            
            # Metada
            if filename not in meta_handles:
                outfile_name = outfile_pattern.replace(NAME_TOKEN, META_PREFIX + filename)
                with open(outfile_name, 'w') as fout:
                    fout.write(meta_header(format)) # clear
                meta_handles[filename] = open(outfile_name, 'a')
            
            fout = embed_handles[filename]
            fout.write(output(data, format))

            fout_m = meta_handles[filename]
            fout_m.write(meta_output(data, format))
    
    for fout in embed_handles.values():
        fout.close()

    for fout_m in meta_handles.values():
        fout_m.close()

if __name__ == '__main__':

    parser = argparse.ArgumentParser(
                    prog='embeddingprojector',
                    description='Tools to ',
                    )
    
    parser.add_argument('-f', '--filename')      
    parser.add_argument('-o', '--out')      
    parser.add_argument('-g', '--format', default='tsv')      
    parser.add_argument('-v', '--verbose',
                        action='store_true')  
    
    args = parser.parse_args()

    if args.verbose:
        VERBOSE = args.verbose


    main(args.filename, args.out, args.format)