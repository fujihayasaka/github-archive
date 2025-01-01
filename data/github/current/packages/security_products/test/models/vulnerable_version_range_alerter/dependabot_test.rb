# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class VulnerableVersionRangeAlerterEmittingMessagesToDependabotTest < GitHub::TestCase
  include HydroTestHelpers
  include DependabotGithubAppHelper
  include DependabotAlertsEnterpriseEnablementHelper

  fixtures do
    # Set up the dependabot app
    make_trusted_oauth_apps_owner
    @dependabot_app = create(:dependabot_integration)

    @vulnerability = create :published_vulnerability
    @range = create :vulnerable_version_range,
      vulnerability: @vulnerability,
      affects:     "rake",
      requirements: "< 10.5.0",
      fixed_in: "10.5.0"
    @event = create :vulnerability_alerting_event, :on_process_alerts,
      vulnerability: @vulnerability
    @process = create :vulnerable_version_range_alerting_process,
      vulnerable_version_range: @range,
      vulnerability_alerting_event: @event

    @repository = create(:repository)

    # If we are testing for Enterprise, ensure Dependency Graph is enabled
    # as it is a prerequisite of Repository#enable_vulnerability_updates
    if GitHub.enterprise?
      enable_dependabot_alerts_for_enterprise_instance(@repository.owner)
    end
    @repository.enable_vulnerability_updates(actor: @repository.owner)

    @dependabot_install = @dependabot_app.install_on(
      @repository.owner,
      repositories: [],
      installer: @repository.owner,
      entry_point: :test_case
    ).installation
  end

  setup do
    GitHub.stubs(dependabot_enabled?: true) if GitHub.enterprise?

    stub_dependents_query
    @alerter = VulnerableVersionRangeAlerter.new(@process)
    reset_dependabot_github_app_memoization
  end

  def process_alertable_repos
    perform_enqueued_jobs(only: Dependabot::RepositoryVulnerabilityCreatedJob) do
      @alerter.process_alertable_repos
      run_processor(GitHub::StreamProcessors::DependabotAlerts::VulnerableDependencyProcessor.new, skip_query_counter: true)
    end
  end

  test "it requests a dependency update for the alert's package" do
    assert_empty @repository.dependency_updates

    process_alertable_repos

    refute_empty @repository.dependency_updates

    dependency_update = @repository.dependency_updates.first

    assert_equal "requested", dependency_update.state
    assert_equal "vulnerability", dependency_update.reason
    assert_equal "scan", dependency_update.trigger_type
    assert_equal "Gemfile.lock", dependency_update.manifest_path
    assert_equal "rake", dependency_update.package_name

    assert_hydro_published({
      repository_vulnerability_alert: @repository.repository_vulnerability_alerts.last.hydro_entity_payload,
      repository: Hydro::EntitySerializer.repository(@repository),
      owner: Hydro::EntitySerializer.user(@repository.owner),
      security_advisory: @vulnerability.becomes(SecurityAdvisory).hydro_entity_payload,
      security_vulnerability: @range.becomes(SecurityVulnerability).hydro_entity_payload,
      trigger: "scan",
      description: @vulnerability.description,
      github_bot_install_id: @dependabot_install.id.to_s,
      repository_dependency_update_id: dependency_update.id.to_s,
      dry_run: false,
    }, schema: "github.v1.RepositoryVulnerabilityAlertCreate")
  end

  test "it does not request dependency updates if the repository config has it disabled" do
    @repository.disable_vulnerability_updates(actor: @repository.owner)

    assert_empty @repository.dependency_updates

    process_alertable_repos

    assert_empty @repository.dependency_updates

    refute_hydro_messages(schema: "github.v1.RepositoryVulnerabilityAlertCreate")
  end

  test "it does not request dependency updates if the repository is deleted" do
    @alert = create(:repository_vulnerability_alert, :open, repository: @repository)
    @repository.delete

    assert_no_changes -> { RepositoryDependencyUpdate.count } do
      perform_enqueued_jobs(only: Dependabot::RepositoryVulnerabilityCreatedJob) do
        Dependabot::RepositoryVulnerabilityCreatedJob.perform_later(@alert.id)
      end
    end
  end

  test "it does not request dependency updates if the repository owner is deleted" do
    @alert = create(:repository_vulnerability_alert, :open, repository: @repository)
    @repository.owner.delete

    assert_no_changes -> { RepositoryDependencyUpdate.count } do
      perform_enqueued_jobs(only: Dependabot::RepositoryVulnerabilityCreatedJob) do
        Dependabot::RepositoryVulnerabilityCreatedJob.perform_later(@alert.id)
      end
    end
  end

  test "it does not request dependency updates if the alert is deleted" do
    @alert = create(:repository_vulnerability_alert, :open, repository: @repository)
    alert_id = @alert.id
    @alert.delete

    assert_no_changes -> { RepositoryDependencyUpdate.count } do
      perform_enqueued_jobs(only: Dependabot::RepositoryVulnerabilityCreatedJob) do
        Dependabot::RepositoryVulnerabilityCreatedJob.perform_later(alert_id)
      end
    end
  end

  test "it does not request a dependency update if the owner is spammy" do
    skip unless GitHub.spamminess_check_enabled? # Spam checking is disabled in Enterprise

    @alert = create(:repository_vulnerability_alert, :open, repository: @repository)
    @repository.owner.mark_as_spammy

    RepositoryDependencyUpdate.expects(:request_for_dependency).never
    assert_no_changes -> { RepositoryDependencyUpdate.count } do
      perform_enqueued_jobs(only: Dependabot::RepositoryVulnerabilityCreatedJob) do
        Dependabot::RepositoryVulnerabilityCreatedJob.perform_later(@alert.id)
      end
    end
  end

  test "re-enqueues Vulnerability Creation Job if Aqueduct::Worker::JobKilled error is raised while processing alertable repos" do
    Dependabot::RepositoryVulnerabilityCreatedJob.any_instance.stubs(:perform).raises(Aqueduct::Worker::JobKilled)
    assert_enqueued_jobs(1, only: Dependabot::RepositoryVulnerabilityCreatedJob) do
      @alerter.process_alertable_repos
      run_processor(GitHub::StreamProcessors::DependabotAlerts::VulnerableDependencyProcessor.new, skip_query_counter: true)
    end
  end

  context "an alert already exists for a newer vulnerable version of the same package" do
    test "it requests a dependency update for the newer vulnerable version" do
      @higher_vulnerability = create :published_vulnerability
      @higher_range = create :vulnerable_version_range,
        vulnerability: @higher_vulnerability,
        affects:     "rake",
        requirements: "< 11.0.0",
        fixed_in: "11.0.0"

      @alert = create(:repository_vulnerability_alert,
                      :open,
                      repository: @repository,
                      vulnerability: @higher_vulnerability,
                      vulnerable_version_range: @higher_range,
                      vulnerable_manifest_path: "Gemfile.lock",
                      affects: "rake")

      assert_empty @repository.dependency_updates

      process_alertable_repos

      @repository.dependency_updates.reload

      assert_equal 1, @repository.dependency_updates.count
      dependency_update = @repository.dependency_updates.first

      assert_equal "requested", dependency_update.state
      assert_equal "vulnerability", dependency_update.reason
      assert_equal "scan", dependency_update.trigger_type
      assert_equal "Gemfile.lock", dependency_update.manifest_path
      assert_equal "rake", dependency_update.package_name
      assert_equal @alert, dependency_update.repository_vulnerability_alert

      assert_hydro_published({
        repository_vulnerability_alert: @alert.hydro_entity_payload,
        repository: Hydro::EntitySerializer.repository(@repository),
        owner: Hydro::EntitySerializer.user(@repository.owner),
        security_advisory: @higher_vulnerability.becomes(SecurityAdvisory).hydro_entity_payload,
        security_vulnerability: @higher_range.becomes(SecurityVulnerability).hydro_entity_payload,
        trigger: "scan",
        description: @higher_vulnerability.description,
        github_bot_install_id: @dependabot_install.id.to_s,
        repository_dependency_update_id: dependency_update.id.to_s,
        dry_run: false,
      }, schema: "github.v1.RepositoryVulnerabilityAlertCreate")
    end

    test "it requests a new update if an errored update exists for the newer vulnerable version" do
      @higher_vulnerability = create :published_vulnerability
      @higher_range = create :vulnerable_version_range,
        vulnerability: @higher_vulnerability,
        affects:     "rake",
        requirements: "< 11.0.0",
        fixed_in: "11.0.0"

      @alert = create(:repository_vulnerability_alert,
                      :open,
                      repository: @repository,
                      vulnerability: @higher_vulnerability,
                      vulnerable_version_range: @higher_range,
                      vulnerable_manifest_path: "Gemfile.lock",
                      affects: "rake")

      @update = RepositoryDependencyUpdate::AlertResolver.new(@alert,
                                                              trigger: :install).create_update
      @update.mark_as_errored(title: "Oh no!", body: "This is broken", type: "bad")

      reset_hydro # clear the message we just created

      assert_same_elements [@update], @repository.dependency_updates

      process_alertable_repos

      @repository.dependency_updates.reload

      assert_equal 2, @repository.dependency_updates.count
      new_dependency_update = @repository.dependency_updates.order(:id).last

      assert_equal "requested", new_dependency_update.state
      assert_equal "vulnerability", new_dependency_update.reason
      assert_equal "scan", new_dependency_update.trigger_type
      assert_equal "Gemfile.lock", new_dependency_update.manifest_path
      assert_equal "rake", new_dependency_update.package_name

      assert_hydro_published({
        repository_vulnerability_alert: @alert.hydro_entity_payload,
        repository: Hydro::EntitySerializer.repository(@repository),
        owner: Hydro::EntitySerializer.user(@repository.owner),
        security_advisory: @higher_vulnerability.becomes(SecurityAdvisory).hydro_entity_payload,
        security_vulnerability: @higher_range.becomes(SecurityVulnerability).hydro_entity_payload,
        trigger: "scan",
        description: @higher_vulnerability.description,
        github_bot_install_id: @dependabot_install.id.to_s,
        repository_dependency_update_id: new_dependency_update.id.to_s,
        dry_run: false,
      }, schema: "github.v1.RepositoryVulnerabilityAlertCreate")
    end

    test "it does nothing if there is already a requested update for the newer vulnerable version" do
      @higher_vulnerability = create :published_vulnerability
      @higher_range = create :vulnerable_version_range,
        vulnerability: @higher_vulnerability,
        affects:     "rake",
        requirements: "< 11.0.0",
        fixed_in: "11.0.0"

      @alert = create(:repository_vulnerability_alert,
                      :open,
                      repository: @repository,
                      vulnerability: @higher_vulnerability,
                      vulnerable_version_range: @higher_range,
                      vulnerable_manifest_path: "Gemfile.lock",
                      affects: "rake")

      @update = RepositoryDependencyUpdate::AlertResolver.new(@alert,
                                                              trigger: :install).create_update
      reset_hydro # clear the message we just created

      assert_same_elements [@update], @repository.dependency_updates

      process_alertable_repos

      assert_same_elements [@update], @repository.dependency_updates.reload

      refute_hydro_messages(schema: "github.v1.RepositoryVulnerabilityAlertCreate")
    end

    test "it does nothing if there is already a completed update for the newer vulnerable version" do
      @higher_vulnerability = create :published_vulnerability
      @higher_range = create :vulnerable_version_range,
        vulnerability: @higher_vulnerability,
        affects:     "rake",
        requirements: "< 11.0.0",
        fixed_in: "11.0.0"

      @alert = create(:repository_vulnerability_alert,
                      :open,
                      repository: @repository,
                      vulnerability: @higher_vulnerability,
                      vulnerable_version_range: @higher_range,
                      vulnerable_manifest_path: "Gemfile.lock",
                      affects: "rake")

      @update = RepositoryDependencyUpdate::AlertResolver.new(@alert,
                                                              trigger: :install).create_update
      @update.mark_as_complete(pull_request: create(:pull_request, :disable_disk_access, repository: @repository))

      reset_hydro # clear the message we just created

      assert_same_elements [@update], @repository.dependency_updates

      process_alertable_repos

      assert_same_elements [@update], @repository.dependency_updates.reload

      refute_hydro_messages(schema: "github.v1.RepositoryVulnerabilityAlertCreate")
    end
  end

  def stub_dependents_query
    results = GitHub::Result.new do
      [
        DependencyGraph::Dependent.new({
          "repositoryId" => @repository.id,
          "name" => @repository.name,
          "manifestPath" => "Gemfile.lock",
          "requirements" => "10.1.0",
          "scope" => "development",
        }),
      ]
    end

    graphql_client = FakeDependencyGraphClient.new
    DependencyGraph::Client.stubs(:new).returns(graphql_client)

    filter = {
      package_manager: "RubyGems",
      package_name: "rake",
      requirements: "< 10.5.0",
      first: 100,
      preview: GitHub.flipper[:vulnerability_alerts_preview_dependencies].enabled?,
    }

    DependencyGraph::AllRepositoriesWithVersionRangeQuery.stubs(:new)
      .with(equals({ dependents_filter: filter, backend: graphql_client }))
      .returns(stub(results: results))
  end
end
