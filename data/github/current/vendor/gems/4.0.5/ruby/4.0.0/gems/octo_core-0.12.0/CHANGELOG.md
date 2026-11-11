# Changelog

## [0.12.0](https://github.com/github/gem-trove/compare/octo_core/v0.11.0...octo_core/v0.12.0) (2026-05-19)


### Features

* widen octo_core rack dependency to support Rack 3 ([#155](https://github.com/github/gem-trove/issues/155)) ([edae400](https://github.com/github/gem-trove/commit/edae400abead0db213d7aabeaa2afae2beb1c2a7))

## [0.11.0](https://github.com/github/gem-trove/compare/octo_core/v0.10.2...octo_core/v0.11.0) (2026-05-15)


### Features

* **octo_core:** upgrade faraday to 2.x ([#152](https://github.com/github/gem-trove/issues/152)) ([b68b465](https://github.com/github/gem-trove/commit/b68b465c2b66af96a16a71db80067e0df4dc144d))

## [0.10.2](https://github.com/github/gem-trove/compare/octo_core/v0.10.1...octo_core/v0.10.2) (2025-12-18)


### Bug Fixes

* tapioca compiler causing error ([#146](https://github.com/github/gem-trove/issues/146)) ([ac358a9](https://github.com/github/gem-trove/commit/ac358a98a9dab352d4bcfbfb9d3f24e6156a7343))

## [0.10.1](https://github.com/github/gem-trove/compare/octo_core/v0.10.0...octo_core/v0.10.1) (2025-12-17)


### Bug Fixes

* downgrade faraday and loosen strictness ([#144](https://github.com/github/gem-trove/issues/144)) ([0c67722](https://github.com/github/gem-trove/commit/0c67722252125cfa5c8e42ebd8135fdbe046d709))

## [0.10.0](https://github.com/github/gem-trove/compare/octo_core/v0.9.0...octo_core/v0.10.0) (2025-12-15)


### Features

* env base class, unique registration of env variables, configurable prefix ([#106](https://github.com/github/gem-trove/issues/106)) ([6d2d2d8](https://github.com/github/gem-trove/commit/6d2d2d8b75379d09eaaa4383009f076ed758de6c))


### Bug Fixes

* octo_core tests were failing on main ([#120](https://github.com/github/gem-trove/issues/120)) ([bac7113](https://github.com/github/gem-trove/commit/bac71136c973bb1df24ae04c52f3b5809659f5b0))

## [0.9.0](https://github.com/github/gem-trove/compare/octo_core/v0.8.0...octo_core/v0.9.0) (2025-03-25)


### Features

* add action and controller tags to stats middleware ([#111](https://github.com/github/gem-trove/issues/111)) ([8f35e03](https://github.com/github/gem-trove/commit/8f35e0324a6b60049f74dbc7f3918bc45f77b853))

## [0.8.0](https://github.com/github/gem-trove/compare/octo_core/v0.7.1...octo_core/v0.8.0) (2025-03-19)


### Features

* default service and env datadog tags ([#104](https://github.com/github/gem-trove/issues/104)) ([7eb7128](https://github.com/github/gem-trove/commit/7eb7128afc02c7d13b90831e478e19e56044818f))
* stats middleware ([#102](https://github.com/github/gem-trove/issues/102)) ([2d2dc75](https://github.com/github/gem-trove/commit/2d2dc75ac42eeb559ae8802bacc60f26d3292a4d))


### Bug Fixes

* update broken tests ([#101](https://github.com/github/gem-trove/issues/101)) ([7a6750f](https://github.com/github/gem-trove/commit/7a6750f3b288d5b21a333bb720edef4439a53086))

## [0.7.1](https://github.com/github/gem-trove/compare/octo_core/v0.7.0...octo_core/v0.7.1) (2025-03-18)


### Bug Fixes

* hmac handling goes in api module ([#98](https://github.com/github/gem-trove/issues/98)) ([baa140c](https://github.com/github/gem-trove/commit/baa140cb7d988813ffae995abf25a37c5acb7bf7))

## [0.7.0](https://github.com/github/gem-trove/compare/octo_core/v0.6.0...octo_core/v0.7.0) (2025-03-14)


### Features

* support integer values in OctoCore::Env ([#94](https://github.com/github/gem-trove/issues/94)) ([88fa1ee](https://github.com/github/gem-trove/commit/88fa1eeed1afd792db900dc2f4b4403332022aa1))


### Bug Fixes

* split HMAC controller functionality, fix env var references ([#96](https://github.com/github/gem-trove/issues/96)) ([16b467e](https://github.com/github/gem-trove/commit/16b467e01a0486d8fd78e98db15ceab68d47ac35))

## [0.6.0](https://github.com/github/gem-trove/compare/octo_core/v0.5.0...octo_core/v0.6.0) (2025-03-10)


### Features

* AppEnvironment.qualified_app_name ([#93](https://github.com/github/gem-trove/issues/93)) ([0242f4a](https://github.com/github/gem-trove/commit/0242f4afa012cf2c83c876a8b3eb058397d48d5e))


### Bug Fixes

* boolean methods should have a question mark ([#91](https://github.com/github/gem-trove/issues/91)) ([681cae1](https://github.com/github/gem-trove/commit/681cae1b3b645e309fb5b03686b144e8743c751d))

## [0.5.0](https://github.com/github/gem-trove/compare/octo_core/v0.4.0...octo_core/v0.5.0) (2025-03-07)


### Features

* add tapioca compiler for `OctoCore::Env#define_env_variable` ([#81](https://github.com/github/gem-trove/issues/81)) ([9e939b0](https://github.com/github/gem-trove/commit/9e939b040b866481e7807b809f1acc204bbcf4a3))
* memory stats enhancements ([#87](https://github.com/github/gem-trove/issues/87)) ([cdf7d69](https://github.com/github/gem-trove/commit/cdf7d6970ca515dd0d9600c471bf509182499b32))
* output stats to an IO stream ([#88](https://github.com/github/gem-trove/issues/88)) ([5668f86](https://github.com/github/gem-trove/commit/5668f869068fb81568a57c36a7f58c6dd306b1f8))
* sensible datadog defaults ([#90](https://github.com/github/gem-trove/issues/90)) ([efe4bda](https://github.com/github/gem-trove/commit/efe4bda08defb4b8717ad75c24020f7d450c314a))

## [0.4.0](https://github.com/github/gem-trove/compare/octo_core/v0.3.0...octo_core/v0.4.0) (2025-03-06)


### Features

* Datadog stats reporting ([#82](https://github.com/github/gem-trove/issues/82)) ([9525244](https://github.com/github/gem-trove/commit/9525244696e6eff84c4254dab0c0310ee650c2cb))
* hmac request auth ([#74](https://github.com/github/gem-trove/issues/74)) ([7e3f9bc](https://github.com/github/gem-trove/commit/7e3f9bc8d1d2e9693a05ea91de44f37d642173c2))
* track missing env variables ([#79](https://github.com/github/gem-trove/issues/79)) ([748182e](https://github.com/github/gem-trove/commit/748182e5e1ec9e0d96cd0570de75502cd7516053))

## [0.3.0](https://github.com/github/gem-trove/compare/octo_core/v0.2.0...octo_core/v0.3.0) (2025-02-25)


### Features

* establish #deliver_error, bring runtime/env dependencies ([#20](https://github.com/github/gem-trove/issues/20)) ([347545c](https://github.com/github/gem-trove/commit/347545cffcfde64c87e9b86a6af1b46c8aeed332))

## [0.2.0](https://github.com/github/gem-trove/compare/octo_core-v0.1.0...octo_core/v0.2.0) (2025-02-24)


### Features

* add per_page validation ([#45](https://github.com/github/gem-trove/issues/45)) ([867a9ca](https://github.com/github/gem-trove/commit/867a9cae8c3922680d50e906cf209a5aad6b3bb5))
* allow dotcom test style, tags ([#29](https://github.com/github/gem-trove/issues/29)) ([b6c01c7](https://github.com/github/gem-trove/commit/b6c01c724418cb0555591cead871e4feeb5165c5))
* Centralize Faraday connection and HMAC middleware ([#44](https://github.com/github/gem-trove/issues/44)) ([6aeaaf0](https://github.com/github/gem-trove/commit/6aeaaf04d6aaa6b60d71ac09e533c68f5ea725c2))
* **octo_core:** add support for upper bound check on pagination ([#43](https://github.com/github/gem-trove/issues/43)) ([b413ae8](https://github.com/github/gem-trove/commit/b413ae87f2800136d210a442be144e0cd24f4cd1))


### Bug Fixes

* deprecation warnings and sig ([#61](https://github.com/github/gem-trove/issues/61)) ([3c420d1](https://github.com/github/gem-trove/commit/3c420d1201c09fb05148a2886f366c507a348d65))
* remove warnings around duplicate gem versions ([#48](https://github.com/github/gem-trove/issues/48)) ([96a38f2](https://github.com/github/gem-trove/commit/96a38f2578799ab2646f98fd8f8c2fd3e818ce86))


### Reverts

* "chore(main): release octo_core 0.2.0 ([#42](https://github.com/github/gem-trove/issues/42))" ([#55](https://github.com/github/gem-trove/issues/55)) ([2c99a9a](https://github.com/github/gem-trove/commit/2c99a9a5c89e4b0d25bdd1946fe6f66a1e2e0640))
* "chore(main): release octo_core 0.2.0" ([#58](https://github.com/github/gem-trove/issues/58)) ([b0ba51d](https://github.com/github/gem-trove/commit/b0ba51d71917e45d326346c5529fd29f7a48f7d6))
* "chore(main): release octo_core 0.2.0" ([#64](https://github.com/github/gem-trove/issues/64)) ([b634bde](https://github.com/github/gem-trove/commit/b634bdeccbfe0354832d352eaacbd2706ecc73d8))
