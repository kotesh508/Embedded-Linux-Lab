#!/bin/bash

OUTPUT="interview/Linux_Kernel_Interview_Reference.md"

echo "# Linux Kernel Interview Reference" > "$OUTPUT"
echo "" >> "$OUTPUT"

find . -type f -name "*.md" | while read file
do
    if grep -q "🧠 Interview Explanation" "$file"; then

        echo "--------------------------------------------------------" >> "$OUTPUT"
        echo "" >> "$OUTPUT"

        echo "## Source File" >> "$OUTPUT"
        echo "\`$file\`" >> "$OUTPUT"
        echo "" >> "$OUTPUT"

        awk '
        /🧠 Interview Explanation/ {flag=1}
        flag {print}
        /^📁 Related Files/ {flag=0}
        ' "$file" >> "$OUTPUT"

        echo "" >> "$OUTPUT"

    fi
done

echo "Done."
