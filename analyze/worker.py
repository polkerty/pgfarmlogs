from concurrent.futures import ThreadPoolExecutor

def run_jobs(fn, payloads, max_workers=5):
    results = [None] * len(payloads)
    progress = 0

    def run_and_store(i, args):
        try:
            return i, fn(args)
        except Exception as e:
            print(f"Error processing payload #{i}: {args}: {e}")
            return i, {"error": str(e)}

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(run_and_store, i, args) for i, args in enumerate(payloads)]

        for future in futures:
            i, result = future.result()
            results[i] = result
            errors = sum(1 for r in results if isinstance(r, dict) and "error" in r)
            progress += 1
            print(f"Progress: {progress}/{len(payloads)} | Errors: {errors}")

    return results
