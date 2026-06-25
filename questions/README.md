# Questions — this pile's per-poll constitution

Each `questions/<source>/<poll>.json` is the **governing constitution** for one poll on this pile:
the question, its type, and the **guidance** that decides what passes. `bin/govern` matches every
incoming record (by its `source` + `poll`) to the file here and judges the answer against it. This is
*yours* — the pile-runner authors it, and **editing a file is a live patch**: the next `bin/govern`
run governs by the new text, and records which version it used (`constitution_sha` in the report).

The QR a respondent scanned may have *shown* its own question/guidance; that is a display copy carried
as `shown_guidance` for transparency. **This registry is what governs.** The two can differ — that is
the point: you can tighten or loosen the rule privately while a poll runs.

## Schema

```json
{
  "source": "tell",            // the Tell (feed source) that delivers this poll
  "poll": "dog-photo",         // poll id within that source
  "type": "open",              // "multichoice" | "open"
  "text": "Can I have a picture of your dog?",
  "options": [],               // multichoice only — the accepted answers
  "accept_writein": true,      // whether a non-option answer is even considered
  "guidance": "A jpg or png image of a dog. Joke/non-dog answers do not pass."
}
```

## How each answer is judged (`bin/govern`)

- **multichoice + answer is a listed option** → `accept`, mechanically (rule `auto`). No agent needed.
- **anything else** (a write-in, or any `open` answer) → handed to the **judge** (`bin/judge`, or your
  `DP_JUDGE_CMD`). The default judge applies cheap guards (empty → `reject`; write-in when
  `accept_writein:false` → `reject`) and otherwise returns **`needs-judgment`** — honest about the
  fact that an open answer against guidance is a call for a human or an agent, *work that can be done
  in parallel*. Plug a real judge into `DP_JUDGE_CMD` to resolve those.

Phrase the `text` as a **question** ("Can I have a picture of your dog?") and let `guidance` carry the
format/mood ("jpg/png", "joke answers only"). That primes the acceptance far better than a regex, and
covers pictures and templates.

Every run writes a transparency report to `reports/govern-<source>-<stamp>.json` with each verdict,
its reason, the `constitution_sha` in effect, and the signed `manifest_digest` it governed — so a
third party can tie *what was accepted* to *the rule in force* and *the signed delivery*.
