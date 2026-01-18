#!/bin/bash
set -euo pipefail

MODE="${1:-test}"  # Default to test mode
TEMP_FILE=$(mktemp)

# Generate helm template (chart root is parent directory)
helm template radarr .. -f ../values.yaml --namespace media-center > "$TEMP_FILE"

if [ "$MODE" = "update" ]; then
    mv "$TEMP_FILE" gold_file.yaml
    echo "Updated gold_file.yaml"
elif [ "$MODE" = "test" ]; then
    if [ ! -f gold_file.yaml ]; then
        echo "Error: gold_file.yaml not found. Run with 'update' mode first."
        rm "$TEMP_FILE"
        exit 1
    fi
    if diff -u gold_file.yaml "$TEMP_FILE" > /dev/null; then
        echo "✓ No differences found. gold_file.yaml is up to date."
        rm "$TEMP_FILE"
        exit 0
    else
        echo "✗ Differences found between current template and gold_file.yaml:"
        diff -u gold_file.yaml "$TEMP_FILE" || true
        rm "$TEMP_FILE"
        exit 1
    fi
else
    echo "Usage: $0 [test|update]"
    rm "$TEMP_FILE"
    exit 1
fi
