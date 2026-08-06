"""Check a variable reference sheet against the instruments it came from.

Usage:
    python3 check_coverage.py <variable_reference.csv> <text_dir> [HAZARD ...]

Reports, per hazard:
  missing   a "name:" line in an instrument with no row in the sheet. Always a
            defect - go back and read that part of the document.
  extra     a row with no matching "name:" line. Legitimate for randomization
            variables, which appear only inside brackets, and for names the
            instrument writes without a space after the colon. Anything else
            needs explaining.

Exit status is 1 if anything is missing, so this can gate a build.
"""

import collections
import csv
import os
import re
import sys

NAME = re.compile(r"^([a-z][a-z0-9_]*|[A-Z][A-Z0-9_]*):")


def instrument_names(path):
    names = []
    for line in open(path):
        if "\t" not in line:
            continue
        text = line.split("\t", 1)[1].strip()
        match = NAME.match(text)
        if match:
            names.append(match.group(1))
    return names


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)

    sheet_path, text_dir = sys.argv[1], sys.argv[2]
    wanted = [h.upper() for h in sys.argv[3:]]

    documents = collections.defaultdict(set)
    for name in sorted(os.listdir(text_dir)):
        if not name.endswith(".txt"):
            continue
        hazard = name[:2].upper()
        documents[hazard].update(instrument_names(os.path.join(text_dir, name)))

    sheet = collections.defaultdict(set)
    for row in csv.DictReader(open(sheet_path)):
        sheet[row["survey_hazard"].upper()].add(row["variable"])

    failed = False
    for hazard in sorted(set(documents) | set(sheet)):
        if wanted and hazard not in wanted:
            continue
        missing = sorted(documents[hazard] - sheet[hazard])
        extra = sorted(sheet[hazard] - documents[hazard])
        print("%s  document %3d  sheet %3d  missing %d  extra %d"
              % (hazard, len(documents[hazard]), len(sheet[hazard]),
                 len(missing), len(extra)))
        if missing:
            failed = True
            print("    missing:", ", ".join(missing))
        if extra:
            print("    extra:  ", ", ".join(extra))

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
