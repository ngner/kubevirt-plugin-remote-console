#!/usr/bin/env bash

# Helper script to convert Console YAML configuration to JSON format
# Usage: ./yaml-to-json.sh [input-yaml-file] [output-json-file]
#
# Example:
#   ./yaml-to-json.sh policy-console-cluster-virt.yaml mock-console-cr.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="${1:-policy-console-cluster-virt.yaml}"
OUTPUT_FILE="${2:-mock-console-cr.json}"

# Resolve paths relative to script directory
if [[ "$INPUT_FILE" != /* ]]; then
    INPUT_FILE="${SCRIPT_DIR}/${INPUT_FILE}"
fi

if [[ "$OUTPUT_FILE" != /* ]]; then
    OUTPUT_FILE="${SCRIPT_DIR}/${OUTPUT_FILE}"
fi

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE" >&2
    exit 1
fi

# Function to convert using yq
convert_with_yq() {
    yq eval -o=json "$INPUT_FILE" > "$OUTPUT_FILE"
}

# Function to convert using Python
convert_with_python() {
    python3 << EOF
import json
import yaml
import sys

try:
    with open('$INPUT_FILE', 'r') as f:
        data = yaml.safe_load(f)
    with open('$OUTPUT_FILE', 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Successfully converted $INPUT_FILE to $OUTPUT_FILE")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# Function to convert using jq (requires yaml2json or similar)
convert_with_jq() {
    if command -v yaml2json >/dev/null 2>&1; then
        yaml2json < "$INPUT_FILE" | jq '.' > "$OUTPUT_FILE"
    else
        echo "Error: yaml2json not found. Please install yaml2json or use yq/Python." >&2
        return 1
    fi
}

# Try conversion methods in order of preference
echo "Converting $INPUT_FILE to $OUTPUT_FILE..."

if command -v yq >/dev/null 2>&1; then
    echo "Using yq..."
    convert_with_yq
elif python3 -c "import yaml, json" 2>/dev/null; then
    echo "Using Python (yaml + json modules)..."
    convert_with_python
elif command -v jq >/dev/null 2>&1 && command -v yaml2json >/dev/null 2>&1; then
    echo "Using jq + yaml2json..."
    convert_with_jq
else
    echo "Error: No suitable conversion tool found." >&2
    echo "Please install one of the following:" >&2
    echo "  - yq: https://github.com/mikefarah/yq" >&2
    echo "  - Python with PyYAML: pip install pyyaml" >&2
    echo "  - jq + yaml2json" >&2
    exit 1
fi

# Verify output file was created
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: Output file was not created: $OUTPUT_FILE" >&2
    exit 1
fi

echo "Conversion complete: $OUTPUT_FILE"


