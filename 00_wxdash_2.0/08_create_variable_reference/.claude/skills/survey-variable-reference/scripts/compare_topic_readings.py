"""Line up the first topic reading and three independent checks, row by row.

Usage:
    python3 compare_topic_readings.py <variable_reference.csv> <first.csv>
        <literalist.csv> <reader.csv> <skeptic.csv> <review_out.csv>

<first.csv> is the first reading: survey_hazard, variable, topic, topic_2,
check, reason. Each checker file is one checker's reading of the same rows:
survey_hazard, variable, topic, topic_2, alternative, confidence, reason.
Several surveys' files can be concatenated into one per reader first.

Every row gets one of five verdicts, from the four primary topics:

  unanimous             all four agree - settled
  current holds 3-1     the first reading and two checkers agree
  current outvoted 3-1  all three checkers agree on something else
  current leads 2-1-1   the first reading has the most votes, unshared
  split                 no single topic leads, or the first reading trails

Only `unanimous` rows are settled. The review file lists every other row with
its question and every reader's topic and reason side by side, outvoted and
split rows first. The summary also reports stems where several items were
contested the same way: that usually means a deciding rule is unclear, which
is worth fixing in topics.csv rather than row by row.

This script compares readings. It decides nothing.
"""

import collections
import csv
import sys

READERS = ["literalist", "reader", "skeptic"]
ORDER = ["current outvoted 3-1", "split", "current leads 2-1-1",
         "current holds 3-1"]


def load(path):
    return {(r["survey_hazard"], r["variable"]): r
            for r in csv.DictReader(open(path, newline=""))}


def main():
    if len(sys.argv) != 7:
        sys.exit(__doc__)
    sheet_path, first_path = sys.argv[1], sys.argv[2]
    checker_paths, out_path = sys.argv[3:6], sys.argv[6]

    sheet = load(sheet_path)
    first = load(first_path)
    checks = {name: load(p) for name, p in zip(READERS, checker_paths)}

    for name, rows in checks.items():
        missing = set(first) - set(rows)
        extra = set(rows) - set(first)
        if missing or extra:
            sys.exit("%s: %d rows missing, %d extra - every checker must "
                     "read exactly the rows the first reading covers."
                     % (name, len(missing), len(extra)))

    verdicts = collections.Counter()
    contested = []
    by_stem = collections.defaultdict(collections.Counter)
    for key, row in first.items():
        votes = [row["topic"]] + [checks[n][key]["topic"] for n in READERS]
        counts = collections.Counter(votes)
        top, n = counts.most_common(1)[0]
        leaders = [t for t, m in counts.items() if m == n]
        if n == 4:
            verdict = "unanimous"
        elif n == 3:
            verdict = ("current holds 3-1" if top == row["topic"]
                       else "current outvoted 3-1")
        elif len(leaders) == 1 and top == row["topic"]:
            verdict = "current leads 2-1-1"
        else:
            verdict = "split"
        verdicts[verdict] += 1
        if verdict == "unanimous":
            continue

        ref = sheet.get(key, {})
        stem = ref.get("question_intro", "")
        if stem:
            by_stem[(key[0], stem)][tuple(sorted(set(votes)))] += 1
        out = {
            "verdict": verdict,
            "survey_hazard": key[0],
            "variable": key[1],
            "majority": top if len(leaders) == 1 else " / ".join(sorted(leaders)),
            "first": row["topic"],
            "first_topic_2": row.get("topic_2", ""),
        }
        for name in READERS:
            out[name] = checks[name][key]["topic"]
        out["question_intro"] = stem
        out["question_text"] = ref.get("question_text", "")
        out["first_reason"] = row.get("reason", "")
        for name in READERS:
            c = checks[name][key]
            out[name + "_reason"] = "; ".join(
                x for x in [c.get("confidence", ""), c.get("reason", ""),
                            ("alt: " + c["alternative"])
                            if c.get("alternative") else ""] if x)
        out["decision"] = ""
        contested.append(out)

    contested.sort(key=lambda r: (ORDER.index(r["verdict"]),
                                  r["survey_hazard"], r["variable"]))
    fields = ["verdict", "survey_hazard", "variable", "majority", "first",
              "first_topic_2"] + READERS + [
        "question_intro", "question_text", "first_reason"] + [
        n + "_reason" for n in READERS] + ["decision"]
    with open(out_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader()
        w.writerows(contested)

    total = sum(verdicts.values())
    print("%d rows read four times" % total)
    for v in ["unanimous"] + ORDER:
        print("  %-22s %5d" % (v, verdicts[v]))
    patterns = [(k, s, n) for k, c in by_stem.items()
                for s, n in c.items() if n >= 3]
    if patterns:
        print("stems where 3+ items were contested the same way "
              "(check the deciding rules):")
        for (hazard, stem), topics, n in sorted(patterns, key=lambda p: -p[2]):
            print("  %s  %d items  %s\n      %s"
                  % (hazard, n, " vs ".join(topics), stem[:100]))
    print("review file: %s (%d rows to decide)" % (out_path, len(contested)))


if __name__ == "__main__":
    main()
