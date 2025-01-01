# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class RepositoryDependencyUpdateDependencyResolverTest < GitHub::TestCase
  include DependabotGithubAppHelper

  fixtures do
    # Set up the dependabot app
    make_trusted_oauth_apps_owner
    @dependabot_app = create(:dependabot_integration)

    @repository = create(:repository, from_example: :pull_request_fork)
    @repository.enable_vulnerability_updates(actor: @repository.owner)

    @pull_request = create(:pull_request, repository: @repository)

    @closed_pull_request = create(:pull_request,
                                  repository: @repository,
                                  head_ref: "topic-rebased-on-master").tap(&:close)
    assert_predicate @closed_pull_request, :closed?

    @merged_pull_request = create(:pull_request,
                                  repository: @repository,
                                  head_ref: "ahead").tap(&:merge)
    assert_predicate @merged_pull_request, :merged?

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
    @sinatra_vulnerability.reload
  end

  setup do
    reset_dependabot_github_app_memoization
  end

  def resolver_for(manifest_path:, package_name:, trigger: :scan)
    RepositoryDependencyUpdate::DependencyResolver.new(repository: @repository,
                                                       manifest_path: manifest_path,
                                                       package_name: package_name,
                                                       trigger: trigger)
  end

  context "#create_update" do
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

      update = resolver_for(manifest_path: "package-lock.json", package_name: "express").create_update
      refute update
    end

    test "given a repository with a set of alerts on a single manifest, it creates an update for the newest fixed version of the target package" do
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

      sinatra_alert_fixed_in_1_0 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @sinatra_vulnerability,
        vulnerable_version_range: @sinatra_vulnerable_version,
      )

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(manifest_path: "Gemfile.lock", package_name: "rails").create_update

      assert_predicate update, :valid?

      assert_equal rails_alert_fixed_in_4_1_1, update.repository_vulnerability_alert
      assert_equal @repository, update.repository
      assert_equal rails_alert_fixed_in_4_1_1.vulnerable_manifest_path, update.manifest_path
      assert_equal rails_alert_fixed_in_4_1_1.vulnerable_version_range.affects, update.package_name
      assert_equal "requested", update.state
      assert_equal "vulnerability", update.reason
      assert_equal "scan", update.trigger_type
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

      assert_equal expected_payload, actual_payload
    end

    test "given a dependency with two alerts suggesting the same version, it creates an update for the newest alert" do
      rails_alert_fixed_in_4_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      newer_vulnerability = create :published_vulnerability, with_ranges: 0
      newer_vulnerable_version = create :vulnerable_version_range,
        vulnerability: newer_vulnerability,
        affects: "rails",
        requirements: "< 4.1.0",
        fixed_in: "4.1.0",
        ecosystem: "RubyGems"
      newer_vulnerability.reload

      newer_fixed_in_4_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: newer_vulnerability,
        vulnerable_version_range: newer_vulnerable_version,
      )

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(manifest_path: "Gemfile.lock", package_name: "rails").create_update

      assert_predicate update, :valid?

      assert_equal newer_fixed_in_4_1, update.repository_vulnerability_alert
      assert_equal @repository, update.repository
      assert_equal newer_fixed_in_4_1.vulnerable_manifest_path, update.manifest_path
      assert_equal newer_fixed_in_4_1.vulnerable_version_range.affects, update.package_name
      assert_equal "requested", update.state
      assert_equal "vulnerability", update.reason
      assert_equal "scan", update.trigger_type
      refute update.dry_run

      assert_nil update.pull_request
      assert_nil update.body
      assert_nil update.error_body

      expected_payload = {
        repository_dependency_update: update,
        repository_vulnerability_alert: newer_fixed_in_4_1,
        security_advisory: newer_vulnerability.becomes(SecurityAdvisory),
        security_vulnerability: newer_vulnerable_version.becomes(SecurityVulnerability),
        github_bot_install_id: @dependabot_install.id,
      }

      assert_equal expected_payload, actual_payload
    end

    test "given a dependency with a fully resolved dependency update for an older version of the target package" do
      rails_alert_fixed_in_4_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      existing_update = RepositoryDependencyUpdate::AlertResolver.new(rails_alert_fixed_in_4_1, trigger: :scan).create_update
      existing_update.mark_as_complete(pull_request: @merged_pull_request)

      rails_alert_fixed_in_4_1.delete # Once an alert is resolved it gets pruned

      rails_alert_fixed_in_4_1_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_2,
        vulnerable_version_range: @rails_vulnerable_version_2,
      )

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(manifest_path: "Gemfile.lock", package_name: "rails").create_update

      assert_predicate update, :valid?

      assert_equal rails_alert_fixed_in_4_1_1, update.repository_vulnerability_alert
      assert_equal @repository, update.repository
      assert_equal rails_alert_fixed_in_4_1_1.vulnerable_manifest_path, update.manifest_path
      assert_equal rails_alert_fixed_in_4_1_1.vulnerable_version_range.affects, update.package_name
      assert_equal "requested", update.state
      assert_equal "vulnerability", update.reason
      assert_equal "scan", update.trigger_type
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

      assert_equal expected_payload, actual_payload
    end

    test "given a dependency with an open update pull request for an older version of the target package" do
      rails_alert_fixed_in_4_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      existing_update = RepositoryDependencyUpdate::AlertResolver.new(rails_alert_fixed_in_4_1, trigger: :scan).create_update
      existing_update.mark_as_complete(pull_request: @pull_request)

      rails_alert_fixed_in_4_1_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_2,
        vulnerable_version_range: @rails_vulnerable_version_2,
      )

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(manifest_path: "Gemfile.lock", package_name: "rails").create_update

      assert_predicate update, :valid?

      assert_equal rails_alert_fixed_in_4_1_1, update.repository_vulnerability_alert
      assert_equal @repository, update.repository
      assert_equal rails_alert_fixed_in_4_1_1.vulnerable_manifest_path, update.manifest_path
      assert_equal rails_alert_fixed_in_4_1_1.vulnerable_version_range.affects, update.package_name
      assert_equal "requested", update.state
      assert_equal "vulnerability", update.reason
      assert_equal "scan", update.trigger_type
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

      assert_equal expected_payload, actual_payload
    end

    test "given a dependency with a closed update pull request for an older version of the target package" do
      rails_alert_fixed_in_4_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      existing_update = RepositoryDependencyUpdate::AlertResolver.new(rails_alert_fixed_in_4_1, trigger: :scan).create_update
      existing_update.mark_as_complete(pull_request: @closed_pull_request)

      rails_alert_fixed_in_4_1_1 = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_2,
        vulnerable_version_range: @rails_vulnerable_version_2,
      )

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(manifest_path: "Gemfile.lock", package_name: "rails").create_update

      assert_predicate update, :valid?

      assert_equal rails_alert_fixed_in_4_1_1, update.repository_vulnerability_alert
      assert_equal @repository, update.repository
      assert_equal rails_alert_fixed_in_4_1_1.vulnerable_manifest_path, update.manifest_path
      assert_equal rails_alert_fixed_in_4_1_1.vulnerable_version_range.affects, update.package_name
      assert_equal "requested", update.state
      assert_equal "vulnerability", update.reason
      assert_equal "scan", update.trigger_type
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

      assert_equal expected_payload, actual_payload
    end

    test "returns false if no alerts exist for the given dependency" do
      rails_alert = create(:repository_vulnerability_alert,
        :open,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(manifest_path: "yarn.lock", package_name: "node").create_update

      refute update
      assert_empty actual_payload
    end

    test "returns false if only dismissed alerts exist for the given dependency" do
      dismissed_rails_alert = create(:repository_vulnerability_alert,
        :dismissed,
        repository: @repository,
        vulnerable_manifest_path: "Gemfile.lock",
        vulnerability: @rails_vulnerability_1,
        vulnerable_version_range: @rails_vulnerable_version_1,
      )

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(manifest_path: "Gemfile.lock", package_name: "rails").create_update

      refute update
      assert_empty actual_payload
    end

    test "raises an exception for a trigger of `dry_run`" do
      assert_raises ArgumentError, "The 'dry_run' trigger is no longer supported" do
        resolver_for(manifest_path: anything, package_name: anything, trigger: :dry_run).create_update
      end
    end

    test "raise an exception error for an invalid trigger" do
      assert_raises ArgumentError, "Unknown trigger 'random'" do
        resolver_for(manifest_path: anything, package_name: anything, trigger: :random).create_update
      end
    end
  end
end unless GitHub.enterprise?
