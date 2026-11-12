# Changelog

## [2.4.0](https://github.com/github/feature-management-client-go/compare/vexi/v2.3.0...vexi/v2.4.0) (2025-09-23)


### Features

* Added traces to vexi is enabled methods ([#528](https://github.com/github/feature-management-client-go/issues/528)) ([d784645](https://github.com/github/feature-management-client-go/commit/d78464556bec3959e92afd88aa68d86b9d9721d5))
* Updated the is enabled methods to call a common isEnabledWithDetails internal method and added method name tag to metrics ([#527](https://github.com/github/feature-management-client-go/issues/527)) ([016b1a0](https://github.com/github/feature-management-client-go/commit/016b1a0fb0691676b302c37a1ae8b6152a0c2aff))


### Bug Fixes

* Remove segment error span attribute ([#531](https://github.com/github/feature-management-client-go/issues/531)) ([087f38a](https://github.com/github/feature-management-client-go/commit/087f38a6a2d97ade06ef21413ed948bce78875f4))
* Rename trace attributes to follow otel conventions and add span kind ([#530](https://github.com/github/feature-management-client-go/issues/530)) ([efd2f36](https://github.com/github/feature-management-client-go/commit/efd2f364989b4abfdcc60baa33d9086c979959c0))
* Use vexi tracer interface on the hydro adapter ([#532](https://github.com/github/feature-management-client-go/issues/532)) ([23ee39d](https://github.com/github/feature-management-client-go/commit/23ee39ddb0bf7a2568e71f539289555a595de5c5))

## [2.3.0](https://github.com/github/feature-management-client-go/compare/vexi/v2.2.2...vexi/v2.3.0) (2025-09-22)


### Features

* Added experimental file based override hydro adapter for break glass overrides for the feature management team ([#402](https://github.com/github/feature-management-client-go/issues/402)) ([cb63567](https://github.com/github/feature-management-client-go/commit/cb63567e29b0a4c18847ef9c03d0f060a4c294f1))


### Bug Fixes

* **deps:** Bump github.com/IBM/sarama from 1.46.0 to 1.46.1 in /vexi in the vexi-packages group ([#523](https://github.com/github/feature-management-client-go/issues/523)) ([e9c424a](https://github.com/github/feature-management-client-go/commit/e9c424a2860647648c5c1120c8fae5c4dc583184))
* Update Tracer interface to be scoped to the methods we use to match go-server ([#525](https://github.com/github/feature-management-client-go/issues/525)) ([c7050c4](https://github.com/github/feature-management-client-go/commit/c7050c45a62afb9ca9cabeb14638011463ba9111))

## [2.2.2](https://github.com/github/feature-management-client-go/compare/vexi/v2.2.1...vexi/v2.2.2) (2025-09-17)


### Bug Fixes

* **deps:** Bump google.golang.org/protobuf from 1.36.8 to 1.36.9 in /vexi in the vexi-packages group ([#516](https://github.com/github/feature-management-client-go/issues/516)) ([462bd05](https://github.com/github/feature-management-client-go/commit/462bd05f7a5cd69fb95ee81d0482466a21659f6e))
* Remove Monolith Custom Gates Evaluator ([#520](https://github.com/github/feature-management-client-go/issues/520)) ([40dd6f7](https://github.com/github/feature-management-client-go/commit/40dd6f73f023779db98594986b6c85b5c1b413d2))

## [2.2.1](https://github.com/github/feature-management-client-go/compare/vexi/v2.2.0...vexi/v2.2.1) (2025-09-08)


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 2 updates ([#503](https://github.com/github/feature-management-client-go/issues/503)) ([a5c6e2e](https://github.com/github/feature-management-client-go/commit/a5c6e2e0ffb3a20069ff484ba2c05b5c3d89e894))
* **deps:** Bump the vexi-packages group in /vexi with 2 updates ([#506](https://github.com/github/feature-management-client-go/issues/506)) ([9e91c67](https://github.com/github/feature-management-client-go/commit/9e91c67bd008e92df22348027d67130fdefcdbc0))
* **deps:** Bump the vexi-packages group in /vexi with 2 updates ([#513](https://github.com/github/feature-management-client-go/issues/513)) ([eb21bcf](https://github.com/github/feature-management-client-go/commit/eb21bcf2c4594cf924a9584dfd9dcc030c39e134))
* **deps:** Bump the vexi-packages group in /vexi with 5 updates and update go version to 1.24.6 ([#510](https://github.com/github/feature-management-client-go/issues/510)) ([3a219b4](https://github.com/github/feature-management-client-go/commit/3a219b4690564f6e5018d647facc799c637ac584))

## [2.2.0](https://github.com/github/feature-management-client-go/compare/vexi/v2.1.1...vexi/v2.2.0) (2025-08-13)


### Features

* Added the all features enabled adapter ([#486](https://github.com/github/feature-management-client-go/issues/486)) ([faaafef](https://github.com/github/feature-management-client-go/commit/faaafef2951bbbd78bdfe5c77520b388c3d20c21))


### Bug Fixes

* **deps:** Bump github.com/github/feature-management-protos/gen/go/feature_management/feature_flags from 1.8.0 to 1.9.0 in /vexi in the vexi-packages group ([#495](https://github.com/github/feature-management-client-go/issues/495)) ([c2f6b72](https://github.com/github/feature-management-client-go/commit/c2f6b72dad1edd98745bf00606cf4fbd467baa0c))
* **deps:** Bump the vexi-packages group in /vexi with 2 updates ([#497](https://github.com/github/feature-management-client-go/issues/497)) ([e2b0399](https://github.com/github/feature-management-client-go/commit/e2b0399ee24a9388bd828dde79cbe720ef51cdac))
* **deps:** Bump the vexi-packages group in /vexi with 3 updates ([#488](https://github.com/github/feature-management-client-go/issues/488)) ([58efb06](https://github.com/github/feature-management-client-go/commit/58efb06c31554d152c6ed281104d3f76ef324f3e))

## [2.1.1](https://github.com/github/feature-management-client-go/compare/vexi/v2.1.0...vexi/v2.1.1) (2025-07-21)


### Bug Fixes

* **deps:** Bump golang.org/x/sync from 0.15.0 to 0.16.0 in /vexi in the vexi-packages group ([#478](https://github.com/github/feature-management-client-go/issues/478)) ([86462d0](https://github.com/github/feature-management-client-go/commit/86462d0f5a92bfe04b40cdd679e66f64dd900ccb))

## [2.1.0](https://github.com/github/feature-management-client-go/compare/vexi/v2.0.2...vexi/v2.1.0) (2025-07-17)


### Features

* Add support for the `shopify_members` custom group ([#476](https://github.com/github/feature-management-client-go/issues/476)) ([a728629](https://github.com/github/feature-management-client-go/commit/a728629ac4a3560b243d0b61b8ab6c5da51056a6))

## [2.0.2](https://github.com/github/feature-management-client-go/compare/vexi/v2.0.1...vexi/v2.0.2) (2025-07-14)


### Bug Fixes

* **deps:** Bump the vexi-packages group across 1 directory with 10 updates ([#474](https://github.com/github/feature-management-client-go/issues/474)) ([98eb05e](https://github.com/github/feature-management-client-go/commit/98eb05e19b5eb773bc80e60365a1e22891305b91))

## [2.0.1](https://github.com/github/feature-management-client-go/compare/vexi/v2.0.0...vexi/v2.0.1) (2025-07-08)


### Bug Fixes

* Account for nil actors ([#467](https://github.com/github/feature-management-client-go/issues/467)) ([df4f1b9](https://github.com/github/feature-management-client-go/commit/df4f1b92d8c9774e2ae385bce187b9fcc2f4e169))

## [2.0.0](https://github.com/github/feature-management-client-go/compare/vexi/v2.0.0-rc.3...vexi/v2.0.0) (2025-06-13)


### Bug Fixes

* Fix timestamp comparison logic in hydro adapter entity updaters ([#455](https://github.com/github/feature-management-client-go/issues/455)) ([b336e52](https://github.com/github/feature-management-client-go/commit/b336e526741b43f42a2210986b74379165ca2bd1))
* Update order of params in persistent host adapter init ([#453](https://github.com/github/feature-management-client-go/issues/453)) ([4ce746e](https://github.com/github/feature-management-client-go/commit/4ce746e4e7f739c510ee14daca0de28a00edde65))

## [2.0.0-rc.3](https://github.com/github/feature-management-client-go/compare/vexi/v2.0.0-rc.2...vexi/v2.0.0-rc.3) (2025-06-12)


### Bug Fixes

* Revamp error handling in vexi for ~10% performance boost and simpler public api service ([#449](https://github.com/github/feature-management-client-go/issues/449)) ([f2b8492](https://github.com/github/feature-management-client-go/commit/f2b84928d82909b280ab472a2690de92b368dad9))
* Updated adapter interface to simplify it ([#450](https://github.com/github/feature-management-client-go/issues/450)) ([ab0d245](https://github.com/github/feature-management-client-go/commit/ab0d245adce1ade6344f803a791dcd9bf805ac8e))
* Updated tombstone message rejection logging verbosity ([#448](https://github.com/github/feature-management-client-go/issues/448)) ([693cecf](https://github.com/github/feature-management-client-go/commit/693cecf614503671f1888c8c10ec9286160cc09d))

## [2.0.0-rc.2](https://github.com/github/feature-management-client-go/compare/vexi/v1.9.3...vexi/v2.0.0-rc.2) (2025-06-06)


### Features

* Add Resilient Start for `HydroAdapter` by @evgkarpov in https://github.com/github/feature-management-client-go/pull/377
* Skeleton for PersistentHydroAdapter by @takost in https://github.com/github/feature-management-client-go/pull/385
* Persistent file store by @cholick in https://github.com/github/feature-management-client-go/pull/394
* Add support for the `github_stars_members` custom group by @DanRigby in https://github.com/github/feature-management-client-go/pull/398
* return different error and set longer max backoff window by @camjamesjoy in https://github.com/github/feature-management-client-go/pull/409
* log cache updates by @camjamesjoy in https://github.com/github/feature-management-client-go/pull/403
* add readiness service to serializer and better tests by @camjamesjoy in https://github.com/github/feature-management-client-go/pull/408
* Remove un-needed data from sync maps by ignoring things that aren't for our service by @cholick in https://github.com/github/feature-management-client-go/pull/411
* get rid of timestamp cache and use updated at instead by @camjamesjoy in https://github.com/github/feature-management-client-go/pull/414
* Update fake adapter to be thread safe using xsync.MapOf by @thomasf7 in https://github.com/github/feature-management-client-go/pull/432
* Major version 2.0.0 by @ShreyasRmsft in https://github.com/github/feature-management-client-go/pull/443


### Bug Fixes

* Use random file name suffix for the tmp file to allow multiple instances to point to the same file cache by @ShreyasRmsft in https://github.com/github/feature-management-client-go/pull/424
* Add new telemetry and update existing telemetry to be more consistent by @ShreyasRmsft in https://github.com/github/feature-management-client-go/pull/435
* Added owning service filtering for persistent host hydro adapter by @ShreyasRmsft in https://github.com/github/feature-management-client-go/pull/438
* Skip parsing message in case of tombstones by @ShreyasRmsft in https://github.com/github/feature-management-client-go/pull/439
* Removed WithOwningService option on vexi by @ShreyasRmsft in https://github.com/github/feature-management-client-go/pull/445


## [1.9.3](https://github.com/github/feature-management-client-go/compare/vexi/v1.7.0...vexi/v1.9.3) (2025-05-16)


### Features

* Add support for the `microsoft_team_members` custom gate ([#380](https://github.com/github/feature-management-client-go/issues/380)) ([9e42cac](https://github.com/github/feature-management-client-go/commit/9e42cac997caa380a7ae58e041111b64e4e3f496))
* Add new constructors to ensure required parameters are explicitly passed ([#352](https://github.com/github/feature-management-client-go/issues/352)) ([149fc70](https://github.com/github/feature-management-client-go/commit/149fc7008b207026a5dee0e4e1f1f2fbcbf1ca63))
* Add sampling option for check metric ([#376](https://github.com/github/feature-management-client-go/issues/376)) ([93c0dfd](https://github.com/github/feature-management-client-go/commit/93c0dfd1604d1fd297c61bfd78321a9bdd5f10f8))
* Create new Vexi Client and Hydro Apapter constructors ([#335](https://github.com/github/feature-management-client-go/issues/335)) ([6b32c88](https://github.com/github/feature-management-client-go/commit/6b32c88b095f96a75db69cd8cbac7cbb802b7985))
* Add support for the `microsoft_team_members` custom gate by @DanRigby in https://github.com/github/feature-management-client-go/pull/380


### Bug Fixes

* Fixed race condition in cache readiness when high water marks is 1 ([#356](https://github.com/github/feature-management-client-go/issues/356)) ([fc7b5a7](https://github.com/github/feature-management-client-go/commit/fc7b5a73c2e60b6a867ff326a8f01f4dbf906731))
* Fix high memory usage when using vexi.WithSampling option for metrics in https://github.com/github/feature-management-client-go/commit/febdc57895e0b9a276cb90624c674807abbfb52e
* Fix unused time in https://github.com/github/feature-management-client-go/commit/a25251cb6493f8d86f619c2e6e0d84a2fa2451ff


## [1.7.0](https://github.com/github/feature-management-client-go/compare/vexi/v1.6.5...vexi/v1.7.0) (2025-03-17)


### Features

* Enable result reason tag on enabled checks ([#325](https://github.com/github/feature-management-client-go/issues/325)) ([8ae07cc](https://github.com/github/feature-management-client-go/commit/8ae07ccf760f5c3f838b29e0da976945fb42249a))


### Bug Fixes

* **deps:** Bump golang.org/x/net from 0.34.0 to 0.36.0 in /vexi in the go_modules group ([#337](https://github.com/github/feature-management-client-go/issues/337)) ([d5d0b26](https://github.com/github/feature-management-client-go/commit/d5d0b2620e6c8351c2d740a789c7c0fc8b0d4fe5))
* Use Times instead of MaxTimes ([#343](https://github.com/github/feature-management-client-go/issues/343)) ([7ea1c0f](https://github.com/github/feature-management-client-go/commit/7ea1c0fc4de568e4ec7334351e1e995d8e71c1d2))

## [1.6.5](https://github.com/github/feature-management-client-go/compare/vexi/v1.6.4...vexi/v1.6.5) (2025-03-12)


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 3 updates ([#324](https://github.com/github/feature-management-client-go/issues/324)) ([2b4d0d7](https://github.com/github/feature-management-client-go/commit/2b4d0d7929fe58eda7511fd8e830c9a34099d637))
* **deps:** Update to go 1.23.7 ([#331](https://github.com/github/feature-management-client-go/issues/331)) ([bde1e5a](https://github.com/github/feature-management-client-go/commit/bde1e5ae82c7a94a296164a3ee46add413029e75))

## [1.6.4](https://github.com/github/feature-management-client-go/compare/vexi/v1.6.3...vexi/v1.6.4) (2025-03-03)


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 2 updates ([#318](https://github.com/github/feature-management-client-go/issues/318)) ([c4b2b35](https://github.com/github/feature-management-client-go/commit/c4b2b3536bcc2caa2ca26e8fa85334be0a0fe98c))

## [1.6.3](https://github.com/github/feature-management-client-go/compare/vexi/v1.6.2...vexi/v1.6.3) (2025-02-17)


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 4 updates ([#314](https://github.com/github/feature-management-client-go/issues/314)) ([b762d94](https://github.com/github/feature-management-client-go/commit/b762d9452b3b5e91f728f63aaa2330dd50858c4a))

## [1.6.2](https://github.com/github/feature-management-client-go/compare/vexi/v1.6.1...vexi/v1.6.2) (2025-02-10)


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 3 updates ([#307](https://github.com/github/feature-management-client-go/issues/307)) ([ffc65d8](https://github.com/github/feature-management-client-go/commit/ffc65d856338431c6d636158ae742a9b2d842f4e))

## [1.6.1](https://github.com/github/feature-management-client-go/compare/vexi/v1.6.0...vexi/v1.6.1) (2025-02-03)


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 2 updates ([#305](https://github.com/github/feature-management-client-go/issues/305)) ([48645ca](https://github.com/github/feature-management-client-go/commit/48645cab7c34b8d0c707dc5f6c212088aab319d9))

## [1.6.0](https://github.com/github/feature-management-client-go/compare/vexi/v1.5.2...vexi/v1.6.0) (2025-01-30)


### Features

* Added telemetry for empty feature flag and actors inputs ([#301](https://github.com/github/feature-management-client-go/issues/301)) ([57b30b0](https://github.com/github/feature-management-client-go/commit/57b30b0c7eee330a4286bb06ee6f843e62a031a4))

## [1.5.2](https://github.com/github/feature-management-client-go/compare/vexi/v1.5.1...vexi/v1.5.2) (2025-01-28)


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 2 updates ([#299](https://github.com/github/feature-management-client-go/issues/299)) ([19f4fe3](https://github.com/github/feature-management-client-go/commit/19f4fe30bacfcd6cc2e71ac7e0bbb3ea5483621c))

## [1.5.1](https://github.com/github/feature-management-client-go/compare/vexi/v1.5.0...vexi/v1.5.1) (2025-01-22)


### Bug Fixes

* Removed passing a stats client to the kafka client by default ([#296](https://github.com/github/feature-management-client-go/issues/296)) ([c7740d2](https://github.com/github/feature-management-client-go/commit/c7740d2ddaaa6061424089fde0ac7f05f1060f07))

## [1.5.0](https://github.com/github/feature-management-client-go/compare/vexi/v1.4.0...vexi/v1.5.0) (2025-01-22)


### Features

* **hydro adapter:** Allow customizing kafka options ([#292](https://github.com/github/feature-management-client-go/issues/292)) ([5a9cfbe](https://github.com/github/feature-management-client-go/commit/5a9cfbe5d928b4ba65612057fc0431e183d59d07))
* Move internal/adapter interface to adapter/interface to allow user in consumers ([#294](https://github.com/github/feature-management-client-go/issues/294)) ([4bc9643](https://github.com/github/feature-management-client-go/commit/4bc964367f83018c42edeb97f3d5cef204b49dac))

## [1.4.0](https://github.com/github/feature-management-client-go/compare/vexi/v1.3.2...vexi/v1.4.0) (2025-01-21)


### Features

* Add default value and error return alternatives for IsEnabled ([#287](https://github.com/github/feature-management-client-go/issues/287)) ([f4516a7](https://github.com/github/feature-management-client-go/commit/f4516a7314f006a220320db33371384c3a7db44f))
* Add support for subscribing to changes from all owning services in Vexi go Hydro Adapter ([#288](https://github.com/github/feature-management-client-go/issues/288)) ([27e25f2](https://github.com/github/feature-management-client-go/commit/27e25f2824077c00e44faa51bb1cbb068abb5ef5))
* Add timestamps to cache to prevent out of date updates to cache ([#289](https://github.com/github/feature-management-client-go/issues/289)) ([d29600d](https://github.com/github/feature-management-client-go/commit/d29600d541f3673e1a97f2147186f4f4cb178c01))
* Switched vexi-go hydro adapter to use System root certificate store ([#285](https://github.com/github/feature-management-client-go/issues/285)) ([c2f4bf0](https://github.com/github/feature-management-client-go/commit/c2f4bf0ed403edbb60fdb3ff2ec123fb08c83fd9))


### Bug Fixes

* Changed hydro adapter to use a typed error for feature flag not found to prevent Error spam ([#284](https://github.com/github/feature-management-client-go/issues/284)) ([bf5ca41](https://github.com/github/feature-management-client-go/commit/bf5ca41c57ab94c07a961434f5e8aa4a3165c4ed))
* **deps:** Bump the vexi-packages group in /vexi with 4 updates ([#282](https://github.com/github/feature-management-client-go/issues/282)) ([90aaa87](https://github.com/github/feature-management-client-go/commit/90aaa87f3044ca6dac8ace6cf86060dce6061cfc))
* **deps:** Bump the vexi-packages group in /vexi with 5 updates ([#291](https://github.com/github/feature-management-client-go/issues/291)) ([7be88d7](https://github.com/github/feature-management-client-go/commit/7be88d71c36e25779defdafa205ba104f4c850e4))
* Improve performance and refactor telemetry ([#269](https://github.com/github/feature-management-client-go/issues/269)) ([bdc2f59](https://github.com/github/feature-management-client-go/commit/bdc2f59f561c1e092e40398834325e58e3c3a5f9))

## [1.3.2](https://github.com/github/feature-management-client-go/compare/vexi/v1.3.1...vexi/v1.3.2) (2025-01-06)


### Bug Fixes

* **deps:** Bump github.com/github/hydro-client-go/v7 from 7.8.6 to 7.8.7 in /vexi in the vexi-packages group ([#278](https://github.com/github/feature-management-client-go/issues/278)) ([2783747](https://github.com/github/feature-management-client-go/commit/2783747bc758470533b8ba80bd9c84ed0e9a6ed4))
* **deps:** Bump google.golang.org/protobuf from 1.35.2 to 1.36.0 in /vexi in the vexi-packages group ([#274](https://github.com/github/feature-management-client-go/issues/274)) ([d9a92d8](https://github.com/github/feature-management-client-go/commit/d9a92d8dbd70f253f880f6d19e025e6638cbba0a))
* **deps:** Bump the vexi-packages group in /vexi with 2 updates ([#266](https://github.com/github/feature-management-client-go/issues/266)) ([d427a1d](https://github.com/github/feature-management-client-go/commit/d427a1d1284d008da2012a1b1573c2456ff0b8c7))
* **deps:** Bump the vexi-packages group in /vexi with 2 updates ([#275](https://github.com/github/feature-management-client-go/issues/275)) ([5db4ea0](https://github.com/github/feature-management-client-go/commit/5db4ea0d723c0e97468168d09135e751ec8fedf7))

## [1.3.1](https://github.com/github/feature-management-client-go/compare/vexi/v1.3.0...vexi/v1.3.1) (2024-12-12)


### Bug Fixes

* **deps:** Bump golang.org/x/crypto from 0.27.0 to 0.31.0 in /vexi in the go_modules group ([#263](https://github.com/github/feature-management-client-go/issues/263)) ([63e13d3](https://github.com/github/feature-management-client-go/commit/63e13d34bc37c651f5604a10437f518b68266aa9))
* **deps:** Bump golang.org/x/sync from 0.9.0 to 0.10.0 in /vexi in the vexi-packages group ([#261](https://github.com/github/feature-management-client-go/issues/261)) ([8b916f7](https://github.com/github/feature-management-client-go/commit/8b916f7ec43348a65e4fcc32109c9621f36d7d2d))

## [1.3.0](https://github.com/github/feature-management-client-go/compare/vexi/v1.2.2...vexi/v1.3.0) (2024-12-04)


### Features

* Add additional GitHub actor types to extension ([#257](https://github.com/github/feature-management-client-go/issues/257)) ([2b04ddb](https://github.com/github/feature-management-client-go/commit/2b04ddbaced118256ec8abc9de9e699a8e543013))

## [1.2.2](https://github.com/github/feature-management-client-go/compare/vexi/v1.2.1...vexi/v1.2.2) (2024-12-02)


### Bug Fixes

* **deps:** Bump github.com/github/hydro-client-go/v7 from 7.8.4 to 7.8.5 in /vexi in the vexi-packages group ([#254](https://github.com/github/feature-management-client-go/issues/254)) ([e823fd8](https://github.com/github/feature-management-client-go/commit/e823fd82f7faf73e9b57744b0ab341cb3cf17d71))
* Fixed names cannot be empty ERROR when no segments ([#253](https://github.com/github/feature-management-client-go/issues/253)) ([87a8c39](https://github.com/github/feature-management-client-go/commit/87a8c3980c9e8a01e4768ef081c8b0b9e4350213))

## [1.2.1](https://github.com/github/feature-management-client-go/compare/vexi/v1.2.0...vexi/v1.2.1) (2024-11-25)


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 3 updates ([#250](https://github.com/github/feature-management-client-go/issues/250)) ([2999687](https://github.com/github/feature-management-client-go/commit/299968735b016401820b7f2beea14f9d3b704640))

## [1.2.0](https://github.com/github/feature-management-client-go/compare/vexi/v1.1.1...vexi/v1.2.0) (2024-11-23)


### Features

* Add support for subscribing to multiple owning services ([#247](https://github.com/github/feature-management-client-go/issues/247)) ([c7b6621](https://github.com/github/feature-management-client-go/commit/c7b662134a417b0687888a8e53b46822a60312d1))

## [1.1.1](https://github.com/github/feature-management-client-go/compare/vexi/v1.1.0...vexi/v1.1.1) (2024-11-22)


### Bug Fixes

* Bug in compare watermarks for all partitions ([#245](https://github.com/github/feature-management-client-go/issues/245)) ([b1d21b2](https://github.com/github/feature-management-client-go/commit/b1d21b28ddb1ac05b2fb02f88262d9cc522e001e))

## [1.1.0](https://github.com/github/feature-management-client-go/compare/vexi/v1.0.0...vexi/v1.1.0) (2024-11-20)


### Features

* Add support for curated segments ([#242](https://github.com/github/feature-management-client-go/issues/242)) ([affa1f7](https://github.com/github/feature-management-client-go/commit/affa1f7608b07225979e0fe821b8f6798a82d33d))


### Bug Fixes

* **deps:** Bump google.golang.org/protobuf from 1.35.1 to 1.35.2 in /vexi in the vexi-packages group ([#238](https://github.com/github/feature-management-client-go/issues/238)) ([66fff90](https://github.com/github/feature-management-client-go/commit/66fff904fa7f92d14f77289dd39535c076765b67))

## [1.0.0](https://github.com/github/feature-management-client-go/compare/vexi/v0.6.1...vexi/v1.0.0) (2024-11-13)

GA of Vexi to 1.0.0

### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 4 updates ([#234](https://github.com/github/feature-management-client-go/issues/234)) ([aab2b61](https://github.com/github/feature-management-client-go/commit/aab2b61ccbd13446817a8efee28d0c3be671d305))
* Guard against races ([#233](https://github.com/github/feature-management-client-go/issues/233)) ([22a7212](https://github.com/github/feature-management-client-go/commit/22a7212a8a6ee08af9ee4d595c9fa0376c272844))

## [0.6.1](https://github.com/github/feature-management-client-go/compare/vexi/v0.6.0...vexi/v0.6.1) (2024-11-04)


### Bug Fixes

* **deps:** Bump github.com/github/go-stats from 1.18.0 to 1.18.1 in /vexi in the vexi-packages group ([#231](https://github.com/github/feature-management-client-go/issues/231)) ([91a8366](https://github.com/github/feature-management-client-go/commit/91a8366962e2b88a2eeb4e23ba174a34fb2512e9))
* **deps:** Bump the vexi-packages group in /vexi with 2 updates ([#228](https://github.com/github/feature-management-client-go/issues/228)) ([e5bdb4e](https://github.com/github/feature-management-client-go/commit/e5bdb4e7b843c03e301c0225809e4bafc2cd9e95))

## [0.6.0](https://github.com/github/feature-management-client-go/compare/vexi/v0.5.6...vexi/v0.6.0) (2024-10-17)


### ⚠ BREAKING CHANGES

* Use dev feature go ([#225](https://github.com/github/feature-management-client-go/issues/225))

### Features

* Added owning service to enabled telemetry ([#223](https://github.com/github/feature-management-client-go/issues/223)) ([9730627](https://github.com/github/feature-management-client-go/commit/9730627bfafdcee0e1a2b3be7ae1405f75197611))
* Use dev feature go ([#225](https://github.com/github/feature-management-client-go/issues/225)) ([f29924b](https://github.com/github/feature-management-client-go/commit/f29924bb26527f1f5857eb205c47b952b7cf7b13))


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 5 updates ([#220](https://github.com/github/feature-management-client-go/issues/220)) ([6200316](https://github.com/github/feature-management-client-go/commit/6200316daf13d60f426709c614acf3483973e299))

## [0.5.6](https://github.com/github/feature-management-client-go/compare/vexi/v0.5.5...vexi/v0.5.6) (2024-10-07)


### Bug Fixes

* Update metric names ([#217](https://github.com/github/feature-management-client-go/issues/217)) ([d5445f3](https://github.com/github/feature-management-client-go/commit/d5445f3ed6e8f292e00c2265e1e332c7369d3a6f))

## [0.5.5](https://github.com/github/feature-management-client-go/compare/vexi/v0.5.4...vexi/v0.5.5) (2024-10-07)


### Bug Fixes

* Bug in enabled check ([#214](https://github.com/github/feature-management-client-go/issues/214)) ([115b553](https://github.com/github/feature-management-client-go/commit/115b553d1f11d69c0ac6c3fe2acce9049c3a2d90))

## [0.5.4](https://github.com/github/feature-management-client-go/compare/vexi/v0.5.3...vexi/v0.5.4) (2024-10-07)


### Bug Fixes

* Make logs and metrics consistent ([#212](https://github.com/github/feature-management-client-go/issues/212)) ([d9b6920](https://github.com/github/feature-management-client-go/commit/d9b692035660231519f0a9c59b35ab1931db5b03))

## [0.5.3](https://github.com/github/feature-management-client-go/compare/vexi/v0.5.2...vexi/v0.5.3) (2024-10-03)


### Bug Fixes

* Reset prefix on stats client ([#210](https://github.com/github/feature-management-client-go/issues/210)) ([319ab9b](https://github.com/github/feature-management-client-go/commit/319ab9bbf7080f229e8816f223a4c301fa865187))

## [0.5.2](https://github.com/github/feature-management-client-go/compare/vexi/v0.5.1...vexi/v0.5.2) (2024-10-03)


### Bug Fixes

* Bug in hydro adapter ([#208](https://github.com/github/feature-management-client-go/issues/208)) ([f2c2692](https://github.com/github/feature-management-client-go/commit/f2c269267552944b650e09c3ef2856ae8c2c979e))

## [0.5.1](https://github.com/github/feature-management-client-go/compare/vexi/v0.5.0...vexi/v0.5.1) (2024-10-03)


### Features

* Improve observability for hydro adapter ([#207](https://github.com/github/feature-management-client-go/issues/207)) ([6bd76cc](https://github.com/github/feature-management-client-go/commit/6bd76cca22dc2ae9dc6a228ddf74c0e2b626f9b9))


### Bug Fixes

* Use conventions for metric names ([#205](https://github.com/github/feature-management-client-go/issues/205)) ([b8ca947](https://github.com/github/feature-management-client-go/commit/b8ca9473456ce1f084d89269c72fb4d20610e578))

## [0.5.0](https://github.com/github/feature-management-client-go/compare/vexi/v0.4.1...vexi/v0.5.0) (2024-10-02)


### ⚠ BREAKING CHANGES

* refactor client for better conventions ([#202](https://github.com/github/feature-management-client-go/issues/202))

### Features

* Refactor client for better conventions ([#202](https://github.com/github/feature-management-client-go/issues/202)) ([8879406](https://github.com/github/feature-management-client-go/commit/8879406122bd7a554ac590468496fa9f03e5d3ab))
* Report a metric for hydro adapter start time ([#204](https://github.com/github/feature-management-client-go/issues/204)) ([2ee1574](https://github.com/github/feature-management-client-go/commit/2ee15740fe7e8dd1c4d3b25841453d74856ff9be))
* Report vexi version ([#199](https://github.com/github/feature-management-client-go/issues/199)) ([abd0937](https://github.com/github/feature-management-client-go/commit/abd09373e32a1edbb0b7995ea8295fbb9ba5511c))

## [0.4.1](https://github.com/github/feature-management-client-go/compare/vexi/v0.4.0...vexi/v0.4.1) (2024-10-01)


### Bug Fixes

* Default segment missing from array preventing actor checks ([#200](https://github.com/github/feature-management-client-go/issues/200)) ([ae48cff](https://github.com/github/feature-management-client-go/commit/ae48cffa203b49fe7f507bf97f0a5c0e4033377d))

## [0.4.0](https://github.com/github/feature-management-client-go/compare/vexi/v0.3.0...vexi/v0.4.0) (2024-09-30)


### ⚠ BREAKING CHANGES

* Cleanup Segments and mock exports ([#198](https://github.com/github/feature-management-client-go/issues/198))
* Improve telem in vexi-client ([#197](https://github.com/github/feature-management-client-go/issues/197))
* move monolith custom gates ([#193](https://github.com/github/feature-management-client-go/issues/193))
* Implement vexi actor interface and helpers ([#190](https://github.com/github/feature-management-client-go/issues/190))
* refactor telemetry ([#192](https://github.com/github/feature-management-client-go/issues/192))
* Adding FakeAdapter for testing use cases ([#188](https://github.com/github/feature-management-client-go/issues/188))
* Refactor vexi go API ([#180](https://github.com/github/feature-management-client-go/issues/180))

### Features

* Adding FakeAdapter for testing use cases ([#188](https://github.com/github/feature-management-client-go/issues/188)) ([bc2fe8b](https://github.com/github/feature-management-client-go/commit/bc2fe8b7ce5cda8279e5518ecd8a0572feb82071))
* Cleanup Segments and mock exports ([#198](https://github.com/github/feature-management-client-go/issues/198)) ([8fa71f0](https://github.com/github/feature-management-client-go/commit/8fa71f082455e9dee9502c2bf524acd837daf1c7))
* Created feature-flag-data adapter for FML use cases in codespaces ([#189](https://github.com/github/feature-management-client-go/issues/189)) ([c0ae0ab](https://github.com/github/feature-management-client-go/commit/c0ae0ab11bf683c62116142068ffba73ec9fbe19))
* Identify version field ([#187](https://github.com/github/feature-management-client-go/issues/187)) ([be0ecda](https://github.com/github/feature-management-client-go/commit/be0ecda5d077318a510c069403b50e3bfe9cd4b5))
* Implement vexi actor interface and helpers ([#190](https://github.com/github/feature-management-client-go/issues/190)) ([83a8326](https://github.com/github/feature-management-client-go/commit/83a83264f4a56c6520d37c15ba3af08c9ae2ab83))
* Improve telem in vexi-client ([#197](https://github.com/github/feature-management-client-go/issues/197)) ([c83d2b6](https://github.com/github/feature-management-client-go/commit/c83d2b6ffe518a80e09397549f5669848f94c84b))
* Move monolith custom gates ([#193](https://github.com/github/feature-management-client-go/issues/193)) ([b88f90b](https://github.com/github/feature-management-client-go/commit/b88f90bb8ed48df5a5df7a3bf8b06af6490852e9))
* Refactor telemetry ([#192](https://github.com/github/feature-management-client-go/issues/192)) ([7f89046](https://github.com/github/feature-management-client-go/commit/7f890467da2eb39b746bd9095de8ffaaa38101b9))
* Refactor vexi go API ([#180](https://github.com/github/feature-management-client-go/issues/180)) ([8834e95](https://github.com/github/feature-management-client-go/commit/8834e9580c7dfb0c23431e006f2b4999f87bf24d))
* Set version file for vexi ([#186](https://github.com/github/feature-management-client-go/issues/186)) ([a345abb](https://github.com/github/feature-management-client-go/commit/a345abb97fbafdff34189af388066ac58ce0d7f3))
* Vexi Hydro messaging adapter ([#185](https://github.com/github/feature-management-client-go/issues/185)) ([b5e0d4e](https://github.com/github/feature-management-client-go/commit/b5e0d4e4e01e3715e536ac2da1158d40b790bd1e))


### Bug Fixes

* **deps:** Bump github.com/github/go-stats from 1.15.0 to 1.16.0 in /vexi in the vexi-packages group ([#183](https://github.com/github/feature-management-client-go/issues/183)) ([1c66617](https://github.com/github/feature-management-client-go/commit/1c66617d610accba6b3b5e0d9f76cb6193da98b2))
* **deps:** Bump the vexi-packages group in /vexi with 4 updates ([#196](https://github.com/github/feature-management-client-go/issues/196)) ([54cc9dd](https://github.com/github/feature-management-client-go/commit/54cc9ddca07e0e309a1b2fccf9595ae484e11108))

## [0.3.0](https://github.com/github/feature-management-client-go/compare/vexi/v0.2.10...vexi/v0.3.0) (2024-09-17)


### ⚠ BREAKING CHANGES

* restructure and rename components in vexi-go ([#179](https://github.com/github/feature-management-client-go/issues/179))

### Features

* Restructure and rename components in vexi-go ([#179](https://github.com/github/feature-management-client-go/issues/179)) ([d394217](https://github.com/github/feature-management-client-go/commit/d39421713ca89c2334d6978265eba2741c1bcc50))


### Bug Fixes

* **deps:** Bump github.com/github/go-auth from 0.6.1 to 0.7.1 in /vexi in the vexi-packages group ([#166](https://github.com/github/feature-management-client-go/issues/166)) ([29ff58f](https://github.com/github/feature-management-client-go/commit/29ff58fb8420b3c3621d31a456bb65e66a60c514))
* **deps:** Bump github.com/github/go-auth from 0.7.1 to 0.7.2 in /vexi in the vexi-packages group ([#171](https://github.com/github/feature-management-client-go/issues/171)) ([fa42ca6](https://github.com/github/feature-management-client-go/commit/fa42ca65c252a568698db595cb10bf2d299367d9))

## [0.2.10](https://github.com/github/feature-management-client-go/compare/vexi/v0.2.9...vexi/v0.2.10) (2024-08-26)


### Bug Fixes

* **deps:** Bump github.com/github/feature-management-protos/gen/go/feature_management/feature_flags from 1.6.0 to 1.7.0 in /vexi in the vexi-packages group ([#163](https://github.com/github/feature-management-client-go/issues/163)) ([5002204](https://github.com/github/feature-management-client-go/commit/5002204db225739b678d4f074f49fa692dc58e47))

## [0.2.9](https://github.com/github/feature-management-client-go/compare/vexi/v0.2.8...vexi/v0.2.9) (2024-08-13)


### Features

* Add support for history to use JWTs ([#152](https://github.com/github/feature-management-client-go/issues/152)) ([94f911b](https://github.com/github/feature-management-client-go/commit/94f911b695abae29dea7f883e57c8503978e531f))
* Enabled JWTs in vexi management for history using custom HTTP client ([#154](https://github.com/github/feature-management-client-go/issues/154)) ([d0cb05f](https://github.com/github/feature-management-client-go/commit/d0cb05f823afe986524040c38837c9ec59f70ff4))


### Bug Fixes

* **deps:** Bump github.com/github/feature-management-protos/gen/go/feature_management/feature_flags from 1.1.3 to 1.1.4 in /vexi in the vexi-packages group ([#142](https://github.com/github/feature-management-client-go/issues/142)) ([686239b](https://github.com/github/feature-management-client-go/commit/686239be4fe903a18e74d4f5c22d7c154407e95b))
* **deps:** Bump github.com/github/feature-management-protos/gen/go/feature_management/feature_flags from 1.2.0 to 1.5.0 in /vexi in the vexi-packages group ([#148](https://github.com/github/feature-management-client-go/issues/148)) ([ff1d876](https://github.com/github/feature-management-client-go/commit/ff1d8760a213b426285a2a8efffbac05e79dafe1))
* **deps:** Bump github.com/github/feature-management-protos/gen/go/feature_management/feature_flags from 1.5.0 to 1.6.0 in /vexi in the vexi-packages group ([#159](https://github.com/github/feature-management-client-go/issues/159)) ([22ff728](https://github.com/github/feature-management-client-go/commit/22ff7289f8a40c76a047cfa49b9387504aeb939c))
* **deps:** Bump github.com/github/github-telemetry-go from 1.32.0 to 1.32.1 in /vexi in the vexi-packages group ([#160](https://github.com/github/feature-management-client-go/issues/160)) ([7423f3b](https://github.com/github/feature-management-client-go/commit/7423f3b4290376073b8912bb30cef9930da9ff9a))

## [0.2.8](https://github.com/github/feature-management-client-go/compare/vexi/v0.2.7...vexi/v0.2.8) (2024-05-16)


### Bug Fixes

* **deps:** Bump github.com/github/feature-management-protos/gen/go/feature_management/feature_flags from 1.1.2 to 1.1.3 in /vexi in the vexi-packages group ([#136](https://github.com/github/feature-management-client-go/issues/136)) ([c50c8bb](https://github.com/github/feature-management-client-go/commit/c50c8bb9c922606eab383a45d32853f007a8a981))

## [0.2.7](https://github.com/github/feature-management-client-go/compare/vexi/v0.2.6...vexi/v0.2.7) (2024-04-22)


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 2 updates ([#130](https://github.com/github/feature-management-client-go/issues/130)) ([3c3f4ca](https://github.com/github/feature-management-client-go/commit/3c3f4ca65e67fc5e2829ebd2922b2c17a78515ec))

## [0.2.6](https://github.com/github/feature-management-client-go/compare/vexi/v0.2.5...vexi/v0.2.6) (2024-03-25)


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 1 update ([#122](https://github.com/github/feature-management-client-go/issues/122)) ([53fbec7](https://github.com/github/feature-management-client-go/commit/53fbec72847506b374f92d372b12a5a67fd97a6f))

## [0.2.5](https://github.com/github/feature-management-client-go/compare/vexi/v0.2.4...vexi/v0.2.5) (2024-03-19)


### Features

* Downgrade to go-stats v1 ([#118](https://github.com/github/feature-management-client-go/issues/118)) ([e97107f](https://github.com/github/feature-management-client-go/commit/e97107f3c4e6b191a1bcf7cb4e765768772cd14f))

## [0.2.4](https://github.com/github/feature-management-client-go/compare/vexi/v0.2.3...vexi/v0.2.4) (2024-03-12)


### Bug Fixes

* Add Default Client Retry Timeout ([#115](https://github.com/github/feature-management-client-go/issues/115)) ([cf38b18](https://github.com/github/feature-management-client-go/commit/cf38b18a6b199920034a5c24408ec8734f87ebf7))
* **deps:** Bump the vexi-packages group in /vexi with 1 update ([#109](https://github.com/github/feature-management-client-go/issues/109)) ([297148e](https://github.com/github/feature-management-client-go/commit/297148e853db0e8f5e0966171f95c58f98d51535))

## [0.2.3](https://github.com/github/feature-management-client-go/compare/vexi/v0.2.2...vexi/v0.2.3) (2024-03-06)


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 2 updates ([#98](https://github.com/github/feature-management-client-go/issues/98)) ([9f6e880](https://github.com/github/feature-management-client-go/commit/9f6e8806c015cc1ee53a605df46b1b065662a513))

## [0.2.2](https://github.com/github/feature-management-client-go/compare/vexi/v0.2.1...vexi/v0.2.2) (2024-02-23)


### Bug Fixes

* Update to use the new ffh url format ([#88](https://github.com/github/feature-management-client-go/issues/88)) ([5c70e85](https://github.com/github/feature-management-client-go/commit/5c70e85366f58ba9da9e6f9a678da22fc6c93e4c))

## [0.2.1](https://github.com/github/feature-management-client-go/compare/vexi/v0.2.0...vexi/v0.2.1) (2024-02-22)


### Features

* Refactor and rename of the go packages ([#81](https://github.com/github/feature-management-client-go/issues/81)) ([7056760](https://github.com/github/feature-management-client-go/commit/705676017f04e47d8a2461aa0094c329ac69caa3))


### Bug Fixes

* **deps:** Bump the vexi-packages group in /vexi with 1 update ([#86](https://github.com/github/feature-management-client-go/issues/86)) ([59c533b](https://github.com/github/feature-management-client-go/commit/59c533b5d2059cf2e0521dbef9d74eb786b9f781))

## 0.2.0 (2024-02-14)


### Features

* Feature Management SDK - History ([#67](https://github.com/github/feature-management-client-go/issues/67)) ([4ca8d89](https://github.com/github/feature-management-client-go/commit/4ca8d895b9b408f9ca94eb27cb6785ae1adf1e64))


### Continuous Integration

* Modify workflows to support release processes ([#66](https://github.com/github/feature-management-client-go/issues/66)) ([3bd5df8](https://github.com/github/feature-management-client-go/commit/3bd5df8be1a3df82080b17ac5c1055505a684089))
