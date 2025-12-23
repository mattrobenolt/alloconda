#!/usr/bin/env bash
set -euxo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <wheel> [wheel...]" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
dockerfile_src="$project_dir/docker/Dockerfile.smoke"
for wheel in "$@"; do
    if [[ ! -f "$wheel" ]]; then
        echo "wheel not found: $wheel" >&2
        exit 2
    fi

    wheel_abs="$(python -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$wheel")"
    wheel_name="$(basename "$wheel_abs")"

    if [[ "$wheel_name" != *"manylinux"* && "$wheel_name" != *"musllinux"* ]]; then
        echo "skipping non-linux wheel: $wheel_name" >&2
        continue
    fi

    platform_flag=""
    if [[ "$wheel_name" == *"aarch64"* ]]; then
        platform_flag="--platform=linux/arm64"
    elif [[ "$wheel_name" == *"x86_64"* ]]; then
        platform_flag="--platform=linux/amd64"
    fi

    python_image="${PYTHON_IMAGE:-python:3.14-slim}"
    if [[ "$wheel_name" =~ -cp([0-9]{2,3})- ]]; then
        tag="${BASH_REMATCH[1]}"
        env_name="PYTHON_IMAGE_CP${tag}"
        major="${tag:0:1}"
        minor="${tag:1}"
        python_image="${!env_name:-python:${major}.${minor}-slim}"
    fi

    (
        tmp_dir="$(mktemp -d)"
        trap 'rm -rf "$tmp_dir"' EXIT

        cp "$wheel_abs" "$tmp_dir/$wheel_name"
        cp "$project_dir/pyproject.toml" "$tmp_dir/pyproject.toml"
        cp -R "$project_dir/tests" "$tmp_dir/tests"
        cp "$dockerfile_src" "$tmp_dir/Dockerfile"

        image_tag="zigzon-wheel-smoke:${wheel_name//[^a-zA-Z0-9_.-]/_}"

        docker build $platform_flag \
            --build-arg PYTHON_IMAGE="$python_image" \
            -t "$image_tag" \
            "$tmp_dir"

        docker run --rm $platform_flag "$image_tag"
    )
done
