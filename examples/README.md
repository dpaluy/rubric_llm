# RubricLLM Examples

These examples are plain Ruby scripts for trying RubricLLM against live LLM-as-Judge calls. They are separate from the root
README so adoption examples can grow without making the main gem documentation noisy.

## Setup

Install dependencies from the project root:

```bash
bundle install
```

The examples below use OpenAI through RubyLLM. Set an API key before running them:

```bash
export OPENAI_API_KEY=...
```

Each script also wires `OPENAI_API_KEY` into `RubyLLM.configure(openai_api_key:)`, because RubyLLM expects provider keys on its
own configuration object.

## Judge vs Evaluated Model

RubricLLM does not call the model being evaluated. It scores answers that your app, prompt, model, or RAG pipeline already
produced.

- **Judge model**: the model configured in `RubricLLM.configure`, for example `gpt-4.1`. This model reads the question,
  answer, context, and ground truth, then returns scores.
- **Evaluated model/system**: the model, prompt, or application pipeline that produced the candidate answer. In these examples,
  evaluated answers are pre-generated candidate outputs; RubricLLM decides which ones pass or need review.

This separation is intentional. It lets you evaluate outputs from any source while keeping the judge model stable.

## Example Guide

All commands below should be run from the project root after `OPENAI_API_KEY` is available in the environment. You can either
export the key once or pass it inline:

```bash
OPENAI_API_KEY=... bundle exec ruby examples/llm_as_judge_rag.rb
```

### `llm_as_judge_rag.rb`

Run:

```bash
bundle exec ruby examples/llm_as_judge_rag.rb
```

What it does:

- Evaluates two pre-generated answers to the same RAG question.
- Uses `gpt-4.1` as the judge model.
- Labels the evaluated system as `acme-rag-v1`, but does not call that system.
- Sends each candidate answer through `faithfulness` and `correctness`.
- Prints each candidate's answer, per-metric scores, overall score, pass/review decision, and any judge-call errors.

The candidate inputs are stored as an array:

```ruby
candidate_answers = [
  { id: "candidate-a", answer: "..." },
  { id: "candidate-b", answer: "..." }
]
```

That shape is intentional. RubricLLM is not told which candidate is good or bad. The evaluator decides that from the answer,
context, ground truth, and metrics.

Use this example when you want the smallest practical RAG evaluation: one question, one context set, one ground truth answer,
and multiple candidate answers.

### `llm_as_judge_batch.rb`

Run:

```bash
bundle exec ruby examples/llm_as_judge_batch.rb
```

What it does:

- Evaluates a small dataset of three RAG samples.
- Uses the same two metrics as the single RAG example: `faithfulness` and `correctness`.
- Runs the batch with `concurrency: 2`.
- Prints every sample answer with a `PASS` or `FAIL` decision, then prints aggregate stats, failures, and the worst sample.

Each dataset row contains the fields RubricLLM needs for RAG judging:

```ruby
{
  question: "...",
  context: ["..."],
  ground_truth: "...",
  answer: "..."
}
```

The example includes two supported answers and one answer that contradicts the context. The failing machine-washing answer is
expected to score low because the context says not to machine-wash or tumble-dry the pack, while the answer says the opposite.

Use this example when you want to evaluate many saved outputs from the same application or prompt and inspect aggregate quality.

### `llm_as_judge_model_comparison.rb`

Run:

```bash
bundle exec ruby examples/llm_as_judge_model_comparison.rb
```

What it does:

- Compares two evaluated systems: `acme-rag-v1` and `acme-rag-v2`.
- Uses one stable judge model for both systems.
- Starts with paired samples where each question has a baseline answer and a candidate answer.
- Builds two datasets, evaluates each dataset, then calls `RubricLLM.compare`.
- Prints a baseline report, a candidate report, and an A/B comparison table.

The important idea is that the judge model stays fixed while the evaluated system changes. This lets you compare a baseline
prompt, model, retriever, or RAG pipeline against a candidate version without changing the scoring model.

Use this example when you want to decide whether a new prompt/model/pipeline version is better than the current one across the
same questions.

### `llm_as_judge_custom_metric.rb`

Run:

```bash
bundle exec ruby examples/llm_as_judge_custom_metric.rb
```

What it does:

