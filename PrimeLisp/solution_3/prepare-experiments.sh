#!/bin/sh
set -eu
task_source=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
task_destination=${1:?Usage: prepare-experiments.sh DESTINATION}
task_solution="$task_source/PrimeLisp/solution_3"
task_commit=$(git -C "$task_source" rev-parse HEAD)
git -C "$task_source" ls-files --error-unmatch PrimeLisp/solution_3/run.sh >/dev/null
if ! git -C "$task_source" diff --quiet HEAD -- PrimeLisp/solution_3; then
    echo 'Commit the shared setup before creating the experiments.' >&2
    exit 1
fi
for task_method in batch interactive; do
    if [ -e "$task_destination/$task_method" ]; then
        echo "Already exists: $task_destination/$task_method" >&2
        exit 1
    fi
done
mkdir -p -- "$task_destination"
task_destination=$(CDPATH= cd -- "$task_destination" && pwd)
for task_method in batch interactive; do
    task_clone="$task_destination/$task_method"
    git clone --quiet --no-hardlinks "$task_source" "$task_clone"
    git -C "$task_clone" switch --quiet -c "experiment/$task_method" "$task_commit"
    if [ -f "$task_solution/.sbcl-path" ]; then
        cp "$task_solution/.sbcl-path" "$task_clone/PrimeLisp/solution_3/.sbcl-path"
    fi
    printf '%s\n' "$task_method" > "$task_clone/PrimeLisp/solution_3/.method"
    printf '%s: %s\n' "$task_method" "$task_clone/PrimeLisp/solution_3"
done
printf 'Common commit: %s\n' "$task_commit"
