import argparse
import json

VERBOSE = False

def output(file, format):
    if format == 'tsv':
        return '\t'.join(str(dim) for dim in file['embedding']) + '\n'
    
    raise ValueError(f'Invalid output format {format}')

NAME_TOKEN = '<NAME>'

def main(filename, outfile_pattern, format):

    if NAME_TOKEN not in outfile_pattern:
        raise ValueError(f"Please include the token {NAME_TOKEN} in the output file pattern.")
    
    file_descriptors = {}

    # clear out file

    with open(filename, 'r') as fin:
        for file in fin:
            data = json.loads(file)
            filename = data['filename'].split('/')[-1]
            if filename not in file_descriptors:
                outfile_name = outfile_pattern.replace(NAME_TOKEN, filename)
                with open(outfile_name, 'w') as fout:
                    fout.write('') # clear
                file_descriptors[filename] = open(outfile_name, 'a')
            
            fout = file_descriptors[filename]
            fout.write(output(data, format))
    
    for fout in file_descriptors.values():
        fout.close()

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