"""Write the rows that need topics as one readable packet per survey.

Usage:
    python3 prepare_topic_packets.py <variable_reference.csv> <out_dir>
        [--all] [--scale-items 05_scale_items.csv] [--measures measures.csv]
        [HAZARD ...]

By default a row needs a topic when it is a weather question
(question_focus = weather) whose `topics` cell is empty - the rows a new
instrument has just added. --all takes every weather row instead, for
re-reading the whole sheet after the topic list changes. Background rows are
never included: they are Background by rule.

Each packet, <out_dir>/<HAZARD>_questions.md, lists the rows grouped under
the stem they share, with each item's type, wording, response options and
show condition - everything a reader needs, and nothing that suggests an
answer.

The one exception is an item behind a mapped measure, whose topic is not a
reading but a rule: it takes the topic of its measure's construct, which
topics.csv (beside the sheet) declares in `measure_construct`. Given 05's
scale items and 09's measure menu, the packet marks those rows with the topic
they must have, so no reader spends judgment on them or argues them away.
This script assigns no other topics.
"""

import collections
import csv
import os
import sys


HAZARD_CODES = {"Severe Weather (WX)": "WX", "Tropical Cyclone (TC)": "TC",
                "Winter Weather (WW)": "WW", "Flooding (FL)": "FL"}


def option(args, flag):
    if flag not in args:
        return None
    i = args.index(flag)
    value = args[i + 1]
    del args[i:i + 2]
    return value


def fixed_topics(sheet_path, scale_items_path, measures_path):
    """(hazard, variable) -> (measure, topic) for items behind a measure."""
    topics_path = os.path.join(os.path.dirname(os.path.abspath(sheet_path)),
                               "topics.csv")
    construct = {r["measure_construct"]: r["topic"]
                 for r in csv.DictReader(open(topics_path, newline=""))
                 if r.get("measure_construct")}
    fixed = {}
    if scale_items_path:
        for r in csv.DictReader(open(scale_items_path, newline="")):
            name = r["measure"].split("_", 1)[1]
            if name not in construct:
                sys.exit("%s has no construct topic in topics.csv"
                         % r["measure"])
            key = (HAZARD_CODES.get(r["survey_hazard"], r["survey_hazard"]),
                   r["variable"])
            fixed[key] = (r["measure"], construct[name])
    risk = set()
    if measures_path:
        risk = {r["measure"].lower()
                for r in csv.DictReader(open(measures_path, newline=""))
                if r["measure"].startswith("RISK_")}
    return fixed, risk, construct.get("RISK")


def main():
    args = [a for a in sys.argv[1:]]
    if len(args) < 2:
        sys.exit(__doc__)
    take_all = "--all" in args
    args = [a for a in args if a != "--all"]
    scale_items_path = option(args, "--scale-items")
    measures_path = option(args, "--measures")
    sheet_path, out_dir = args[0], args[1]
    wanted = [h.upper() for h in args[2:]]
    os.makedirs(out_dir, exist_ok=True)
    fixed, risk, risk_topic = fixed_topics(sheet_path, scale_items_path,
                                           measures_path)

    rows = [
        r for r in csv.DictReader(open(sheet_path, newline=""))
        if r["question_focus"] == "weather"
        and (take_all or not r.get("topics", "").strip())
        and (not wanted or r["survey_hazard"].upper() in wanted)
    ]
    by_hazard = collections.defaultdict(list)
    for r in rows:
        by_hazard[r["survey_hazard"]].append(r)

    if not by_hazard:
        print("No rows need topics.")
        return

    for hazard, hazard_rows in by_hazard.items():
        groups = collections.OrderedDict()
        for r in hazard_rows:
            key = r["question_intro"] or "(no stem) " + r["variable"]
            groups.setdefault(key, []).append(r)
        path = os.path.join(out_dir, hazard + "_questions.md")
        with open(path, "w") as f:
            f.write("# %s survey: %d rows in %d groups\n\n"
                    % (hazard, len(hazard_rows), len(groups)))
            for i, (stem, items) in enumerate(groups.items(), 1):
                f.write("## Group %d\n" % i)
                if not stem.startswith("(no stem)"):
                    f.write("STEM: %s\n" % stem)
                for r in items:
                    f.write("- `%s` [%s] %s\n"
                            % (r["variable"], r["question_type"],
                               r["question_text"]))
                    if r["response_options"]:
                        f.write("    options: %s\n" % r["response_options"])
                    if r["asked_if"]:
                        f.write("    asked_if: %s\n" % r["asked_if"])
                    key = (r["survey_hazard"], r["variable"])
                    if key in fixed:
                        f.write("    MEASURE ITEM (%s): topic is fixed as %s\n"
                                % fixed[key])
                    elif r["variable"] in risk and risk_topic:
                        f.write("    MEASURE ITEM (%s): topic is fixed as %s\n"
                                % (r["variable"].upper(), risk_topic))
                f.write("\n")
        print("%s  %d rows in %d groups -> %s"
              % (hazard, len(hazard_rows), len(groups), path))


if __name__ == "__main__":
    main()
