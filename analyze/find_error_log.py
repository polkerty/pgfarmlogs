
import argparse
import json
import re
import string

VERBOSE=False

def get_data(filename):
    with open(filename, 'r') as f:
        data = json.load(f)
    return data    

def get_filenames(data):
    names = set()
    for file in data:
        end = file['filename'].split('/')[-1]
        names.add(end)

    return names


def filename_split(text):
    # 1. Split on either '/' or any whitespace.
    raw_tokens = re.split(r'[/\s]+', text)
    
    tokens = []
    for rt in raw_tokens:
        # 2. Strip leading/trailing punctuation, but not periods inside the token.
        stripped = rt.strip(string.punctuation)  
        if stripped:  # ignore empty results
            tokens.append(stripped)
    return tokens


def find_interesting_files(data, filenames, entrypoint):
    interesting = set([entrypoint])
    for file in data:
        if file['filename'] != entrypoint:
            continue

        words = filename_split(file['text'])

        if VERBOSE:
            print(words)

        for word in words:
            if word in filenames:
                interesting.add(word)

    return  list(interesting)

    

def main(filename, entrypoint):

    data = get_data(filename)

    filenames = get_filenames(data)

    interesting_files = find_interesting_files(data, filenames, entrypoint)

    for file in interesting_files:
        print(file)



if __name__ == '__main__':
    parser = argparse.ArgumentParser(
                prog='find_error_log',
                description='Determine which log files are sometimes referenced from the main log file.',
                )

    parser.add_argument('-f', '--filename', required=True)      
    parser.add_argument('-e', '--entrypoint', default='head')      
    parser.add_argument('-v', '--verbose', action='store_true')      
    args = parser.parse_args()

    if args.verbose:
        VERBOSE=True

    main(args.filename, args.entrypoint)