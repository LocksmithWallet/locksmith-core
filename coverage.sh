forge coverage --report lcov --optimize --optimizer-runs 20000 --contracts src/ && genhtml lcov.info --branch-coverage --exclude stubs --output-dir coverage
