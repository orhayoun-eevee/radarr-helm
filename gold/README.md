# Gold File

This directory contains the "gold file" - a reference output of `helm template` that represents the expected Kubernetes manifests generated from the Helm chart.

## Purpose

The gold file serves as a baseline for tracking changes. When you modify `values.yaml` or chart templates, you can compare the new output against the gold file to see exactly what changed in the final manifests.

## Files

- `gold_file.yaml` - The reference Helm template output
- `generate_gold.sh` - Script to generate and test against the gold file

## Usage

### Test Mode (Default)

Compare current helm template output against the gold file:

```bash
cd gold
./generate_gold.sh test
# or simply
./generate_gold.sh
```

This will:
- Generate a temporary helm template output
- Compare it against `gold_file.yaml`
- Show differences if any exist
- Exit with code 0 if no differences, 1 if differences found

### Update Mode

Update the gold file with the current helm template output:

```bash
cd gold
./generate_gold.sh update
```

This will:
- Generate helm template output
- Overwrite `gold_file.yaml` with the new output
- Print a confirmation message

## Workflow

1. Make changes to `values.yaml` or chart templates
2. Run `./generate_gold.sh test` to see what changed
3. Review the differences
4. If the changes are correct, run `./generate_gold.sh update` to update the gold file
5. Commit both the changes and the updated gold file

## Benefits

- **Visual diff**: See exactly what manifests changed
- **Regression detection**: Catch unintended changes early
- **Documentation**: The gold file serves as documentation of the current state
- **CI/CD integration**: Can be used in automated testing pipelines
