# typed: true
# frozen_string_literal: true

require "test_helper"

class VulnerableVersionRangeAlerterTest < GitHub::TestCase
  include HydroTestHelpers
  include DependabotAlertsEnterpriseEnablementHelper

  VULNERABLE_DEPENDENCY_FOUND_SCHEMA = "dependabot.v0.VulnerableDependencyFound"

  fixtures do
    @vulnerability = create :published_vulnerability, :auto_dismissable
    @range = create :vulnerable_version_range,
      vulnerability: @vulnerability,
      affects:     "express.js",
      requirements: ">= 4.0.0",
      fixed_in: "3.9.9",
      ecosystem: "npm"
    @process = create :vulnerable_version_range_alerting_process,
      vulnerable_version_range: @range

    @org = create :organization
    @public_repo = create(:repository)
    @private_repo = create(:private_repository, owner: @org)
  end

  setup do
    if GitHub.enterprise?
      stub_dependabot_alerts_enterprise_enablement
      @public_repo.enable_vulnerability_alerts(actor: @public_repo.owner)
    end

    @private_repo.enable_vulnerability_alerts(actor: @private_repo.owner)

    stub_dependents_query
    @alerter = VulnerableVersionRangeAlerter.new(@process)

    @alerts = [
      { state: :open, path: "package-lock.json", range: @range, requirements: "*", dependency_scope: "development" },
    ]
  end

  test "it publishes a vulnerable dependency found message for both a public and private repo" do
    Timecop.freeze do
      assert_no_vulnerability_alerts @public_repo

      assert_equal 2, @alerter.process_alertable_repos.size

      assert_no_vulnerability_alerts @public_repo
      assert_hydro_messages schema: VULNERABLE_DEPENDENCY_FOUND_SCHEMA, count: 2

      assert_hydro_published({
        repository_id: @public_repo.id,
        vulnerable_dependency: {
          vulnerable_version_range_ids: [@range.id],
          manifest_path: "package-lock.json",
          requirements: "*",
          scope: "development",
        },
        vulnerability_alerting_event_id: @process.vulnerability_alerting_event_id,
        vulnerable_version_range_alerting_process_id: @process.id,
        created_at: Time.current,
      }, schema: VULNERABLE_DEPENDENCY_FOUND_SCHEMA, count: 1, partition_key: @public_repo.id)

      assert_hydro_published({
        repository_id: @private_repo.id,
        vulnerable_dependency: {
          vulnerable_version_range_ids: [@range.id],
          manifest_path: "package-lock.json",
          requirements: "*",
          scope: "development",
        },
        vulnerability_alerting_event_id: @process.vulnerability_alerting_event_id,
        vulnerable_version_range_alerting_process_id: @process.id,
        created_at: Time.current,
      }, schema: VULNERABLE_DEPENDENCY_FOUND_SCHEMA, count: 1, partition_key: @private_repo.id)
    end
  end

  test "it publishes a vulnerable dependency found message even if there a matching alert marked as fixed" do
    Timecop.freeze do
      alert = create :repository_vulnerability_alert, :fixed, {
        repository: @public_repo,
        vulnerability: @range.vulnerability,
        vulnerable_version_range: @range,
        vulnerable_manifest_path: "package-lock.json",
        vulnerable_requirements: "*",
        dependency_scope: "development",
      }

      assert_vulnerability_alerts(@public_repo, @alerts)

      # we should never trigger notifications
      RepositoryVulnerabilityAlert.any_instance.expects(:trigger_notifications).never

      @alerter.process_alertable_repos

      assert_equal "fixed", alert.reload.state
      assert_hydro_messages schema: VULNERABLE_DEPENDENCY_FOUND_SCHEMA, count: 2

      assert_hydro_published({
        repository_id: @public_repo.id,
        vulnerable_dependency: {
          vulnerable_version_range_ids: [@range.id],
          manifest_path: "package-lock.json",
          requirements: "*",
          scope: "development",
        },
        vulnerability_alerting_event_id: @process.vulnerability_alerting_event_id,
        vulnerable_version_range_alerting_process_id: @process.id,
        created_at: Time.current
      }, schema: VULNERABLE_DEPENDENCY_FOUND_SCHEMA, count: 1, partition_key: @public_repo.id)
    end
  end

  test "it does not emit a security center hydro update event" do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    reset_hydro # remove repo alert enablement security center hydro message

    @alerter.process_alertable_repos

    refute_hydro_messages(schema: "github.v1.SecurityCenterRepositoryUpdate")
  end unless GitHub.enterprise?

  test "it does not emit a RepositoryVulnerabilityAlertLifecycle event" do
    @alerter.process_alertable_repos

    refute_hydro_messages(schema: "github.security_alerts.v1.RepositoryVulnerabilityAlertLifecycleEvente")
  end

  test "allows empty pages" do
    graphql_client = FakeDependencyGraphClient.new
    DependencyGraph::Client.stubs(:new).returns(graphql_client)
    filter = { package_manager: "npm", package_name: "express.js", requirements: ">= 4.0.0", first: 100, preview: GitHub.flipper[:vulnerability_alerts_preview_dependencies].enabled? }
    DependencyGraph::AllRepositoriesWithVersionRangeQuery.expects(:new)
      .with(equals({ dependents_filter: filter, backend: graphql_client }))
      .returns(stub(results: GitHub::Result.new { [] }, has_next?: true, last_cursor: nil, dependent_end_cursor: "advance_to_here"))

    alerter = VulnerableVersionRangeAlerter.new(@process)
    assert_predicate alerter, :more_to_process?
    assert_equal "advance_to_here", alerter.next_cursor
    assert_equal 0, alerter.dependents_count
  end

  test "passes the provided cursor to the query" do
    graphql_client = FakeDependencyGraphClient.new
    DependencyGraph::Client.stubs(:new).returns(graphql_client)
    cursor = "foo_bar_baz"
    filter = {
      package_manager: "npm",
      package_name: "express.js",
      requirements: ">= 4.0.0",
      first: 100,
      preview: GitHub.flipper[:vulnerability_alerts_preview_dependencies].enabled?,
      after: cursor,
    }
    DependencyGraph::AllRepositoriesWithVersionRangeQuery.expects(:new)
      .with(equals({ dependents_filter: filter, backend: graphql_client }))
      .returns(stub(results: nil))

    # Initializing a VulnerableVersionRangeAlerter will create a new
    # DependencyGraph::AllRepositoriesWithVersionRangeQuery
    VulnerableVersionRangeAlerter.new(@process, cursor: cursor)
  end

  test "uses a timeout of 15s" do
    graphql_client = FakeDependencyGraphClient.new
    DependencyGraph::Client.expects(:new)
      .with(timeout: 15, query_type: "all_repositories_with_version_range")
      .returns(graphql_client)
    filter = { package_manager: "npm", package_name: "express.js", requirements: ">= 4.0.0", first: 100, preview: GitHub.flipper[:vulnerability_alerts_preview_dependencies].enabled? }
    DependencyGraph::AllRepositoriesWithVersionRangeQuery.expects(:new)
      .with(equals({ dependents_filter: filter, backend: graphql_client }))
      .returns(stub(results: GitHub::Result.new { [] }, has_next?: true, last_cursor: nil, dependent_end_cursor: "advance_to_here"))

    VulnerableVersionRangeAlerter.new(@process.reload)
  end

  def assert_vulnerability_alerts(repository, alerts)
    expected_count = alerts.count
    actual_count = repository.repository_vulnerability_alerts.count
    assert_equal expected_count, actual_count, "Expected #{expected_count} alert(s), got #{actual_count}"

    alerts.each { |alert| assert_vulnerability_alert(repository, **alert) }
  end

  def assert_no_vulnerability_alerts(repo)
    count = repo.repository_vulnerability_alerts.count
    assert_equal 0, count, "Expected 0 alerts, got #{count}"
  end

  def assert_vulnerability_alert(repository, state:, path:, range:, requirements:, dependency_scope:)
    alert = repository.repository_vulnerability_alerts.where({
      vulnerable_manifest_path: path,
      vulnerable_version_range_id: range,
      vulnerable_requirements: requirements,
      dependency_scope: dependency_scope,
    }).first

    assert alert, <<~FAILURE
      Couldn't find an alert that matches:
      - State: #{state}
      - Manifest: #{path}
      - Range: #{range.inspect}
      - Requirements: #{requirements}
      - Dependency Scope: #{dependency_scope}
    FAILURE
  end

  def stub_dependents_query
    results = GitHub::Result.new do
      [
        DependencyGraph::Dependent.new({
          "repositoryId" => @public_repo.id,
          "name" => @public_repo.name,
          "manifestPath" => "package-lock.json",
          "requirements" => "*",
          "scope" => "development",
        }),
        DependencyGraph::Dependent.new({
          "repositoryId" => @private_repo.id,
          "name" => @private_repo.name,
          "manifestPath" => "package-lock.json",
          "requirements" => "*",
          "scope" => "development",
        }),
        # Dependent with empty manifest path to skip
        DependencyGraph::Dependent.new({
          "repositoryId" => @private_repo.id,
          "name" => @private_repo.name,
          "manifestPath" => "",
          "requirements" => "*",
          "scope" => "development",
        }),
      ]
    end

    graphql_client = FakeDependencyGraphClient.new
    DependencyGraph::Client.stubs(:new).returns(graphql_client)

    filter = { package_manager: "npm", package_name: "express.js", requirements: ">= 4.0.0", first: 100, preview: GitHub.flipper[:vulnerability_alerts_preview_dependencies].enabled? }

    DependencyGraph::AllRepositoriesWithVersionRangeQuery.stubs(:new)
      .with(equals({ dependents_filter: filter, backend: graphql_client }))
      .returns(stub(results: results))
  end
end
