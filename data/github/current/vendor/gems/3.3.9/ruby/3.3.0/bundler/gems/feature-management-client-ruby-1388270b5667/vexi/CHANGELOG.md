# Changelog

## [0.2.44](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.43...vexi/v0.2.44) (2024-11-26)


### Bug Fixes

* Return nil instead of error from in_memory cache get ([#358](https://github.com/github/feature-management-client-ruby/issues/358)) ([154ff9f](https://github.com/github/feature-management-client-ruby/commit/154ff9f4e2c309cd3fe4f4fdd47583872b8c0e84))

## [0.2.43](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.42...vexi/v0.2.43) (2024-11-26)


### Features

* Improve preload instrumentation ([#356](https://github.com/github/feature-management-client-ruby/issues/356)) ([fc8aec7](https://github.com/github/feature-management-client-ruby/commit/fc8aec76755b8ae361e2c1a2b97266e7d8a5cd98))
* Update vexi to use singular get with cache for single enabled calls ([#355](https://github.com/github/feature-management-client-ruby/issues/355)) ([5112aab](https://github.com/github/feature-management-client-ruby/commit/5112aabc69d2f214ee578e49eab347de053d6c97))

## [0.2.42](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.41...vexi/v0.2.42) (2024-11-16)


### Bug Fixes

* Support init of CircuitBreakerConfig via constructor parameters ([#349](https://github.com/github/feature-management-client-ruby/issues/349)) ([193185f](https://github.com/github/feature-management-client-ruby/commit/193185f11ac9c2e11a2e203bd9a990a92361c940))

## [0.2.41](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.40...vexi/v0.2.41) (2024-11-15)


### Features

* Add optional support for cache and adapter circuit breakers ([#347](https://github.com/github/feature-management-client-ruby/issues/347)) ([83c734f](https://github.com/github/feature-management-client-ruby/commit/83c734f12749172ecad6e0ef67282869adbe3e67))

## [0.2.40](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.39...vexi/v0.2.40) (2024-11-07)


### Bug Fixes

* Fallback to adapter in case of cache get and move on in case of cache set errors ([#345](https://github.com/github/feature-management-client-ruby/issues/345)) ([6811acf](https://github.com/github/feature-management-client-ruby/commit/6811acff7a581bdce2db79fd04fef604260ff9c6))
* Fix handling of nil and invalid actor inputs ([#344](https://github.com/github/feature-management-client-ruby/issues/344)) ([bb22671](https://github.com/github/feature-management-client-ruby/commit/bb226713879e7cb59758574de47e0ea5b3a33ceb))
* Handle errors fetching feature flags or segments during preload ([#342](https://github.com/github/feature-management-client-ruby/issues/342)) ([7861b25](https://github.com/github/feature-management-client-ruby/commit/7861b2556d4e8336f02f14ae1a1198b9ac5a9f31))

## [0.2.39](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.38...vexi/v0.2.39) (2024-10-31)


### Bug Fixes

* Store boolean_gate in hash instead of converting back and forth to state ([#337](https://github.com/github/feature-management-client-ruby/issues/337)) ([c652a8b](https://github.com/github/feature-management-client-ruby/commit/c652a8b00eff070b46c8f6c0d215a9b2f2a9103b))

## [0.2.38](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.37...vexi/v0.2.38) (2024-10-15)


### Features

* Create vexi gem with sorbet erased for performance boost to match Flipper ([#329](https://github.com/github/feature-management-client-ruby/issues/329)) ([35dac35](https://github.com/github/feature-management-client-ruby/commit/35dac35befd716fcee7ae5baf3e563ec344e7653))
* Removed enums from vexi-ruby to make way for using sorbet-eraser ([#330](https://github.com/github/feature-management-client-ruby/issues/330)) ([24723b9](https://github.com/github/feature-management-client-ruby/commit/24723b9a35c400a824d5c53ddb80a60e56a7785e))

## [0.2.37](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.36...vexi/v0.2.37) (2024-10-09)


### Features

* Migrate instrumentation to a single notification event ([#318](https://github.com/github/feature-management-client-ruby/issues/318)) ([e25cdc1](https://github.com/github/feature-management-client-ruby/commit/e25cdc1920d309c07fbb07295924e1c7fb7ba109))


### Bug Fixes

* Allow instrumentation of multiple errors per `enabled?` call ([#324](https://github.com/github/feature-management-client-ruby/issues/324)) ([d6e3e55](https://github.com/github/feature-management-client-ruby/commit/d6e3e554bbacfd46712ede021930c06abb3591fd))


### Performance Improvements

* Added short circuit return when evaluating percentage gates in case it is set to 100 ([#323](https://github.com/github/feature-management-client-ruby/issues/323)) ([53b755f](https://github.com/github/feature-management-client-ruby/commit/53b755ffb9e5e2e7783df88188d79cd862319a21))
* Improve performance of percentage actors and calls gates evaluation in case of 0% ([#320](https://github.com/github/feature-management-client-ruby/issues/320)) ([520947a](https://github.com/github/feature-management-client-ruby/commit/520947a349202d2da08b79809616bf0ca1b0ffaa))

## [0.2.36](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.35...vexi/v0.2.36) (2024-10-02)


### Bug Fixes

* Use monotonic time in vexi telemetry ([#314](https://github.com/github/feature-management-client-ruby/issues/314)) ([ec77fa6](https://github.com/github/feature-management-client-ruby/commit/ec77fa6ec5ba6e42ec0ee7c4cdda627c3d8e23bf))

## [0.2.35](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.34...vexi/v0.2.35) (2024-09-30)


### Bug Fixes

* Renamed a variable in the abstract entity service ([#311](https://github.com/github/feature-management-client-ruby/issues/311)) ([7233bc6](https://github.com/github/feature-management-client-ruby/commit/7233bc66fb7530526310212f8f1fe3229919cc34))

## [0.2.34](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.33...vexi/v0.2.34) (2024-09-30)


### Features

* Removed an unnecessary comment ([#309](https://github.com/github/feature-management-client-ruby/issues/309)) ([7a3f4b2](https://github.com/github/feature-management-client-ruby/commit/7a3f4b2f0de24beb89774160a75efea247fb4f83))

## [0.2.33](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.32...vexi/v0.2.33) (2024-09-19)


### Bug Fixes

* Passing an actors array with a nil value can cause vexi `enable?` check to incorrectly return true ([#302](https://github.com/github/feature-management-client-ruby/issues/302)) ([4b0621f](https://github.com/github/feature-management-client-ruby/commit/4b0621f66e243cbf778108bb67df0f8ba3d4a4f3))

## [0.2.32](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.31...vexi/v0.2.32) (2024-09-06)


### Bug Fixes

* Typo in segment cache key prefix and provide way to actually override these ([#298](https://github.com/github/feature-management-client-ruby/issues/298)) ([c9b8a6c](https://github.com/github/feature-management-client-ruby/commit/c9b8a6ca964168efa5dcd42bfcc793b6e03a34f2))

## [0.2.31](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.30...vexi/v0.2.31) (2024-09-04)


### Bug Fixes

* Handle resolving state of feature flag from symbol or string from hash ([#296](https://github.com/github/feature-management-client-ruby/issues/296)) ([503f7e4](https://github.com/github/feature-management-client-ruby/commit/503f7e4a8c57f2fb2a6366262932ba811f584644))

## [0.2.30](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.29...vexi/v0.2.30) (2024-08-30)


### Features

* Cache config for key prefixes ([#293](https://github.com/github/feature-management-client-ruby/issues/293)) ([286e312](https://github.com/github/feature-management-client-ruby/commit/286e312071937ea268bd957bbfb6426f75a8798c))
* Convert to_h to to_hash and add from_hash ([#290](https://github.com/github/feature-management-client-ruby/issues/290)) ([f1245b0](https://github.com/github/feature-management-client-ruby/commit/f1245b0f394e0473248124b890429318ef645222))
* Remove is_default_segment_embedded and default_segment from feature flag ([#291](https://github.com/github/feature-management-client-ruby/issues/291)) ([d5d4ef6](https://github.com/github/feature-management-client-ruby/commit/d5d4ef69c6b38565aa885612f71f444b34778848))


### Bug Fixes

* Remove unreferenced segments_actors_combination code ([#292](https://github.com/github/feature-management-client-ruby/issues/292)) ([6b08acc](https://github.com/github/feature-management-client-ruby/commit/6b08acc51bc6e1ef3d9db77073717fcdcf35f4c8))

## [0.2.29](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.28...vexi/v0.2.29) (2024-08-26)


### Features

* Updated feature flag and segment models and some methods on them ([#286](https://github.com/github/feature-management-client-ruby/issues/286)) ([18a9231](https://github.com/github/feature-management-client-ruby/commit/18a9231f09016a20e2fbf7fad837487558a7b48d))

## [0.2.28](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.27...vexi/v0.2.28) (2024-08-22)


### Features

* Fixed imports for feature flag model and segment model ([#284](https://github.com/github/feature-management-client-ruby/issues/284)) ([ffd894a](https://github.com/github/feature-management-client-ruby/commit/ffd894abbe835b9afb72918b1cd2e8a20805ecd9))

## [0.2.27](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.26...vexi/v0.2.27) (2024-08-22)


### Features

* Implemented the monolith optimized feature flag data adapter ([#280](https://github.com/github/feature-management-client-ruby/issues/280)) ([d496909](https://github.com/github/feature-management-client-ruby/commit/d49690905efc12027ced0115208b5ea45f121df9))

## [0.2.26](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.25...vexi/v0.2.26) (2024-08-14)


### Features

* Removed big feature support from vexi ([#278](https://github.com/github/feature-management-client-ruby/issues/278)) ([4faeb62](https://github.com/github/feature-management-client-ruby/commit/4faeb62e0a3c15f368ff9a9ae8c6fd53388bc8a4))

## [0.2.25](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.24...vexi/v0.2.25) (2024-08-05)


### Features

* Introduce Vexi::InstrumentationContext ([#273](https://github.com/github/feature-management-client-ruby/issues/273)) ([b342605](https://github.com/github/feature-management-client-ruby/commit/b3426057c159fd5beda7c4771a5f0dfde5b17e6a))

## [0.2.24](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.23...vexi/v0.2.24) (2024-07-26)


### Features

* Add duration metrics for memoization, cache, and adapter ([#270](https://github.com/github/feature-management-client-ruby/issues/270)) ([91c2a2c](https://github.com/github/feature-management-client-ruby/commit/91c2a2c43b86966e796008a6e67b73484795441b))

## [0.2.23](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.22...vexi/v0.2.23) (2024-07-24)


### Bug Fixes

* Fix result type of duration payload ([#268](https://github.com/github/feature-management-client-ruby/issues/268)) ([525ec38](https://github.com/github/feature-management-client-ruby/commit/525ec384c76e1ddf25b81c998692c4264ed6fafa))

## [0.2.22](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.21...vexi/v0.2.22) (2024-07-24)


### Bug Fixes

* Fix custom gates metrics ([#265](https://github.com/github/feature-management-client-ruby/issues/265)) ([7973193](https://github.com/github/feature-management-client-ruby/commit/797319385a6729d902b58989b8513a80d7d413fe))

## [0.2.21](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.20...vexi/v0.2.21) (2024-07-18)


### Features

* Emit feature names for flipper compatibility in the monolith ([#261](https://github.com/github/feature-management-client-ruby/issues/261)) ([6970ba6](https://github.com/github/feature-management-client-ruby/commit/6970ba6d677e4cb315739458a922adbb2299ee2d))

## [0.2.20](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.19...vexi/v0.2.20) (2024-07-15)


### Features

* Add cache hit metrics for Vexi feature flag lookup ([#256](https://github.com/github/feature-management-client-ruby/issues/256)) ([bee6b7a](https://github.com/github/feature-management-client-ruby/commit/bee6b7a1619bc39b3066a0892d198969c7642ef9))

## [0.2.19](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.18...vexi/v0.2.19) (2024-07-12)


### Features

* Cache with ttl and add to memoized any entities not found from the adapter ([#254](https://github.com/github/feature-management-client-ruby/issues/254)) ([d0bfadf](https://github.com/github/feature-management-client-ruby/commit/d0bfadf98b1fa8029c9e2e241a8f75a80a83cce7))

## [0.2.18](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.17...vexi/v0.2.18) (2024-07-09)


### Features

* Include memoizing tag for is_enabled and preload duration notifications ([#250](https://github.com/github/feature-management-client-ruby/issues/250)) ([1ae4f23](https://github.com/github/feature-management-client-ruby/commit/1ae4f238c1fabda956f9f2c9f08a4a045d1928e3))


### Bug Fixes

* Lock feature_management_feature_flags gem to current version ([#253](https://github.com/github/feature-management-client-ruby/issues/253)) ([4c92ff7](https://github.com/github/feature-management-client-ruby/commit/4c92ff7fb0327d299c24479fa87680870f82b980))

## [0.2.17](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.16...vexi/v0.2.17) (2024-07-03)


### Features

* Move Vexi client into it's own module separate from main `Vexi` module ([#246](https://github.com/github/feature-management-client-ruby/issues/246)) ([6d9cc7e](https://github.com/github/feature-management-client-ruby/commit/6d9cc7e4229a636921feaf959eeed086ed1ce122))
* Vexi instance in thread local variable ([#248](https://github.com/github/feature-management-client-ruby/issues/248)) ([a4ff9e1](https://github.com/github/feature-management-client-ruby/commit/a4ff9e10ed5045bf7188f4409e55c73dbe406ff6))

## [0.2.16](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.15...vexi/v0.2.16) (2024-06-26)


### Features

* Add Vexi configuration builder ([#240](https://github.com/github/feature-management-client-ruby/issues/240)) ([e4a9af7](https://github.com/github/feature-management-client-ruby/commit/e4a9af7f70f0f785a60946efc65b19da92f801b0))

## [0.2.15](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.14...vexi/v0.2.15) (2024-06-25)


### Features

* Use interface type collection for actors ([#237](https://github.com/github/feature-management-client-ruby/issues/237)) ([ca41eee](https://github.com/github/feature-management-client-ruby/commit/ca41eee0c7daa15e2dbe14057f7e1a25d37877a9))

## [0.2.14](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.13...vexi/v0.2.14) (2024-06-18)


### Features

* Update `Cache#mset` signature to take `Hash[string, untyped]` ([#236](https://github.com/github/feature-management-client-ruby/issues/236)) ([2715f48](https://github.com/github/feature-management-client-ruby/commit/2715f48379571aeb9376193826979fd51a6722c9))


### Bug Fixes

* Correctly handle caching without expiry in in_memory implementation ([#234](https://github.com/github/feature-management-client-ruby/issues/234)) ([b53e447](https://github.com/github/feature-management-client-ruby/commit/b53e44713213c0c479c42cb506b160ed618e3c1d))

## [0.2.13](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.12...vexi/v0.2.13) (2024-06-07)


### Features

* Add support for memoization ([#229](https://github.com/github/feature-management-client-ruby/issues/229)) ([f1f3543](https://github.com/github/feature-management-client-ruby/commit/f1f3543bef6bc5e8282b312a6681924a3cb7dcd6))
* Add support for preloading multiple feature flags ([#225](https://github.com/github/feature-management-client-ruby/issues/225)) ([d0bcf9e](https://github.com/github/feature-management-client-ruby/commit/d0bcf9eca509b4b021e5c5014585349e70a5431d))


### Bug Fixes

* Remove `vexi.` from operation as the notification name already prefixes it ([#227](https://github.com/github/feature-management-client-ruby/issues/227)) ([ab6a2dc](https://github.com/github/feature-management-client-ruby/commit/ab6a2dc2b32e793944a03f81ac3a244b382d2838))

## [0.2.12](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.11...vexi/v0.2.12) (2024-05-31)


### Bug Fixes

* Rename distribution to duration ([#221](https://github.com/github/feature-management-client-ruby/issues/221)) ([daa25bd](https://github.com/github/feature-management-client-ruby/commit/daa25bde82e3f2ea9b54c98764b8f1fa5024c280))

## [0.2.11](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.10...vexi/v0.2.11) (2024-05-31)


### Features

* Add result value to distribution events ([#220](https://github.com/github/feature-management-client-ruby/issues/220)) ([08b2987](https://github.com/github/feature-management-client-ruby/commit/08b29878ebcf27d830cb16bbdd50131995c57d5b))
* Use semantic notification event names ([#217](https://github.com/github/feature-management-client-ruby/issues/217)) ([0c68050](https://github.com/github/feature-management-client-ruby/commit/0c68050b384289c82006621ad25bebf52e01ea04))

## [0.2.10](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.9...vexi/v0.2.10) (2024-05-24)


### Features

* Emit metric for total duration of the `enabled?` call for custom gates ([#212](https://github.com/github/feature-management-client-ruby/issues/212)) ([7509782](https://github.com/github/feature-management-client-ruby/commit/7509782c1c46e0b979eef207c6f4635661d1797a))


### Bug Fixes

* Introduce configuration context and submit it for metrics ([#213](https://github.com/github/feature-management-client-ruby/issues/213)) ([7d0bc36](https://github.com/github/feature-management-client-ruby/commit/7d0bc3654ec88c96221ab623867c8fcdab943aa7))

## [0.2.9](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.8...vexi/v0.2.9) (2024-05-21)


### Bug Fixes

* Rename feature name to feature flag ([#206](https://github.com/github/feature-management-client-ruby/issues/206)) ([eca46bd](https://github.com/github/feature-management-client-ruby/commit/eca46bd7844e7571eb7fa46aa63f29af623bde91))
* Update metrics events to use hierarchical patterns ([#210](https://github.com/github/feature-management-client-ruby/issues/210)) ([8c71e6c](https://github.com/github/feature-management-client-ruby/commit/8c71e6cc189a542599da0f9dd4703a0a69d46a4e))

## [0.2.8](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.7...vexi/v0.2.8) (2024-03-25)


### Bug Fixes

* Update notification context tags to be consistent with what is checked in the resulting payload ([#185](https://github.com/github/feature-management-client-ruby/issues/185)) ([5ec9a97](https://github.com/github/feature-management-client-ruby/commit/5ec9a97defd4e2e415d5792877bebd97c34e7c5c))

## [0.2.7](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.6...vexi/v0.2.7) (2024-03-21)


### Bug Fixes

* In-memory cache TTL should be 30 seconds ([#181](https://github.com/github/feature-management-client-ruby/issues/181)) ([9fd010a](https://github.com/github/feature-management-client-ruby/commit/9fd010aa55eb1832a3cc02af2170377eba637866))

## [0.2.6](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.5...vexi/v0.2.6) (2024-03-20)


### Features

* Added support for a fallback proc ([#178](https://github.com/github/feature-management-client-ruby/issues/178)) ([a51c071](https://github.com/github/feature-management-client-ruby/commit/a51c071497c615407501ebfaca952f0d3a6f98d5))


### Bug Fixes

* Include non-embedded default segment in segments so it gets checked ([#179](https://github.com/github/feature-management-client-ruby/issues/179)) ([a64834b](https://github.com/github/feature-management-client-ruby/commit/a64834b981e0cb8345c154e9298b13ca8e21bc73))

## [0.2.5](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.4...vexi/v0.2.5) (2024-03-20)


### Features

* Add read and write management operations to file adapter ([#170](https://github.com/github/feature-management-client-ruby/issues/170)) ([b06ccc6](https://github.com/github/feature-management-client-ruby/commit/b06ccc65b6761076ab3357aeb962e12c128e62b5))


### Bug Fixes

* Use more explicit name methods on interfaces ([#174](https://github.com/github/feature-management-client-ruby/issues/174)) ([a0b3e94](https://github.com/github/feature-management-client-ruby/commit/a0b3e94e17974ee701bd62576577383d12bb6366))

## [0.2.4](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.3...vexi/v0.2.4) (2024-03-19)


### Features

* Add Telemetry to Segment Service ([#171](https://github.com/github/feature-management-client-ruby/issues/171)) ([2fe18d2](https://github.com/github/feature-management-client-ruby/commit/2fe18d26438c0a4148e46293d5dd9b9618673d2c))

## [0.2.3](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.2...vexi/v0.2.3) (2024-03-18)


### Bug Fixes

* Fixed feature-flag-hub error messages ([#167](https://github.com/github/feature-management-client-ruby/issues/167)) ([414a285](https://github.com/github/feature-management-client-ruby/commit/414a285ae57e3dbcf3324ed4b5b3439014b2dad1))

## [0.2.2](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.1...vexi/v0.2.2) (2024-03-15)


### Features

* Update vexi_management methods to take string/symbol and string/actor ([#163](https://github.com/github/feature-management-client-ruby/issues/163)) ([db1f8be](https://github.com/github/feature-management-client-ruby/commit/db1f8be5c31ccdcc450bbc8b8949c4ffe11c418b))


### Bug Fixes

* Add Functionality to retrieve a Feature Flag in VexiManagement ([#165](https://github.com/github/feature-management-client-ruby/issues/165)) ([3808a73](https://github.com/github/feature-management-client-ruby/commit/3808a73c2fda6954ea9dcb0dd7d56c046be44778))

## [0.2.1](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.2.0...vexi/v0.2.1) (2024-03-12)


### Features

* Update InMemoryAdapter to use Enum for mode ([#159](https://github.com/github/feature-management-client-ruby/issues/159)) ([0c88c3c](https://github.com/github/feature-management-client-ruby/commit/0c88c3ca96f5fed4a80c532e3de3dd325aeb0371))

## [0.2.0](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.1.11...vexi/v0.2.0) (2024-03-12)


### ⚠ BREAKING CHANGES

* Add actor interface ([#155](https://github.com/github/feature-management-client-ruby/issues/155))

### Features

* Add actor interface ([#155](https://github.com/github/feature-management-client-ruby/issues/155)) ([5ddc08d](https://github.com/github/feature-management-client-ruby/commit/5ddc08d12f1439de35dfa033ae0b9e6fe0257646))
* File management adapter ([#157](https://github.com/github/feature-management-client-ruby/issues/157)) ([042b786](https://github.com/github/feature-management-client-ruby/commit/042b786bb34213a7e6a0ba89219fac9c4d3ef207))
* Update vexi_management to support full API and implement with InMemoryAdapter ([#152](https://github.com/github/feature-management-client-ruby/issues/152)) ([c5d9575](https://github.com/github/feature-management-client-ruby/commit/c5d9575bad1af9f98c013bbb4ccebdea507f5cff))

## [0.1.11](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.1.10...vexi/v0.1.11) (2024-03-08)


### Features

* Create wrapper to instrument distribution timer for enabled ([#145](https://github.com/github/feature-management-client-ruby/issues/145)) ([2ff1dba](https://github.com/github/feature-management-client-ruby/commit/2ff1dba8a2b031d65b642bfbb68fbfdc73b1d0de))
* Support for vexi gem only changes of in_memory_adapter ([#146](https://github.com/github/feature-management-client-ruby/issues/146)) ([c904b7c](https://github.com/github/feature-management-client-ruby/commit/c904b7cdcf2177401065daa1b2e145e976a922db))

## [0.1.10](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.1.9...vexi/v0.1.10) (2024-03-06)


### Features

* Add feature_name to custom gate evaluator enable ([#144](https://github.com/github/feature-management-client-ruby/issues/144)) ([1fe85ac](https://github.com/github/feature-management-client-ruby/commit/1fe85ac9576c6028c3d3418c0ac12b183a9b77d9))
* Switching to activesupport notifications for observability ([#127](https://github.com/github/feature-management-client-ruby/issues/127)) ([e50b675](https://github.com/github/feature-management-client-ruby/commit/e50b67561e5dc65837c542501ee37f549ffad533))


### Bug Fixes

* Segment service should check the adapter if there's a cache miss and not just on cache error ([#140](https://github.com/github/feature-management-client-ruby/issues/140)) ([5762536](https://github.com/github/feature-management-client-ruby/commit/5762536c392349e57d59ed91f5c01ffda5389a7f))

## [0.1.9](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.1.8...vexi/v0.1.9) (2024-03-01)


### Bug Fixes

* Update release workflow to add bundle updates to created PRs ([#133](https://github.com/github/feature-management-client-ruby/issues/133)) ([42b5645](https://github.com/github/feature-management-client-ruby/commit/42b564509cb453a674f4cf0a4237439e9ab6507c))

## [0.1.8](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.1.7...vexi/v0.1.8) (2024-03-01)


### Features

* Gem refactor ([#109](https://github.com/github/feature-management-client-ruby/issues/109)) ([c03bb2d](https://github.com/github/feature-management-client-ruby/commit/c03bb2d345246355548dff364c136b0bd392177e))
* Updated cache interface to perform batch operations ([#120](https://github.com/github/feature-management-client-ruby/issues/120)) ([0597314](https://github.com/github/feature-management-client-ruby/commit/05973140886ae85d28b59dd9f4cd225538360bbd))
* Vexi_management to support enable and disable via in_memory_adapter ([#101](https://github.com/github/feature-management-client-ruby/issues/101)) ([581ef9a](https://github.com/github/feature-management-client-ruby/commit/581ef9a92feb5fd7854f5204092da6dbb39d4b07))


### Bug Fixes

* Fix FFH adapter path ([#118](https://github.com/github/feature-management-client-ruby/issues/118)) ([715d627](https://github.com/github/feature-management-client-ruby/commit/715d627d94cc469343ae757af1f93a4a9946f0cc))

## [0.1.7](https://github.com/github/feature-management-client-ruby/compare/vexi/v0.1.6...vexi/v0.1.7) (2024-02-23)


### Features

* Implement Serial Evaluator ([#92](https://github.com/github/feature-management-client-ruby/issues/92)) ([ba8ded2](https://github.com/github/feature-management-client-ruby/commit/ba8ded23cc1332825c0908d7763f5208cb7e2cfa))


### Bug Fixes

* Refactored the custom gates evaluator to an interface ([#90](https://github.com/github/feature-management-client-ruby/issues/90)) ([0225b96](https://github.com/github/feature-management-client-ruby/commit/0225b96a9824b3a302ab3df990e9a7c2c2730b42))

## [0.1.6](https://github.com/github/vexi-ruby/compare/vexi/v0.1.5...vexi/v0.1.6) (2024-02-08)


### Features

* Add management gem and support for releasing multiple gems ([#74](https://github.com/github/vexi-ruby/issues/74)) ([1f240bf](https://github.com/github/vexi-ruby/commit/1f240bfc94b48301c46fafd0aaafb3e7b57f7db6))

## [0.1.6](https://github.com/github/vexi-ruby/compare/vexi/v0.1.5...vexi/v0.1.6) (2024-02-08)


### Features

* Add management gem and support for releasing multiple gems ([#74](https://github.com/github/vexi-ruby/issues/74)) ([1f240bf](https://github.com/github/vexi-ruby/commit/1f240bfc94b48301c46fafd0aaafb3e7b57f7db6))

## [0.1.5](https://github.com/github/vexi-ruby/compare/vexi/v0.1.4...vexi/v0.1.5) (2024-01-25)


### Features

* Update client ([#68](https://github.com/github/vexi-ruby/issues/68)) ([d2e64ad](https://github.com/github/vexi-ruby/commit/d2e64ad3afa942afedfbf33777a2116b695a2b60))

## [0.1.4](https://github.com/github/vexi-ruby/compare/vexi/v0.1.3...vexi/v0.1.4) (2024-01-25)


### Features

* Change all enabled adapter to constant adapter ([#63](https://github.com/github/vexi-ruby/issues/63)) ([356928c](https://github.com/github/vexi-ruby/commit/356928c520425d60f8129d2a4fd44b1aab1a4242))


### Bug Fixes

* Move adapters, cache, and custom gate evaluators into submodules ([#67](https://github.com/github/vexi-ruby/issues/67)) ([c511177](https://github.com/github/vexi-ruby/commit/c511177375792e7664a96edad234f179fec8b138))

## [0.1.3](https://github.com/github/vexi-ruby/compare/vexi/v0.1.2...vexi/v0.1.3) (2024-01-25)


### Features

* Vexi CLI ([#60](https://github.com/github/vexi-ruby/issues/60)) ([79b58f8](https://github.com/github/vexi-ruby/commit/79b58f825e9859f1ea6fe8692a1b8ecb41f83f88))

## [0.1.2](https://github.com/github/vexi-ruby/compare/vexi/v0.1.1...vexi/v0.1.2) (2024-01-25)


### Bug Fixes

* Change models to be in Vexi module ([#58](https://github.com/github/vexi-ruby/issues/58)) ([34f7937](https://github.com/github/vexi-ruby/commit/34f79378dec14b8f4a93ff8f02e277a37526b868))

## [0.1.1](https://github.com/github/vexi-ruby/compare/vexi/v0.1.0...vexi/v0.1.1) (2024-01-25)


### Bug Fixes

* Add dependencies fnv and zache to vexi.gemspec ([#56](https://github.com/github/vexi-ruby/issues/56)) ([b03ab6a](https://github.com/github/vexi-ruby/commit/b03ab6aac0fe8abf80cb5bbb1354fdbd51f89be4))

## [0.1.0](https://github.com/github/vexi-ruby/compare/vexi-v0.1.0...vexi/v0.1.0) (2024-01-25)


### Features

* Adds a release config file ([#47](https://github.com/github/vexi-ruby/issues/47)) ([67e9d66](https://github.com/github/vexi-ruby/commit/67e9d6695f42d5a05787c145544e66f759c810f2))


### Miscellaneous Chores

* Generate version 0.1.0 ([#51](https://github.com/github/vexi-ruby/issues/51)) ([386ab43](https://github.com/github/vexi-ruby/commit/386ab43a76e5b6aae767558a6fe2f37eacfe88bf))


### Continuous Integration

* Add linting to pr titles ([#53](https://github.com/github/vexi-ruby/issues/53)) ([69ee5f0](https://github.com/github/vexi-ruby/commit/69ee5f0e3dda34034760c0e8d119fc33f79023e4))

## 0.1.0 (2024-01-25)


### Features

* Adds a release config file ([#47](https://github.com/github/vexi-ruby/issues/47)) ([67e9d66](https://github.com/github/vexi-ruby/commit/67e9d6695f42d5a05787c145544e66f759c810f2))


### Miscellaneous Chores

* Generate version 0.1.0 ([#51](https://github.com/github/vexi-ruby/issues/51)) ([386ab43](https://github.com/github/vexi-ruby/commit/386ab43a76e5b6aae767558a6fe2f37eacfe88bf))
