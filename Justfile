default:
    @just --list

sync:
    uv sync --all-packages --all-groups --all-extras

lint:
    zig fmt --check .
    zlint

fmt:
    zig fmt .

zigadd:
    cd python/zigadd && just clean build test

zigadd-wheel:
    cd python/zigadd && just wheel

zigzon:
    cd python/zigzon && just clean build test

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
    zig build docs -p docs {{python_include}}
    mdbook build

python_include := if env("ALLOCONDA_PYTHON_INCLUDE", "") != "" { "-Dpython-include=" + env("ALLOCONDA_PYTHON_INCLUDE") } else { "" }

docs-serve: docs
    mdbook serve

publish:
    uv build --package alloconda --clear
    twine check --strict dist/*
    twine upload --repository alloconda dist/*

clean:
    rm -rf dist/
    rm -rf zig-out/
    rm -rf .zig-cache/
    rm -rf python/hello_alloconda

hello:
    rm -rf python/hello_alloconda
    mkdir python/hello_alloconda
    uv init --no-pin-python python/hello_alloconda
    cd python/hello_alloconda && alloconda init
    cd python/hello_alloconda && alloconda develop
    python -c 'import hello_alloconda; print(hello_alloconda.hello("hello"))'

ci: clean sync lint-all zigadd zigzon zigzon-wheel hello
