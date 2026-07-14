#!/usr/bin/env python3

from pathlib import Path
import re
import shutil

repo = Path.cwd()

output = repo / "interview" / "Linux_Kernel_Interview_Reference.md"
backup = repo / "interview_backup_before_remove"

backup.mkdir(exist_ok=True)

pattern = re.compile(
    r'## 🧠 Interview Explanation\s*\n(.*?)\n---\s*\n',
    re.DOTALL
)

with output.open("w", encoding="utf-8") as out:
    out.write("# Linux Kernel Interview Reference\n\n")

    for md in sorted(repo.rglob("*.md")):

        if "interview_backup" in md.parts:
            continue

        if md == output:
            continue

        text = md.read_text(encoding="utf-8")

        m = pattern.search(text)

        if not m:
            continue

        print("Processing:", md)

        dst = backup / md.relative_to(repo)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(md, dst)

        out.write(f"=====================================================\n")
        out.write(f"FILE: {md}\n\n")
        out.write("## 🧠 Interview Explanation\n\n")
        out.write(m.group(1).strip())
        out.write("\n\n")

        new_text = pattern.sub("", text, count=1)

        md.write_text(new_text, encoding="utf-8")

print("\nDone.")
print("Interview reference:", output)
print("Backup:", backup)
