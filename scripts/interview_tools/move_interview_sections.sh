#!/bin/bash

set -e

# Must be run from repository root
if [ ! -d ".git" ]; then
    echo "Run this script from the repository root."
    exit 1
fi

OUTPUT="interview/Linux_Kernel_Interview_Reference.md"
BACKUP="interview_backup"

mkdir -p "$BACKUP"

echo "# Linux Kernel Interview Reference" > "$OUTPUT"
echo "" >> "$OUTPUT"

COUNT=0

find . -type f -name "*.md" \
    ! -path "./$BACKUP/*" \
    ! -path "./interview/Linux_Kernel_Interview_Reference.md" |
while read FILE
do
    if grep -q "🧠 Interview Explanation" "$FILE"; then

        COUNT=$((COUNT+1))

        echo "Processing: $FILE"

        mkdir -p "$BACKUP/$(dirname "$FILE")"
        cp "$FILE" "$BACKUP/$FILE"

        {
            echo ""
            echo "------------------------------------------------------------"
            echo ""
            echo "## $FILE"
            echo ""

            awk '
            /🧠 Interview Explanation/ {copy=1}
            /^📁 Related Files/ {copy=0}
            copy
            ' "$FILE"

            echo ""
        } >> "$OUTPUT"

        awk '
        BEGIN {skip=0}

        /🧠 Interview Explanation/ {skip=1}

        /^📁 Related Files/ {skip=0}

        !skip
        ' "$FILE" > "$FILE.tmp"

        mv "$FILE.tmp" "$FILE"

    fi
done

echo ""
echo "======================================"
echo "Interview reference created:"
echo "$OUTPUT"
echo ""
echo "Backup stored in:"
echo "$BACKUP"
echo "======================================"
