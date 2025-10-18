#!/bin/bash
# Merge multiple JSON files into one, filtering out files with error messages.

if [ $# -ne 1 ]; then
    echo "Usage: $0 <data_directory>"
    exit 1
fi

DATA_DIR="${1/#\~/$HOME}"

if [ ! -d "$DATA_DIR" ]; then
    echo "Error: Directory $DATA_DIR does not exist"
    exit 1
fi

OUTPUT_FILE="$DATA_DIR/all_roads.geojson"

# Remove existing output file to ensure clean start
if [ -f "$OUTPUT_FILE" ]; then
    rm -f "$OUTPUT_FILE"
    echo "Removed existing $OUTPUT_FILE"
fi

# Find all JSON and GeoJSON files
JSON_FILES=("$DATA_DIR"/*.json "$DATA_DIR"/*.geojson)

# Filter out glob patterns that didn't match
VALID_FILES=()
for file in "${JSON_FILES[@]}"; do
    if [ -f "$file" ]; then
        VALID_FILES+=("$file")
    fi
done

if [ ${#VALID_FILES[@]} -eq 0 ]; then
    echo "No JSON files found in $DATA_DIR"
    exit 1
fi

TOTAL_FILES=${#VALID_FILES[@]}
echo "Found $TOTAL_FILES JSON files"

PROCESSED=0
SKIPPED=0

for json_file in "${VALID_FILES[@]}"; do
    PROCESSED=$((PROCESSED + 1))
    filename=$(basename "$json_file")
    echo "[$PROCESSED/$TOTAL_FILES] Processing $filename..."

    # Check if file contains error message
    if head -n 1 "$json_file" | grep -q "Couldn't find the requested file"; then
        echo "  -> Skipped: Contains error message"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Append file content to output
    cat "$json_file" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "  -> Added"
done

echo ""
echo "Merged $((PROCESSED - SKIPPED)) files into $OUTPUT_FILE"
echo "Skipped $SKIPPED files"
