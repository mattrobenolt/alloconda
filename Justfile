default:
    @just --list

sync:
    uv sync --all-packages --all-groups --all-extras

lint:
    zig fmt --check .
    fd -e zig | zlint --stdin

fmt:
    zig fmt .

test: allotest-test

alloconda-test:
    cd python/alloconda && just test

allotest:
    cd python/allotest && just clean build test

allotest-wheel:
    cd python/allotest && just wheel

allotest-test:
    wheeltest allotest

zigzon:
    cd python/zigzon && just clean build test

zigzon-wheel:
    cd python/zigzon && just wheel

zigzon-test:
    wheeltest zigzon

e2e:
    cd python/zigzon && just e2e

lint-all:
    just lint
    cd python/alloconda && just lint
    cd python/allotest && just lint
    cd python/zigzon && just lint
    cd python/wheeltest && just lint
    cd python/fastproto && just lint

fmt-all:
    just fmt
    cd python/alloconda && just fmt
    cd python/allotest && just fmt
    cd python/zigzon && just fmt
    cd python/wheeltest && just fmt
    cd python/fastproto && just fmt

test-all:
    cd python/alloconda && just test
    cd python/allotest && just build test
    cd python/zigzon && just build test
    cd python/fastproto && just build test

docs:
    zig build docs -p docs {{ python_include }}
    mdbook build

python_include := if env("ALLOCONDA_PYTHON_INCLUDE", "") != "" { "-Dpython-include=" + env("ALLOCONDA_PYTHON_INCLUDE") } else { "" }

docs-serve: docs
    mdbook serve

publish:
    uv build --package alloconda --clear
    twine check --strict dist/*
    twine upload --repository alloconda dist/*

clean:
    fd -HI .wheeltest -t d -x rm -r
    fd -HI zig-out -t d -x rm -r
    fd -HI .zig-cache -t d -x rm -r
    fd -HI dist -t d -x rm -r
    rm -rf .venv/
    rm -rf python/hello_alloconda

hello:
    rm -rf python/hello_alloconda
    mkdir python/hello_alloconda
    uv init --no-pin-python python/hello_alloconda
    cd python/hello_alloconda && alloconda init
    cd python/hello_alloconda && alloconda develop
    python -c 'import hello_alloconda; print(hello_alloconda.hello("hello"))'

ci: clean sync lint-all alloconda-test test zigzon zigzon-wheel hello
