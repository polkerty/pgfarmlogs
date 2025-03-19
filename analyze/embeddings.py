from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()
client = OpenAI()

def main():
    response = client.embeddings.create(
        input="hello!",
        model="text-embedding-3-large"
    )

    print(response.data[0].embedding)


if __name__ == '__main__':
    main()