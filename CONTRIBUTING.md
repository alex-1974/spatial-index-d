# Contributing to spatial-index-d

Normal development and pull requests target `develop`. The `main` branch
holds qualified states; release tags are created only after release gates pass.

Read `AGENTS.md`, `DESIGN_PRINCIPLES.md`, `ROADMAP.md`, relevant ADRs and
available canonical `.workspace/` documents before changing contracts.

## Focus

- Keep the index independent of any coordinate reference system, OSM schema,
  GUI, renderer or particular geometry library.
- Make payload ownership, node ownership, handle validity and update behaviour
  explicit before exposing them as public API.
- Do not require extra packages without a demonstrated consumer need.
- Preserve reproducible results and correctness across insertion histories.
- Include small regression tests for bugs; add realistic benchmarks only when
  they can decide between concrete implementation strategies.
- Use `@safe`, `@nogc`, `nothrow` and `pure` where genuinely supported, not
  to conceal necessary allocations or unsafe ownership.

## Local checks

```sh
dub test --compiler=dmd --force
dub test --compiler=ldc2 --force
dub build --build=release --compiler=ldc2 --force
(cd tests/consumer && dub run --compiler=dmd --force)
(cd tests/consumer && dub run --compiler=ldc2 --force)
git diff --check
```

Minimum frontend: D 2.111.0. The controlled release matrix is documented in
`.github/workflows/release-gate.yml`. DUB 1.40.0 is used in controlled CI.

Do not commit local `.workspace/`, generated documentation or build outputs.
