import argparse
import json

VERBOSE = False

def output(file, format):
    if format == 'tsv':
        return '\t'.join(str(dim) for dim in file['embedding']) + '\n'
    
    raise ValueError(f'Invalid output format {format}')

def main(filename, outfile, format):
    # clear out file
    with open(outfile, 'w') as fout:
        fout.write('')

    with open(filename, 'r') as fin:
        with open(outfile, 'a') as fout:
            for file in fin:
                data = json.loads(file)
                fout.write(output(data, format))

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