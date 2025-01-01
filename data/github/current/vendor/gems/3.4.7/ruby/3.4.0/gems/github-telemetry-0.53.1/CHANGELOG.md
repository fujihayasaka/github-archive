# Changelog

## [0.53.1](https://github.com/github/github-telemetry-ruby/compare/v0.53.0...v0.53.1) (2025-07-08)


### Bug Fixes

* Faraday Instrumentation Defaults ([#694](https://github.com/github/github-telemetry-ruby/issues/694)) ([1ad8483](https://github.com/github/github-telemetry-ruby/commit/1ad8483e22b3458f3a4ad5983e39540dcadf8b92))

## [0.53.0](https://github.com/github/github-telemetry-ruby/compare/v0.52.0...v0.53.0) (2025-05-30)


### Features

* add RequestID propagator ([#631](https://github.com/github/github-telemetry-ruby/issues/631)) ([2ea9d5d](https://github.com/github/github-telemetry-ruby/commit/2ea9d5d3c3028b14d159216d3e859c591c11dc17))


### Miscellaneous Chores

* release 0.53.0 ([2de12e4](https://github.com/github/github-telemetry-ruby/commit/2de12e4706be30706e69ca70c369cad679d36c3d))

## [0.52.0](https://github.com/github/github-telemetry-ruby/compare/v0.51.1...v0.52.0) (2025-04-16)


### ⚠ BREAKING CHANGES

* Use cleansed backtrace instead of full message ([#672](https://github.com/github/github-telemetry-ruby/issues/672))

### Bug Fixes

* Use cleansed backtrace instead of full message ([#672](https://github.com/github/github-telemetry-ruby/issues/672)) ([8e3a26d](https://github.com/github/github-telemetry-ruby/commit/8e3a26d7c66c8a4366012131f1f55c2ab876ad56))

## [0.51.1](https://github.com/github/github-telemetry-ruby/compare/v0.51.0...v0.51.1) (2025-04-14)


### Bug Fixes

* Update appraisals for rails 7.1, 7.2. ([#673](https://github.com/github/github-telemetry-ruby/issues/673)) ([f4b1a84](https://github.com/github/github-telemetry-ruby/commit/f4b1a8474e116078546f2f7f82749f2a2e584cc1))
* Update pinned versions ([#675](https://github.com/github/github-telemetry-ruby/issues/675)) ([daa22a0](https://github.com/github/github-telemetry-ruby/commit/daa22a0c3a20ebd65c71335d3afea0c42d9b6361))

## [0.51.0](https://github.com/github/github-telemetry-ruby/compare/v0.50.1...v0.51.0) (2025-04-01)


### ⚠ BREAKING CHANGES

* remove span lookup hack with all its references ([#670](https://github.com/github/github-telemetry-ruby/issues/670))

### Bug Fixes

* remove span lookup hack with all its references ([#670](https://github.com/github/github-telemetry-ruby/issues/670)) ([bba176f](https://github.com/github/github-telemetry-ruby/commit/bba176ff78490a6e359d4a9ddadbb5f270857a3b))

## [0.50.1](https://github.com/github/github-telemetry-ruby/compare/v0.50.0...v0.50.1) (2025-03-04)


### Bug Fixes

* Unpin semantic-rails gems ([#659](https://github.com/github/github-telemetry-ruby/issues/659)) ([00e9bef](https://github.com/github/github-telemetry-ruby/commit/00e9bef7b05276f11f0c574c107fea407cb6f526))

## [0.50.0](https://github.com/github/github-telemetry-ruby/compare/v0.49.11...v0.50.0) (2025-02-12)


### ⚠ BREAKING CHANGES

* Remove support for Ruby 3.0; Require 'logger' explicitly [#655](https://github.com/github/github-telemetry-ruby/pull/655)

### Features

* Remove support for Ruby 3.0; Require 'logger' explicitly ([7e3b4e0](https://github.com/github/github-telemetry-ruby/commit/7e3b4e036242eaf8e8828d25a07d34a56b5c1ce7))
* Remove support for Ruby 3.0; Require 'logger' explicitly ([e404513](https://github.com/github/github-telemetry-ruby/commit/e4045136449f574fd939f3e417f57892aa51c8c2))
* Remove support for Ruby 3.0; Require 'logger' explicitly ([561146a](https://github.com/github/github-telemetry-ruby/commit/561146a0c5f8af74eb55102afd9982fd7f0ec781))
* Remove support for Ruby 3.0; Require 'logger' explicitly [[#655](https://github.com/github/github-telemetry-ruby/issues/655)](https://github.com/github/github-telemetry-ruby/pull/655) ([1d4c05d](https://github.com/github/github-telemetry-ruby/commit/1d4c05d7baff445bcd43a2e7d04cc6c692543ad6))
* Removes support for Ruby 3.0, which is now at EOL ([7e3b4e0](https://github.com/github/github-telemetry-ruby/commit/7e3b4e036242eaf8e8828d25a07d34a56b5c1ce7))
* Removes support for Ruby 3.0, which is now at EOL ([e404513](https://github.com/github/github-telemetry-ruby/commit/e4045136449f574fd939f3e417f57892aa51c8c2))
* Removes support for Ruby 3.0, which is now at EOL ([561146a](https://github.com/github/github-telemetry-ruby/commit/561146a0c5f8af74eb55102afd9982fd7f0ec781))


### Bug Fixes

* from repo-fixer ([#653](https://github.com/github/github-telemetry-ruby/issues/653)) ([8d45d3b](https://github.com/github/github-telemetry-ruby/commit/8d45d3b34dea94a437c5fee24c14ccfa9c0546d7))

## [0.49.11](https://github.com/github/github-telemetry-ruby/compare/v0.49.10...v0.49.11) (2024-12-12)


### Bug Fixes

* ArgumentError sample_rate ([#642](https://github.com/github/github-telemetry-ruby/issues/642)) ([a2f63bb](https://github.com/github/github-telemetry-ruby/commit/a2f63bb31982f10bec5c63a7af0eacc8b9147a43))

## [0.49.10](https://github.com/github/github-telemetry-ruby/compare/v0.49.9...v0.49.10) (2024-11-07)


### Performance Improvements

* Reduce the pending spans metrics ([#635](https://github.com/github/github-telemetry-ruby/issues/635)) ([a23860b](https://github.com/github/github-telemetry-ruby/commit/a23860baf5b10a2c110ee6141ecd739bb733988a))

## [0.49.9](https://github.com/github/github-telemetry-ruby/compare/v0.49.8...v0.49.9) (2024-09-18)


### Features

* pin sql-obfuscation and related gem versons; set high sql obfuscation limit ([204e5b4](https://github.com/github/github-telemetry-ruby/commit/204e5b483bf954533e012c62987d1eb627c79918))

## [0.49.8](https://github.com/github/github-telemetry-ruby/compare/v0.49.7...v0.49.8) (2024-07-31)


### Features

* make otlp exporter monkey patch always on ([5e3134f](https://github.com/github/github-telemetry-ruby/commit/5e3134f4c2072f4b4bd4a95bfe02940a0f2a532c))

## [0.49.7](https://github.com/github/github-telemetry-ruby/compare/v0.49.6...v0.49.7) (2024-07-18)


### Features

* monkeypatch otlp exporter to reconnect on 503 ([5c3d67c](https://github.com/github/github-telemetry-ruby/commit/5c3d67c69063847d6b7c202161b6728eb1b98d4c))

## [0.49.6](https://github.com/github/github-telemetry-ruby/compare/v0.49.5...v0.49.6) (2024-07-18)


### Bug Fixes

* pin rails_semantic_logger and semantic_logger gems to avoid bug in semanti_logger 4.16 ([#616](https://github.com/github/github-telemetry-ruby/issues/616)) ([6458912](https://github.com/github/github-telemetry-ruby/commit/6458912b0d5d9212d1e39bc8a7fb79b53e1fbc84))

## [0.49.5](https://github.com/github/github-telemetry-ruby/compare/v0.49.4...v0.49.5) (2024-06-17)


### Bug Fixes

* include net.peer.name in ethon spans ([#602](https://github.com/github/github-telemetry-ruby/issues/602)) ([b9186c7](https://github.com/github/github-telemetry-ruby/commit/b9186c73c277c82590a0938f5e654d167d61e96c))

## [0.49.4](https://github.com/github/github-telemetry-ruby/compare/github-telemetry-v0.49.3...github-telemetry/v0.49.4) (2024-06-13)


### Bug Fixes

* include net.peer.name in ethon spans ([#602](https://github.com/github/github-telemetry-ruby/issues/602)) ([b9186c7](https://github.com/github/github-telemetry-ruby/commit/b9186c73c277c82590a0938f5e654d167d61e96c))

## [0.48.0](https://github.com/github/github-telemetry-ruby/compare/v0.47.2...v0.48.0) (2023-12-13)


### Features

* Change default instrumentations ([#559](https://github.com/github/github-telemetry-ruby/issues/559)) ([cf4e84c](https://github.com/github/github-telemetry-ruby/commit/cf4e84cc1419c2df71eaad4430c25c1288683d68))
* Enable Pending Span Processor by default ([#562](https://github.com/github/github-telemetry-ruby/issues/562)) ([aba98be](https://github.com/github/github-telemetry-ruby/commit/aba98be204d4fe2a6a3f0af23eb6a039b13154da))
* Exception hack based on Java and .Net ([#545](https://github.com/github/github-telemetry-ruby/issues/545)) ([bb15096](https://github.com/github/github-telemetry-ruby/commit/bb15096b2cc934fe4ed2ba7f4fc47476d51a3474))


### Bug Fixes

* Handle Recursive Errors ([#569](https://github.com/github/github-telemetry-ruby/issues/569)) ([0623308](https://github.com/github/github-telemetry-ruby/commit/06233081bb5fe3879af276885bf2a9efb46735e8))

## Changelog

See [Releases](https://github.com/github/github-telemetry-ruby/releases)
