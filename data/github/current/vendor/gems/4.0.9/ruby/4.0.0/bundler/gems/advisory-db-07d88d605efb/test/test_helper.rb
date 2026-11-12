# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

if ENV["CI_MODE"] == "true"
  require "minitest_json_dumper/reporter"
  Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new, MinitestJSONDumper::Reporter.new]
end

# Setting GITHUB_THROTTLE_OPEN effectively disables the rate limiter
# tests will not run correctly on CI without this
ENV["GITHUB_THROTTLE_OPEN"] = "1"

require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"
require "active_job/test_helper"
require "chatops/controller/test_case_helpers"

Rails.root.glob("test/support/*.rb").each { |path| require path }

if ENV["JSON_TEST_FAILURE_OUTPUT"]
  require "json_dumper/reporter"

  # We want both the default reporter and the JSON reporter.
  Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new, JSONDumper::Reporter.new],
    ENV,
    # Rails sets a custom backtrace filter;
    # this could get overridden, so make sure to specify.
    Minitest.backtrace_filter
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    # parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    include FactoryBot::Syntax::Methods

    setup do
      DatabaseCleaner.start

      WebMock.reset!

      # This starts PaperTrail's in-thread memory.
      RequestStore.begin!
    end

    teardown do
      # Clean up any stray locks.
      lock_keys = AdvisoryDB.redis.keys("lock:*")
      AdvisoryDB.redis.del(*lock_keys) if lock_keys.any?

      # Clean up any stray cache entries
      key_roots_to_clear = [
        DependencyGraph::Client::CACHE_KEY_ROOT,
        EcosystemRegistriesController::CACHE_KEY_ROOT,
        ReferencesCheck::CACHE_KEY_ROOT,
      ]

      cache_keys_to_clear = key_roots_to_clear.map { |root| AdvisoryDB.redis.keys("#{root}:#{Rails.env}:*") }

      ::GitHub::Telemetry::Logs.logger.debug { "Clearing #{cache_keys_to_clear.size} cache keys matching #{cache_keys_to_clear}:*" }
      AdvisoryDB.redis.del(*cache_keys_to_clear) if cache_keys_to_clear.any?

      DatabaseCleaner.clean

      AdvisoryDB.hydro_publisher.sink.messages.clear

      # This stops and resets PaperTrail's in-thread memory.
      RequestStore.end!
      RequestStore.clear!
    end

    def github_advisories_repo
      ENV.fetch("GITHUB_ADVISORIES_REPO")
    end

    def github_app_email
      ENV.fetch("GITHUB_APP_EMAIL")
    end

    def github_app_name
      ENV.fetch("GITHUB_APP_NAME")
    end

    def github_cvelist_repo
      ENV.fetch("GITHUB_CVELIST_REPO")
    end

    def curation_slack_channel
      ENV.fetch("CURATION_SLACK_CHANNEL", nil)
    end

    def nvd_api_key
      ENV.fetch("NVD_API_KEY", nil)
    end
  end
end

DatabaseCleaner.strategy = :transaction
