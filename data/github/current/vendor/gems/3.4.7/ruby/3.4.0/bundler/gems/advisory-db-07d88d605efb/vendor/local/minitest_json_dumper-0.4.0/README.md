MinitestJSONDumper
===================

This Ruby library allows the standard minitest error/failure reporting to be replaced with JSON output that can be read by CI.

Adding MinitestJSONDumper to your app
-----------------------------

1. Add this gem to your Gemfile.

2. Add this to your `test_helper.rb`:

```ruby
require "minitest_json_dumper/reporter"

Minitest::Reporters.use! [ MinitestJSONDumper::Reporter.new ]
```

(You may want to scope this to only run in certain environments.)

Sample output
-------------

Failure caused by a failed assertion:

```json
===FAILURE===
{
  "suite": "FlakeTest",
  "name": "test_queries_for_related_test_failures",
  "areas_of_responsibility": [

  ],
  "areas_of_responsibility_error": "No #areas_of_responsibility method for FlakeTest",
  "message": "Expected: true\n  Actual: false",
  "location": "/Users/mistydemeo/github/ci/test/models/flake_test.rb:39",
  "duration": 0.026078969007357955,
  "fingerprint": "9545593415283c17f42a06c5fcce6377",
  "hostname": "C02R70KCFVH8"
}
===END FAILURE===
```

Exception raised during a test:

```json
===FAILURE===
{
  "suite": "FlakeTest",
  "name": "test_queries_for_related_test_failures_based_on_repository",
  "areas_of_responsibility": [

  ],
  "areas_of_responsibility_error": "No #areas_of_responsibility method for FlakeTest",
  "message": "Exception: test exception\n    test/models/flake_test.rb:54:in `block in <class:FlakeTest>'",
  "location": "/Users/mistydemeo/github/ci/test/models/flake_test.rb:54",
  "duration": 0.028900219942443073,
  "fingerprint": "c682dc9e82d1e7e2c7005b4e789bab2e",
  "hostname": "C02R70KCFVH8",
  "backtrace": "/Users/mistydemeo/github/ci/test/models/flake_test.rb:54:in `block in <class:FlakeTest>'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest/test.rb:108:in `block (3 levels) in run'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest/test.rb:205:in `capture_exceptions'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest/test.rb:105:in `block (2 levels) in run'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest/test.rb:256:in `time_it'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest/test.rb:104:in `block in run'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:331:in `on_signal'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest/test.rb:276:in `with_info_handler'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest/test.rb:103:in `run'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-reporters-1.1.9/lib/minitest/reporters.rb:48:in `run_with_hooks'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:778:in `run_one_method'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:305:in `run_one_method'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:293:in `block (2 levels) in run'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:292:in `each'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:292:in `block in run'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:331:in `on_signal'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:318:in `with_info_handler'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:291:in `run'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:152:in `block in __run'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:152:in `map'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:152:in `__run'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:129:in `run'\n/Users/mistydemeo/github/ci/vendor/gems/ruby/2.1.0/gems/minitest-5.8.4/lib/minitest.rb:56:in `block in autorun'",
  "exception_class": "Exception"
}
===END FAILURE===
```