- Defines a custom metric named `HelpfulSupportTone`.
- Evaluates two pre-generated support answers with that metric.
- Scores whether each answer is clear, concise, and professionally helpful.
- Prints the custom metric score, judge reasoning, and pass/review decision for each candidate.

The custom metric subclasses `RubricLLM::Metrics::Base`, defines a judge prompt, calls `judge_eval`, and normalizes the judge's
JSON response into:

```ruby
{
  score: Float(result["score"]).clamp(0.0, 1.0),
  details: { reasoning: result["reasoning"] }
}
```

This example is intentionally not a RAG correctness check. It evaluates support tone. A rude or dismissive answer should score
lower even if it contains some policy-relevant information.

Use this example when built-in metrics are not enough and you need a domain-specific rubric such as support quality, brand tone,
safety policy compliance, or instruction-following.

### `llm_as_judge_minitest.rb`

Run:

```bash
bundle exec ruby examples/llm_as_judge_minitest.rb
```

What it does:

- Shows how to use RubricLLM from Minitest.
- Includes `RubricLLM::Assertions`.
- Calls `assert_faithful` to check that the answer is supported by context.
- Calls `assert_correct` to check that the answer matches the ground truth.
- Fails the test if the live judge score is below the assertion threshold.

This is a live LLM-as-Judge smoke test, not an offline deterministic unit test. It is useful when you want a human-readable test
failure around an LLM output quality gate. For normal CI, keep in mind that it needs provider credentials, makes API calls, and
can vary by judge model/provider behavior.

Use this example when you want to wrap RubricLLM checks in familiar Ruby test assertions for manual smoke tests, release gates,
or controlled evaluation jobs.

## Reading Batch Output

`llm_as_judge_batch.rb` evaluates three pre-generated RAG answers with one judge model and two metrics:

- `faithfulness`: whether the answer is supported by the supplied context.
- `correctness`: whether the answer matches the supplied ground truth.

The evaluated system label, such as `acme-rag-v1`, is only a description of where the candidate answers came from. The script
does not call that system. It only passes the stored `question`, `context`, `ground_truth`, and `answer` values to RubricLLM.

The report summarizes each metric across the batch:

```text
faithfulness          mean=0.667  std=0.577  min=0.000  max=1.000  n=3
correctness           mean=0.667  std=0.577  min=0.000  max=1.000  n=3
```

In the bundled sample data, two answers are designed to be supported and correct, while the machine-washing answer contradicts
both the context and the ground truth. A common result is therefore scores like `[1.0, 0.0, 1.0]` for each metric:

```text
mean = (1.0 + 0.0 + 1.0) / 3 = 0.667
```

`overall` is computed per sample as the average of that sample's metric scores:

```text
overall = (faithfulness + correctness) / 2
```

The failure output includes the underlying scores so the overall score is explainable:

```text
Sample results:
1. PASS - What does the Acme Trail Pack warranty cover?
   scores: overall=1.00 (faithfulness=1.00, correctness=1.00)
   answer: The Acme Trail Pack has a lifetime warranty for manufacturing defects, excluding normal wear, misuse, and cosmetic damage.
2. FAIL - Can the Acme Trail Pack be machine-washed?
   scores: overall=0.00 (faithfulness=0.00, correctness=0.00)
   answer: Yes. The Acme Trail Pack can be machine-washed on a hot cycle and tumble-dried.
3. PASS - What is the Acme Trail Pack made from?
   scores: overall=1.00 (faithfulness=1.00, correctness=1.00)
   answer: It uses recycled nylon ripstop for the shell and recycled polyester for the lining.
```

The failures section repeats only the samples that did not pass:

```text
Failures below 0.80:
- Can the Acme Trail Pack be machine-washed?
  scores: overall=0.00 (faithfulness=0.00, correctness=0.00)
```

In that case, `overall=0.00` means the answer scored `0.00` for both metrics:

```text
overall = (0.00 + 0.00) / 2 = 0.00
```

The machine-washing answer appears under failures and as the worst sample because the example threshold is `0.80`.

These examples make provider API calls and may incur cost. Scores can vary by model and provider behavior. For smoke tests, look
for the relative behavior: stronger candidate outputs should pass, and weaker outputs should score lower and be flagged for
review.
