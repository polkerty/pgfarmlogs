from openai import OpenAI
from dotenv import load_dotenv
import argparse
import json

from worker import run_jobs

load_dotenv()
client = OpenAI()

VERBOSE = False

def get_data(filename, count=None, match_names=None):

    if VERBOSE:
        print(f"Loading file {filename} with limit {count}")

    with open(filename, 'r') as f:
        data = json.load(f)

    # can't generate embeddings for empty strings;
    # just skip those files for now
    data = [file for file in data if len(file['text'])]

    if match_names:
        data = [file for file in data if file['filename'].split('/')[-1] in match_names]

    for i, file in enumerate(data):
        file['key'] = i 
    
    if count:
        data = data[:count]
    return data

def batch_files(data):
    chars_per_token = 2 # an estimate, for convenience
    limit_tokens = 8192
    batches = []
    batch = []
    running_token_count = 0
    for file in data:
        text = file['text']
        tokens = len(text)/chars_per_token

        if tokens > limit_tokens:
            # this should never happen based on the existing 
            # limit on file size. However, if the file suffixes
            # are too big, we can't compute embeddings for them at
            # all
            raise ValueError(f"File chunk at index {file['key']} too big to embed "
                             "- estimated {tokens} tokens is above the limit of {limit_tokens}")

        if running_token_count + tokens > limit_tokens:
            # flush the current batch
            batches.append(batch)
            batch = []
            running_token_count = 0

        batch.append(file)
        running_token_count += tokens

    batches.append(batch) # flush the last batch

    print(f"Generated {len(batches)} batches for {len(data)} files")

    return batches

def get_embeddings(batch):
    input = [file['text'] for file in batch]
    response = client.embeddings.create(
        input=input,
        model="text-embedding-3-large"
    )

    for i, embedding in enumerate(response.data):
        if VERBOSE:
            print(embedding)
        batch[i]['embedding'] = list(embedding.embedding)

def batch_get_embeddings(batches):
    by_batch = run_jobs(get_embeddings, batches, 10)
    return by_batch

def main(filename, out, count=None, match_names=None):
    data = get_data(filename, count, match_names)
    batches = batch_files(data)

    # modifies files in place
    batch_get_embeddings(batches)

    # clear file
    with open(out, 'w') as f:
        f.write('')

    # jsonl
    with open(out, 'a') as f:
        for file in data:
            f.write(json.dumps(file) + '\n')

if __name__ == '__main__':

    parser = argparse.ArgumentParser(
                    prog='pgfarmlogembeddings',
                    description='Generate embeddings of errors in the postgres build farm',
                    )
    
    parser.add_argument('-f', '--filename')      
    parser.add_argument('-o', '--out')      
    parser.add_argument('-n', '--match-names')      
    parser.add_argument('-c', '--count', type=int)      
    parser.add_argument('-v', '--verbose',
                        action='store_true')  
    
    args = parser.parse_args()

    match_names = None
    if args.match_names:
        match_names = args.match_names.split(',')

    if args.verbose:
        VERBOSE = args.verbose

    main(args.filename, args.out, args.count, match_names)