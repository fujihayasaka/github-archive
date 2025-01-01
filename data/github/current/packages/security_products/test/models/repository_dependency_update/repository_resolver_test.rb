# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class RepositoryDependencyUpdateRepositoryResolverTest < GitHub::TestCase
  include DependabotGithubAppHelper

  fixtures do
    # Set up the dependabot app
    make_trusted_oauth_apps_owner
    @dependabot_app = create(:dependabot_integration)

    @repository = create(:repository, from_example: :pull_request_fork)
    @repository.enable_vulnerability_updates(actor: @repository.owner)

    @pull_request = create(:pull_request, repository: @repository)

    @dependabot_install = @dependabot_app.install_on(
      @repository.owner,
      repositories: [],
      installer: @repository.owner,
      entry_point: :test_case
    ).installation

    @rails_vulnerability_1 = create :published_vulnerability, with_ranges: 0
    @rails_vulnerable_version_1 = create :vulnerable_version_range,
      vulnerability: @rails_vulnerability_1,
      affects:     "rails",
      requirements: "< 4.1.0",
      fixed_in: "4.1.0",
      ecosystem: "RubyGems"
    @rails_vulnerability_1.reload

    @rails_vulnerability_2 = create :published_vulnerability, with_ranges: 0
    @rails_vulnerable_version_2 = create :vulnerable_version_range,
      vulnerability: @rails_vulnerability_2,
      affects:     "rails",
      requirements: "< 4.1.1",
      fixed_in: "4.1.1",
      ecosystem: "RubyGems"
    @rails_vulnerability_2.reload

    @rails_vulnerability_3 = create :published_vulnerability, with_ranges: 0
    @rails_vulnerable_version_3 = create :vulnerable_version_range,
      vulnerability: @rails_vulnerability_3,
      affects:     "rails",
      requirements: ">= 4.0.0, < 5.0.0",
      fixed_in: nil,
      ecosystem: "RubyGems"
    @rails_vulnerability_3.reload

    @sinatra_vulnerability = create :published_vulnerability, with_ranges: 0
    @sinatra_vulnerable_version = create :vulnerable_version_range,
      vulnerability: @sinatra_vulnerability,
      affects:     "sinatra",
      requirements: "< 1.0.0",
      fixed_in: "1.0.0",
      ecosystem: "RubyGems"
    @rails_vulnerability_3.reload
  end

  setup do
    reset_dependabot_github_app_memoization
  end

  def resolver_for(repository, **kwargs)
    RepositoryDependencyUpdate::RepositoryResolver.new(repository, **T.unsafe(kwargs))
  end

  context "#create_updates" do
    test "does not create a dependency update from a vulnerability alert if the alert state is auto_dismissed" do
      npm_vulnerability = create :published_vulnerability
      npm_range = create :vulnerable_version_range,
        vulnerability: npm_vulnerability,
        affects:     "express.js",
        requirements: ">= 4.0.0",
        fixed_in: "3.9.9",
        ecosystem: "npm"

      auto_dismissed_alert = create(:repository_vulnerability_alert,
        :auto_dismissed,
        repository: @repository,
        vulnerable_manifest_path: "package-lock.json",
        vulnerability: npm_vulnerability,
        vulnerable_version_range: npm_range,
        dependency_scope: "development"
      )

      updates = resolver_for(@repository, trigger: :install).create_updates
      assert_empty updates
    end

    test "creates a dependency update from a vulnerability alert with instrumentation" do
      rails_alert_fixed_in_4_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      actual_payload = []
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload << payload
      end

      updates = resolver_for(@repository, trigger: :install).create_updates

      assert_equal 1, updates.length

      update = updates.first
      assert_predicate update, :valid?

      assert_equal rails_alert_fixed_in_4_1, update.repository_vulnerability_alert
      assert_equal @repository, update.repository
      assert_equal rails_alert_fixed_in_4_1.vulnerable_manifest_path, update.manifest_path
      assert_equal rails_alert_fixed_in_4_1.vulnerable_version_range.affects, update.package_name
      assert_equal "requested", update.state
      assert_equal "vulnerability", update.reason
      assert_equal "install", update.trigger_type
      refute update.dry_run

      assert_nil update.pull_request
      assert_nil update.body
      assert_nil update.error_body

      expected_payload = {
        repository_dependency_update: update,
        repository_vulnerability_alert: rails_alert_fixed_in_4_1,
        security_advisory: @rails_vulnerability_1.becomes(SecurityAdvisory),
        security_vulnerability: @rails_vulnerable_version_1.becomes(SecurityVulnerability),
        github_bot_install_id: @dependabot_install.id,
      }

      assert_equal expected_payload, actual_payload.first
    end

    test "creates a dependency update for each package with open alerts" do
      rails_alert_fixed_in_4_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      sinatra_alert_fixed_in_1_0 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @sinatra_vulnerability,
        vulnerable_version_range: @sinatra_vulnerable_version,
      )

      actual_payload = []
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload << payload
      end

      updates = resolver_for(@repository, trigger: :install).create_updates

      assert_equal 2, updates.length

      assert_same_elements %w[rails sinatra], updates.map(&:package_name).uniq
      assert_same_elements ["Gemfile.lock"], updates.map(&:manifest_path).uniq
      assert updates.all?  { |update| update.requested? }
      assert updates.all?  { |update| update.vulnerability? }
      assert updates.all?  { |update| update.install? }
      assert updates.none? { |update| update.dry_run? }

      assert_equal 2, actual_payload.length
    end

    test "creates a dependency update for each manifest path with open alerts" do
      app_1_gemfile_lock = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "app_1/Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      app_2_gemfile_lock = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "app_2/Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      updates = resolver_for(@repository, trigger: :manual).create_updates

      assert_equal 2, updates.length

      assert_same_elements ["rails"], updates.map(&:package_name).uniq
      assert_same_elements ["app_1/Gemfile.lock", "app_2/Gemfile.lock"], updates.map(&:manifest_path).uniq
      assert updates.all?  { |update| update.requested? }
      assert updates.all?  { |update| update.vulnerability? }
      assert updates.all?  { |update| update.manual? }
      assert updates.none? { |update| update.dry_run? }
    end

    test "creates updates for only fixable alerts" do
      rails_alert_unfixed = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_3,
        vulnerable_version_range: @rails_vulnerable_version_3,
      )

      sinatra_alert_fixed_in_1_0 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @sinatra_vulnerability,
        vulnerable_version_range: @sinatra_vulnerable_version,
      )

      actual_payload = []
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload << payload
      end

      updates = resolver_for(@repository, trigger: :install).create_updates

      assert_equal 1, updates.length

      update = updates.first
      assert_predicate update, :valid?

      assert_equal sinatra_alert_fixed_in_1_0, update.repository_vulnerability_alert
      assert_equal @repository, update.repository
      assert_equal sinatra_alert_fixed_in_1_0.vulnerable_manifest_path, update.manifest_path
      assert_equal sinatra_alert_fixed_in_1_0.vulnerable_version_range.affects, update.package_name
      assert_equal "requested", update.state
      assert_equal "vulnerability", update.reason
      assert_equal "install", update.trigger_type
      refute update.dry_run

      assert_nil update.pull_request
      assert_nil update.body
      assert_nil update.error_body

      expected_payload = {
        repository_dependency_update: update,
        repository_vulnerability_alert: sinatra_alert_fixed_in_1_0,
        security_advisory: @sinatra_vulnerability.becomes(SecurityAdvisory),
        security_vulnerability: @sinatra_vulnerable_version.becomes(SecurityVulnerability),
        github_bot_install_id: @dependabot_install.id,
      }

      assert_equal expected_payload, actual_payload.first
    end

    test "creates an update for alerts that supersede an existing update" do
      rails_alert_fixed_in_4_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      rails_4_1_update = create(:repository_dependency_update,
        :completed,
        repository: @repository,
        repository_vulnerability_alert: rails_alert_fixed_in_4_1,
        pull_request: @pull_request,
        manifest_path: "Gemfile.lock",
        package_name: "rails",
      )

      rails_alert_fixed_in_4_1_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_2,
        vulnerable_version_range: @rails_vulnerable_version_2,
      )

      actual_payload = []
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload << payload
      end

      updates = resolver_for(@repository, trigger: :install).create_updates

      assert_equal 1, updates.length

      update = updates.first
      assert_predicate update, :valid?

      assert_equal rails_alert_fixed_in_4_1_1, update.repository_vulnerability_alert
      assert_equal @repository, update.repository
      assert_equal rails_alert_fixed_in_4_1_1.vulnerable_manifest_path, update.manifest_path
      assert_equal rails_alert_fixed_in_4_1_1.vulnerable_version_range.affects, update.package_name
      assert_equal "requested", update.state
      assert_equal "vulnerability", update.reason
      assert_equal "install", update.trigger_type
      refute update.dry_run

      assert_nil update.pull_request
      assert_nil update.body
      assert_nil update.error_body

      expected_payload = {
        repository_dependency_update: update,
        repository_vulnerability_alert: rails_alert_fixed_in_4_1_1,
        security_advisory: @rails_vulnerability_2.becomes(SecurityAdvisory),
        security_vulnerability: @rails_vulnerable_version_2.becomes(SecurityVulnerability),
        github_bot_install_id: @dependabot_install.id,
      }

      assert_equal expected_payload, actual_payload.first
    end

    test "does not create updates for alerts that are superseded by an existing alert" do
      rails_alert_fixed_in_4_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      rails_alert_fixed_in_4_1_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_2,
        vulnerable_version_range: @rails_vulnerable_version_2,
      )

      rails_4_1_1_update = create(:repository_dependency_update,
        :completed,
        repository: @repository,
        repository_vulnerability_alert: rails_alert_fixed_in_4_1_1,
        pull_request: @pull_request,
        manifest_path: "Gemfile.lock",
        package_name: "rails",
      )

      actual_payload = []
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload << payload
      end

      updates = resolver_for(@repository, trigger: :install).create_updates

      assert_empty updates
      assert_empty actual_payload
    end

    test "creates an update for the highest fixed version given a set of alerts on the same package" do
      rails_alert_fixed_in_4_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      rails_alert_fixed_in_4_1_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_2,
        vulnerable_version_range: @rails_vulnerable_version_2,
      )

      rails_alert_unfixed = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_3,
        vulnerable_version_range: @rails_vulnerable_version_3,
      )

      actual_payload = []
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload << payload
      end

      updates = resolver_for(@repository, trigger: :install).create_updates

      assert_equal 1, updates.length

      update = updates.first
      assert_predicate update, :valid?

      assert_equal rails_alert_fixed_in_4_1_1, update.repository_vulnerability_alert
      assert_equal @repository, update.repository
      assert_equal rails_alert_fixed_in_4_1_1.vulnerable_manifest_path, update.manifest_path
      assert_equal rails_alert_fixed_in_4_1_1.vulnerable_version_range.affects, update.package_name
      assert_equal "requested", update.state
      assert_equal "vulnerability", update.reason
      assert_equal "install", update.trigger_type
      refute update.dry_run

      assert_nil update.pull_request
      assert_nil update.body
      assert_nil update.error_body

      expected_payload = {
        repository_dependency_update: update,
        repository_vulnerability_alert: rails_alert_fixed_in_4_1_1,
        security_advisory: @rails_vulnerability_2.becomes(SecurityAdvisory),
        security_vulnerability: @rails_vulnerable_version_2.becomes(SecurityVulnerability),
        github_bot_install_id: @dependabot_install.id,
      }

      assert_equal expected_payload, actual_payload.first
    end

    test "raises an exception for a trigger of `dry_run`" do
      assert_raises ArgumentError, "The 'dry_run' trigger is no longer supported" do
        resolver_for(@repository, trigger: :dry_run).create_updates
      end
    end

    test "raise an exception error for an invalid trigger" do
      assert_raises ArgumentError, "Unknown trigger 'random'" do
        resolver_for(@repository, trigger: :random).create_updates
      end
    end
  end

  context "setting a dependency_limit" do
    test "it only updates the specified number of distinct dependencies starting from the newest" do
      rails_alert_fixed_in_4_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      sinatra_alert_fixed_in_1_0 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @sinatra_vulnerability,
        vulnerable_version_range: @sinatra_vulnerable_version,
      )

      updates = resolver_for(@repository, trigger: :install, dependency_limit: 1).create_updates

      assert_equal 1, updates.length

      update = updates.first
      assert_predicate update, :valid?

      assert_equal sinatra_alert_fixed_in_1_0, update.repository_vulnerability_alert
      assert_equal @repository, update.repository
      assert_equal sinatra_alert_fixed_in_1_0.vulnerable_manifest_path, update.manifest_path
      assert_equal sinatra_alert_fixed_in_1_0.vulnerable_version_range.affects, update.package_name
      assert_equal "requested", update.state
      assert_equal "vulnerability", update.reason
      assert_equal "install", update.trigger_type
      refute update.dry_run

      assert_nil update.pull_request
      assert_nil update.body
      assert_nil update.error_body
    end

    test "it ignores any dependences that do not have any fixes" do
      sinatra_alert_fixed_in_1_0 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @sinatra_vulnerability,
        vulnerable_version_range: @sinatra_vulnerable_version,
      )

      rails_alert_unfixed = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_3,
        vulnerable_version_range: @rails_vulnerable_version_3,
      )

      updates = resolver_for(@repository, trigger: :install, dependency_limit: 1).create_updates

      assert_equal 1, updates.length

      update = updates.first
      assert_predicate update, :valid?

      assert_equal sinatra_alert_fixed_in_1_0, update.repository_vulnerability_alert
      assert_equal @repository, update.repository
      assert_equal sinatra_alert_fixed_in_1_0.vulnerable_manifest_path, update.manifest_path
      assert_equal sinatra_alert_fixed_in_1_0.vulnerable_version_range.affects, update.package_name
      assert_equal "requested", update.state
      assert_equal "vulnerability", update.reason
      assert_equal "install", update.trigger_type
      refute update.dry_run

      assert_nil update.pull_request
      assert_nil update.body
      assert_nil update.error_body
    end
  end
end unless GitHub.enterprise?
