default:
    @just --list

sync:
    uv sync --all-packages

lint:
    zig fmt --check .
    zlint

fmt:
    zig fmt .

zigadd:
    cd python/zigadd && just build
    cd python/zigadd && just test

zigadd-wheel:
    cd python/zigadd && just wheel

zigzon:
    cd python/zigzon && just build
    cd python/zigzon && just test

zigzon-wheel:
    cd python/zigzon && just wheel

lint-all:
    just lint
    cd python/alloconda && just lint
    cd python/zigadd && just lint
    cd python/zigzon && just lint

fmt-all:
    just fmt
    cd python/alloconda && just fmt
    cd python/zigadd && just fmt
    cd python/zigzon && just fmt

docs:
    mdbook build

docs-serve:
    mdbook serve

publish:
    uv build --package alloconda --clear
    twine check --strict dist/*
    twine upload --repository alloconda dist/*

clean:
    rm -rf dist/
    rm -rf zig-out/
    rm -rf .zig-cache/
