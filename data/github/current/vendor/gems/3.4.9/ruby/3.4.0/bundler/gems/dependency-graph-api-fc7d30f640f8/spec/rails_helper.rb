# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV["RAILS_ENV"] ||= "test"

# GitHub Telemetry Logger Settings

# OpenTelemetry Log Level
# Generally does not need to be adjusted unless you are debugging issues
# with OpenTelemtry adapters or tracing attributes.
ENV["OTEL_LOG_LEVEL"] = "warn"

# These levels are set really high by default to avoid noise from
# intentional failure cases in the tests.

# Sets global logger level
# Logs from DependencyGraph.logger obey this level.
ENV["GITHUB_TELEMETRY_LOGS_LEVEL"] = "fatal"

# Sets library logger level
# Library loggers use this, eg. ActiveRecord query logs
ENV["GITHUB_TELEMETRY_LOGS_LIB_LEVEL"] = "fatal"

# Use the synchronous logger to ensure we get all logs locally
ENV["GITHUB_TELEMETRY_LOGS_ENABLE_SYNC_APPENDER"] = "true"

# *Do* output logs to stdout for tests
ENV["GITHUB_TELEMETRY_LOGS_STDOUT"] = "true"

# *Do not* output logs to a file (log/test.log)
ENV["GITHUB_TELEMETRY_LOGS_FILE"] = "false"

require File.expand_path("../../config/environment", __FILE__)
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "spec_helper"
require "rspec/rails"
require "chatops/controller/rspec"
require "vcr"
# Add additional requires below this line. Rails is not loaded until this point!

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

# Checks for pending migration and applies them before tests are run.
# If you are not using ActiveRecord, you can remove this line.
ActiveRecord::Migration.maintain_test_schema!

# We use this to rebuild views without any disruption
# Using DDL during tests breaks transaction rollback but we also don't need to
# avoid the disruption here so just do something simple
require "table_swap"
class TableSwap
  def with_swap
    connection.execute("DELETE FROM #{@table_name}")
    yield(@table_name)
  end
end

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = ["#{::Rails.root}/spec/fixtures"]

  config.use_transactional_fixtures = true

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.define_derived_metadata(file_path: Regexp.new("/spec/graphql/")) do |metadata|
    metadata[:type] = :graphql
  end

  config.include RSpec::Rails::RequestExampleGroup, type: :graphql
  config.include GraphQLHelpers, type: :graphql

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, :type => :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://relishapp.com/rspec/rspec-rails/docs
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  module ResponseParsing
    def response_json
      JSON.parse(response.body).with_indifferent_access
    end
  end

  module GraphQL
    module Deprecation
      def self.warn(message)
        nil
      end
    end
  end

  module TestHelpers
    class Factory
      def given_package(package_name, version, package_manager = nil, package_opts = {})
        PackageFactory.new(package_name, version, package_manager).tap do |p|
          p.create({}, package_opts)
        end
      end

      def given_manifest(**args)
        ManifestFactory.new(**args).tap(&:create)
      end

      def given_dependency(attrs)
        requirements = Versioning::RequirementSet
          .deserialize(attrs.fetch(:requirements), allow_named_versions: false)

        PackageDependency.create!(attrs.reverse_merge({
          package_manager:     Types::PackageManager[:rubygems],
          encoded_lower_bound: requirements.encoded_lower_bound,
          encoded_upper_bound: requirements.encoded_upper_bound,
        }))
      end

      def given_manifest_dependency(attrs)
        requirements = Versioning::RequirementSet
          .deserialize(attrs.fetch(:requirements), allow_named_versions: false)

        manifest = given_manifest.get

        ManifestDependency.create!(attrs.reverse_merge({
          manifest_id: manifest.id,
          encoded_lower_bound:   requirements.encoded_lower_bound,
          encoded_upper_bound:   requirements.encoded_upper_bound,
          last_seen_at_revision: 1,
        }))
      end

      def given_vulnerable_version_range(attrs)
        requirements = Versioning::RequirementSet
          .deserialize(attrs.fetch(:version_range), allow_named_versions: true)

        VulnerableVersionRange.create!(attrs.reverse_merge({
          github_id:           100,
          encoded_lower_bound: requirements.encoded_lower_bound,
          encoded_upper_bound: requirements.encoded_upper_bound,
        }))
      end

      def given_corresponding_manifest_for_package(package, attrs = {})
        repository = Repository.where({
          github_repository_id: package.github_repository_id
        }.merge(attrs.slice(:github_repository_id))).first_or_create!

        Manifest.create!({
          repository:      repository,
          manifest_type:   :gemspec,
          name:            package.name,
          package_manager: package.package_manager || :rubygems,
          latest_git_ref:  "abc",
          last_pushed_at:  Time.now,
        }.merge(attrs.except(:github_repository_id)))
      end

      def given_repository(attrs = {})
        Repository.create(attrs.reverse_merge({
          github_owner_id: Random.rand(99_999_999),
          github_repository_id: Random.rand(99_999_999),
          nwo: "github/github",
        }))
      end
    end

    def get_package(package_name)
      Package.where(name: package_name).first!
    end

    def get_package_release(package, version)
      get_package(package).releases.published.where(version: version).first!
    end

    def get_repo(repo_id:)
      Repository.where(github_repository_id: repo_id).first!
    end

    def get_manifest(repo_id:, ref: nil, **options)
      scope = get_repo(repo_id: repo_id).manifests
      scope = scope.where({ latest_git_ref: ref }) if ref.present?
      scope = scope.where(options) if options.present?
      scope.first!
    end

    def get_manifest_dependency(name)
      ManifestDependency.where(package_name: name)
    end

    def get_manifest_entry(name)
      # ugh
      ManifestEntry.where(
        manifest_package_version: ManifestPackageVersion.where(
          manifest_package: ManifestPackage.where(
            package_name: name
          )
        )
      )
    end

    def run_consumer(processor)
      consumer = processor.spec_consumer
      consumer.each_message do |msg|
        processor.process_with_consumer(msg, consumer)
      end
      processor.spec_reset
    end

    def factory(&block)
      block_given? ? Factory.new.instance_eval(&block) : Factory.new
    end
  end

  config.include TestHelpers
  config.include ResponseParsing, type: :request

  VCR.configure do |config|
    # What's this, you ask? Looks like when we moved to Dockerized
    # external datastores for DG-API for CI/local dev (Azurite,
    # Redis, Kafka, etc.) we set VCR to *ignore* (allow live HTTP)
    # for all test requests that go out to Docker, including localhost.
    # This is good, but keeps DS-API bound Twirp at localhost:9597 from
    # respecting or recording new cassettes for test cases. So I added
    # an override to the behavior specific for localhost:9597.
    #
    # To re-record the VCR cassettes for DS-API Twirp tests:
    # - Delete the appropriate cassette files
    # - Run DS-API's `script/server` on latest checkout
    # - Run DG-API's Docker setup (`script/start-containers`)
    # - Run DG-API's test suite
    #
    # NOTE: there are other VCR cassettes referenced in tests that probably
    # don't use them any more, given the hosts ignored here. Beware!
    config.ignore_request do |req|
      uri = URI(req.uri)
      %w[127.0.0.1 localhost].include?(uri.host) && ![9597, 9598].include?(uri.port)
    end

    config.allow_http_connections_when_no_cassette = true
    config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
    config.hook_into :webmock
    config.configure_rspec_metadata!
  end

end
