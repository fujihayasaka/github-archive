# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class RepositoryDependencyUpdateAlertResolverTest < GitHub::TestCase
  include DependabotGithubAppHelper

  fixtures do
    @staff = create(:user, :staff)

    # Set up the dependabot app
    make_trusted_oauth_apps_owner
    @dependabot_app = create(:dependabot_integration)
    @dependabot_install_trigger = create(:dependency_update_requested_trigger, integration: @dependabot_app)

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
  end

  setup do
    reset_dependabot_github_app_memoization
  end

  def install_app
    @dependabot_install = @dependabot_app.install_on(
      @repository.owner,
      repositories: [],
      installer: @repository.owner,
      entry_point: :test_case
    ).installation
  end

  def resolver_for(alert, trigger:)
    RepositoryDependencyUpdate::AlertResolver.new(alert, trigger: trigger)
  end

  context "#create_update" do
    test "creates a dependency update from a vulnerability alert with instrumentation" do
      install_app

      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(alert, trigger: :manual).create_update

      assert_predicate update, :valid?

      assert_equal update.repository_vulnerability_alert, alert
      assert_equal update.repository, alert.repository
      assert_equal update.manifest_path, alert.vulnerable_manifest_path
      assert_equal update.package_name, alert.vulnerable_version_range.affects
      assert_equal update.state, "requested"
      assert_equal update.reason, "vulnerability"
      assert_equal update.trigger_type, "manual"
      assert_equal update.dry_run, false

      assert_nil update.pull_request
      assert_nil update.body
      assert_nil update.error_body

      expected_payload = {
        repository_dependency_update: update,
        repository_vulnerability_alert: alert,
        security_advisory: alert.vulnerability.becomes(SecurityAdvisory),
        security_vulnerability: alert.vulnerable_version_range.becomes(SecurityVulnerability),
        github_bot_install_id: @dependabot_install.id,
      }

      assert_equal expected_payload, actual_payload
    end

    test "returns false if the vulnerability alert manifest path is not supported" do
      install_app

      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile")

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(alert, trigger: :manual).create_update

      assert_equal false, update
      assert_empty actual_payload
    end

    test "returns false for a dismissed alert" do
      alert = create(:repository_vulnerability_alert, :dismissed, repository: @repository)

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(alert, trigger: :manual).create_update

      assert_equal false, update
      assert_empty actual_payload
    end

    test "returns false if the alert is not fixable" do
      vulnerability = create :published_vulnerability
      vulnerable_version_range = create :vulnerable_version_range,
        vulnerability: vulnerability,
        affects: "rails",
        requirements: "= 3.2.0",
        fixed_in: nil

      alert = create(:repository_vulnerability_alert,
                     repository: @repository,
                     vulnerability: vulnerability,
                     vulnerable_version_range: vulnerable_version_range,
                     vulnerable_manifest_path: "Gemfile.lock")

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(alert, trigger: :manual).create_update

      assert_equal false, update
      assert_empty actual_payload
    end

    test "returns false if the repository has not enabled vulnerability alerts" do
      @repository.disable_vulnerability_alerts(actor: @repository.owner)
      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(alert, trigger: :manual).create_update

      assert_equal false, update
      assert_empty actual_payload
    end

    test "returns false if the repository is broken" do
      assert @repository.access.mark_broken_git_repository
      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(alert, trigger: :manual).create_update

      assert_equal false, update
      assert_empty actual_payload
    end

    test "returns false if the repository has a DMCA takedown notice" do
      assert @repository.access.disable("dmca", @staff, dmca_takedown: "https://github.com/github/dmca/blob/master/2020/2020-04-07-bad_stuff.md")

      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(alert, trigger: :manual).create_update

      assert_equal false, update
      assert_empty actual_payload
    end

    test "returns false if the repository owner has a full trade control restriction" do
      @repository.owner.trade_controls_restriction.full!
      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(alert, trigger: :manual).create_update

      assert_equal false, update
      assert_empty actual_payload
    end

    test "returns false if the repository is owned by an org with a partial trade control restriction" do
      restricted_organization = create(:organization)
      restricted_organization.trade_controls_restriction.partial! # partial restrictions are limited to orgs

      restricted_repository = create(:repository, owner: restricted_organization)

      alert = create(:repository_vulnerability_alert, repository: restricted_repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(alert, trigger: :manual).create_update

      assert_equal false, update
      assert_empty actual_payload
    end

    test "returns false if the alert has a blank manifest path" do
      alert = create(:repository_vulnerability_alert, repository: @repository)
      alert.vulnerable_manifest_path = ""
      alert.save!(validate: false)

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(alert, trigger: :manual).create_update

      assert_equal false, update
      assert_empty actual_payload
    end

    test "returns false if the alert is for an ecosystem not supported for Dependabot Security Updates" do
      vulnerability = create(:published_vulnerability)
      vulnerable_version = create(:vulnerable_version_range,
                                  vulnerability: vulnerability,
                                  ecosystem: "test_preview_eco",
                                  affects:     "fakeage",
                                  requirements: "< 1.0.0",
                                  fixed_in: "1.0.0")

      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerability: vulnerability,
                                                      vulnerable_version_range: vulnerable_version,
                                                      vulnerable_manifest_path: "mock.json")

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(alert, trigger: :manual).create_update

      assert_equal false, update
      assert_empty actual_payload
    end
  end

  context "#create_update with a manual trigger" do
    test "installs the dependabot app automatically if no installation exists" do
      refute_predicate Repositories::Public.find_active!(@repository.id), :dependabot_installed?

      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      perform_enqueued_jobs(only: InstallAutomaticIntegrationsJob) do
        resolver_for(alert, trigger: :manual).create_update
      end

      assert_predicate Repositories::Public.find_active!(@repository.id), :dependabot_installed?
    end

    test "creates a new update if a requested update exists for the alert" do
      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      update = resolver_for(alert, trigger: :manual).create_update
      refute_predicate update, :proposed_change_exists?

      assert_predicate update, :requested?

      assert_equal 1, alert.repository_dependency_updates.count

      resolver_for(alert, trigger: :manual).create_update

      assert_equal 2, alert.repository_dependency_updates.count
    end

    test "creates a new update if a completed update exists for the alert" do
      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      update = resolver_for(alert, trigger: :manual).create_update
      update.mark_as_complete(pull_request: @pull_request)

      assert_predicate update, :complete?
      assert_predicate update, :proposed_change_exists?

      assert_equal 1, alert.repository_dependency_updates.count

      resolver_for(alert, trigger: :manual).create_update

      assert_equal 2, alert.repository_dependency_updates.count
    end

    test "creates a new update if a completed update exists for the alert, and the pull request associated is closed" do
      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      update = resolver_for(alert, trigger: :manual).create_update
      update.mark_as_complete(pull_request: @closed_pull_request)

      assert_predicate update, :complete?
      assert_predicate update, :proposed_change_exists?

      assert_equal 1, alert.repository_dependency_updates.count

      resolver_for(alert, trigger: :manual).create_update

      assert_equal 2, alert.repository_dependency_updates.count
    end

    test "creates a new update if a completed update exists for the alert, and the pull request associated is merged" do
      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      update = resolver_for(alert, trigger: :manual).create_update
      update.mark_as_complete(pull_request: @merged_pull_request)

      assert_predicate update, :complete?
      assert_predicate update, :proposed_change_exists?

      assert_equal 1, alert.repository_dependency_updates.count

      resolver_for(alert, trigger: :manual).create_update

      assert_equal 2, alert.repository_dependency_updates.count
    end

    test "creates a new update even if an errored update exists for the alert" do
      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      update = resolver_for(alert, trigger: :manual).create_update
      update.mark_as_errored(title: "Nope.", body: "Nope nope nope.", type: "unknown_error")

      assert_predicate update, :error?
      refute_predicate update, :proposed_change_exists?

      assert_equal 1, alert.repository_dependency_updates.count

      resolver_for(alert, trigger: :manual).create_update

      assert_equal 2, alert.repository_dependency_updates.count
    end

    test "creates a new update even if the repository has not enabled vulnerability updates" do
      @repository.disable_vulnerability_updates(actor: @repository.owner)
      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      update = resolver_for(alert, trigger: :manual).create_update

      assert_predicate update, :valid?

      assert_equal update.repository_vulnerability_alert, alert
      assert_equal update.repository, alert.repository
      assert_equal update.manifest_path, alert.vulnerable_manifest_path
      assert_equal update.package_name, alert.vulnerable_version_range.affects
      assert_equal update.state, "requested"
      assert_equal update.reason, "vulnerability"
      assert_equal update.trigger_type, "manual"
      assert_equal update.dry_run, false

      assert_nil update.pull_request
      assert_nil update.body
      assert_nil update.error_body
    end
  end

  # All of these triggers have the same behaviour
  %w(scan push install).each do |trigger_type|
    context "create_update with a '#{trigger_type}' trigger" do
      test "installs the dependabot app automatically" do
        refute_predicate Repositories::Public.find_active!(@repository.id), :dependabot_installed?

        alert = create(:repository_vulnerability_alert, repository: @repository,
                                                        vulnerable_manifest_path: "Gemfile.lock")

        perform_enqueued_jobs(only: InstallAutomaticIntegrationsJob) do
          resolver_for(alert, trigger: trigger_type).create_update
        end

        assert_predicate Repositories::Public.find_active!(@repository.id), :dependabot_installed?
      end

      test "installs dependabot if the repo has an update-specific alert rule" do
        refute_predicate Repositories::Public.find_active!(@repository.id), :dependabot_installed?

        @repository.disable_vulnerability_updates(actor: @repository.owner)
        refute_predicate Repositories::Public.find_active!(@repository.id), :vulnerability_updates_enabled?

        alert = create(:repository_vulnerability_alert, repository: @repository,
                                                        vulnerable_manifest_path: "Gemfile.lock")
        create(:vulnerability_alert_rule, {
          name: "Update Rule",
          target_type: "Repository",
          target_id: @repository.id,
          conditions: {
            ecosystem: [alert.ecosystem],
          },
          actions: {
            version: 1,
            alert_actions: {
              auto_dismiss: "until_patch",
            },
            update_actions: {
              create_pr: true
            },
          }
        })

        perform_enqueued_jobs(only: InstallAutomaticIntegrationsJob) do
          resolver_for(alert, trigger: trigger_type).create_update
        end

        assert_predicate Repositories::Public.find_active!(@repository.id), :dependabot_installed?
      end

      test "returns false if the alert already has a requested update" do
        alert = create(:repository_vulnerability_alert, repository: @repository,
                                                        vulnerable_manifest_path: "Gemfile.lock")

        update = resolver_for(alert, trigger: :manual).create_update

        assert_predicate update, :requested?
        refute_predicate update, :proposed_change_exists?

        assert_same_elements [update], alert.repository_dependency_updates

        refute resolver_for(alert, trigger: trigger_type).create_update
        assert_same_elements [update], alert.repository_dependency_updates
      end

      test "returns false if the alert already has a completed update" do
        alert = create(:repository_vulnerability_alert, repository: @repository,
                                                        vulnerable_manifest_path: "Gemfile.lock")

        update = resolver_for(alert, trigger: :manual).create_update
        update.mark_as_complete(pull_request: @pull_request)

        assert_predicate update, :complete?
        assert_predicate update, :proposed_change_exists?

        assert_same_elements [update], alert.repository_dependency_updates

        refute resolver_for(alert, trigger: trigger_type).create_update
        assert_same_elements [update], alert.repository_dependency_updates
      end

      test "returns false if the alert already has a completed update, and the pull request associated is closed" do
        alert = create(:repository_vulnerability_alert, repository: @repository,
                                                        vulnerable_manifest_path: "Gemfile.lock")

        update = resolver_for(alert, trigger: :manual).create_update
        update.mark_as_complete(pull_request: @closed_pull_request)

        assert_predicate update, :complete?
        assert_predicate update, :proposed_change_exists?

        assert_same_elements [update], alert.repository_dependency_updates

        refute resolver_for(alert, trigger: trigger_type).create_update
        assert_same_elements [update], alert.repository_dependency_updates
      end

      test "returns false if the alert already has a completed update, and the pull request associated is merged" do
        alert = create(:repository_vulnerability_alert, repository: @repository,
                                                        vulnerable_manifest_path: "Gemfile.lock")

        update = resolver_for(alert, trigger: :manual).create_update
        update.mark_as_complete(pull_request: @merged_pull_request)

        assert_predicate update, :complete?
        assert_predicate update, :proposed_change_exists?

        assert_same_elements [update], alert.repository_dependency_updates

        refute resolver_for(alert, trigger: trigger_type).create_update
        assert_same_elements [update], alert.repository_dependency_updates
      end

      test "returns false if the repository has not enabled vulnerability updates" do
        @repository.disable_vulnerability_updates(actor: @repository.owner)
        alert = create(:repository_vulnerability_alert, repository: @repository,
                                                        vulnerable_manifest_path: "Gemfile.lock")

        actual_payload = T.let({}, T.untyped)
        GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
          actual_payload = payload
        end

        update = resolver_for(alert, trigger: trigger_type).create_update

        assert_equal false, update
        assert_empty actual_payload
      end
    end

    context "automatic retries for a '#{trigger_type}' trigger" do
      test "it creates a new update even if the alert already has an errored update" do
        alert = create(:repository_vulnerability_alert, repository: @repository,
                                                        vulnerable_manifest_path: "Gemfile.lock")

        update = resolver_for(alert, trigger: trigger_type).create_update
        update.mark_as_errored(title: "Nope.", body: "Nope nope nope.", type: "unknown_error")

        assert_predicate update, :error?
        refute_predicate update, :proposed_change_exists?

        assert_same_elements [update], alert.repository_dependency_updates

        assert new_update = resolver_for(alert, trigger: trigger_type).create_update

        assert_same_elements [update, new_update], alert.repository_dependency_updates.reload
      end

      test "it will not create a new update if 3 errored rows exist in the last 30 days" do
        alert = create(:repository_vulnerability_alert, repository: @repository,
                                                        vulnerable_manifest_path: "Gemfile.lock")

        Timecop.freeze(29.days.ago) do
          create_list(:repository_dependency_update,
                      RepositoryDependencyUpdate::AlertResolver::MAX_RETRIES,
                      :errored,
                      repository: @repository,
                      repository_vulnerability_alert: alert)
        end

        assert_equal 3, alert.repository_dependency_updates.count

        refute resolver_for(alert, trigger: trigger_type).create_update
        assert_equal 3, alert.repository_dependency_updates.count
      end

      test "it will create a new update if 3 errored rows exist, but one is older than 30 days" do
        alert = create(:repository_vulnerability_alert, repository: @repository,
                                                        vulnerable_manifest_path: "Gemfile.lock")

        Timecop.freeze(29.days.ago) do
          create_list(:repository_dependency_update,
                      RepositoryDependencyUpdate::AlertResolver::MAX_RETRIES - 1,
                      :errored,
                      repository: @repository,
                      repository_vulnerability_alert: alert)
        end

        Timecop.freeze(31.days.ago) do
          create(:repository_dependency_update,
                 :errored,
                 repository: @repository,
                 repository_vulnerability_alert: alert)
        end

        assert_equal 3, alert.repository_dependency_updates.count

        assert new_update = resolver_for(alert, trigger: trigger_type).create_update
        assert_equal 4, alert.repository_dependency_updates.count
      end
    end
  end

  context "create_update with a dry_run trigger" do
    test "raises an exception" do
      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      assert_raises ActiveRecord::RecordInvalid do
        resolver_for(alert, trigger: :dry_run).create_update
      end
    end
  end

  context "create_update with a spammy owner" do
    test "returns false if the repository owner is marked as spammy" do
      @repository.owner.mark_as_spammy
      alert = create(:repository_vulnerability_alert, repository: @repository,
                                                      vulnerable_manifest_path: "Gemfile.lock")

      actual_payload = T.let({}, T.untyped)
      GlobalInstrumenter.subscribe("repository_dependency_update.created.vulnerability") do |_event, _, _, _, payload|
        actual_payload = payload
      end

      update = resolver_for(alert, trigger: :push).create_update

      assert_equal false, update
      assert_empty actual_payload
    end
  end
end unless GitHub.enterprise?
