[default]
check: check-fmt test check-snapshot

alias ck := check

fmt:
    uvx mamushi -l 100 src/**/*.vy src/interfaces/*.vyi
    forge fmt

check-fmt:
    uvx mamushi -l 100 --check src/**/*.vy src/interfaces/*.vyi
    forge fmt --check

test:
    forge test

snapshot:
    forge snapshot

check-snapshot:
    forge snapshot --check
