# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RefreshDependabotAlertsStateJobTest < GitHub::TestCase
  include JobTestHelper
  include DependabotAlertsEnterpriseEnablementHelper

  fixtures do
    enable_dependabot_alerts_for_enterprise_instance(User.ghost) if GitHub.enterprise?

    @vulnerability = create(:published_vulnerability, :auto_dismissable)
    @range = create(:vulnerable_version_range, {
      vulnerability: @vulnerability,
      ecosystem: "npm",
      affects: "npm-pkg",
      requirements: ">= 4.0.0, <= 4.2.0",
      fixed_in: "4.2.1",
    })
    create_list(:repository_vulnerability_alert, 10, :meets_auto_dismiss_conditions, vulnerability: @vulnerability, vulnerable_version_range: @range)

    Repository.all.each do |repo|
      var = create(:vulnerability_alert_rule, :repo_target)
      var.target_id = repo.id
      var.save!
    end

    @deactivated_repo = create(:deleted_repository)
    create(:repository_vulnerability_alert, :meets_auto_dismiss_conditions,
      repository: @deactivated_repo,
      vulnerability: @vulnerability,
      vulnerable_version_range: @range
    )

    # Create a couple orgs with rules
    @org1 = create(:organization)
    @org1_repo1 = create(:repository, :vulnerability_alerts_enabled, owner: @org1)
    @org1_repo2 = create(:repository, :vulnerability_alerts_enabled, owner: @org1)

    @org2 = create(:organization)
    @org2_repo1 = create(:repository, :vulnerability_alerts_enabled, owner: @org2)
    @org2_repo2 = create(:repository, :vulnerability_alerts_enabled, owner: @org2)

  end

  setup do
    GitHub.stubs(:dependabot_enabled?).returns(true)
  end

  test "should raise an error if no vulnerable_version_range_id is provided" do
    assert_raises(ArgumentError) do
      RefreshDependabotAlertsStateJob.perform_later
    end
  end

  test "refreshes alerts based off of a vulnerable_version_range_id" do
    RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: @range.id)

    assert_equal({ %w[auto_dismissed alert_updated] => 10, ["open", nil] => 1 },
      @range.repository_vulnerability_alerts.group(:state, :last_state_change_reason).count)
  end

  test "successfully runs in batches" do
    RefreshDependabotAlertsStateJob.stub_const(:BATCH_SIZE, 5) do
      perform_enqueued_jobs(only: RefreshDependabotAlertsStateJob) do
        RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: @range.id)
      end
    end

    assert_equal({ %w[auto_dismissed alert_updated] => 10, ["open", nil] => 1 },
      @range.repository_vulnerability_alerts.group(:state, :last_state_change_reason).count)
  end

  test "ignores inactive repositories" do
    RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: @range.id)

    assert_equal({ "auto_dismissed" => 10, "open" => 1 },
      @range.repository_vulnerability_alerts.group(:state).count)
  end

  test "ignores repositories without alerts enabled" do
    disabled_repo = Repository.first
    T.must(disabled_repo).disable_vulnerability_alerts(actor: T.must(T.must(disabled_repo).owner))

    RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: @range.id)

    assert_equal({ "auto_dismissed" => 9, "open" => 2 },
      @range.repository_vulnerability_alerts.group(:state).count)
  end

  test "ignores repositories without auto-dismissal enabled" do
    disabled_repo = Repository.last
    T.must(disabled_repo).disable_default_dependabot_rule(actor: T.must(T.must(disabled_repo).owner))

    RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: @range.id)

    assert_equal({ "auto_dismissed" => 10, "open" => 1 },
      @range.repository_vulnerability_alerts.group(:state).count)

    assert_same_elements %w(auto_dismissed open),
      @range.repository_vulnerability_alerts.pluck(:state).uniq
  end

  test "refreshes rules when an epss score changes and the ff is enabled" do
    # Checked in RepositoryVulnerabilityAlert#rule_conditions_are_met?
    vulnerability = create(:vulnerability, :with_cve, :published, { ecosystem: "npm", severity: "high" })
    epss = create(:cve_epss, vulnerability: vulnerability, percentage: 0.25)
    range = create(:vulnerable_version_range, {
      vulnerability: vulnerability,
      ecosystem: "npm",
      affects: "npm-pkg",
      requirements: ">= 1.0.0, <= 1.2.0",
      fixed_in: "1.2.1",
    })
    alert = create(:repository_vulnerability_alert, :open, {
      dependency_scope: "development",
      vulnerability: vulnerability,
      vulnerable_version_range: range
    })
    rule = create(:vulnerability_alert_rule, {
      name: "Dismiss if EPSS below 20%",
      enablement_behavior: "enabled_by_default",
      target_type: "Repository",
      target_id: alert.repository.id,
      conditions: {
        epss: ["percentage<=20.0"]
      },
      actions: {
        version: 1,
        alert_actions: {
          auto_dismiss: "indefinitely"
        }
      }
    })

    assert_equal "open", alert.state

    epss.update!(percentage: 0.15)
    RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: range.id, change: "epss")

    assert_equal "auto_dismissed", alert.reload.state
  end

  test "refreshes alerts when org rules exist and an epss score changes" do
    # Checked in RepositoryVulnerabilityAlert#rule_conditions_are_met?
    vulnerability = create(:vulnerability, :with_cve, :published, { ecosystem: "npm", severity: "high" })
    epss = create(:cve_epss, vulnerability: vulnerability, percentage: 0.25)
    range = create(:vulnerable_version_range, {
      vulnerability: vulnerability,
      ecosystem: "npm",
      affects: "npm-pkg",
      requirements: ">= 1.0.0, <= 1.2.0",
      fixed_in: "1.2.1",
    })
    alert = create(:repository_vulnerability_alert, :open, {
      dependency_scope: "development",
      vulnerability: vulnerability,
      vulnerable_version_range: range,
      repository: @org1_repo1,
    })

    rule = create(:vulnerability_alert_rule, {
      name: "Dismiss if EPSS below 20%",
      enablement_behavior: "enabled_by_default",
      target_type: "User",
      target_id: @org1.id,
      conditions: {
        epss: ["percentage<=20.0"]
      },
      actions: {
        version: 1,
        alert_actions: {
          auto_dismiss: "indefinitely"
        }
      }
    })

    assert_equal "open", alert.state

    epss.update!(percentage: 0.15)
    RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: range.id, changes: ["epss"], org_rules: true)

    assert_equal "auto_dismissed", alert.reload.state
  end

  test "refreshes alerts when a mix of org and repo rules apply and a severity changes" do
    # Checked in RepositoryVulnerabilityAlert#rule_conditions_are_met?
    vulnerability = create(:vulnerability, :with_cve, :published, { ecosystem: "npm", severity: "high" })
    range = create(:vulnerable_version_range, {
      vulnerability: vulnerability,
      ecosystem: "npm",
      affects: "npm-pkg",
      requirements: ">= 1.0.0, <= 1.2.0",
      fixed_in: "1.2.1",
    })
    alert1 = create(:repository_vulnerability_alert, :open, {
      dependency_scope: "development",
      vulnerability: vulnerability,
      vulnerable_version_range: range,
      repository: @org1_repo1,
    })
    alert2 = create(:repository_vulnerability_alert, :open, {
      dependency_scope: "development",
      vulnerability: vulnerability,
      vulnerable_version_range: range
    })
    rule = create(:vulnerability_alert_rule, {
      name: "Dismiss if severity is low",
      enablement_behavior: "enabled_by_default",
      target_type: "User",
      target_id: @org1.id,
      conditions: {
        severity: ["low"]
      },
      actions: {
        version: 1,
        alert_actions: {
          auto_dismiss: "indefinitely"
        }
      }
    })
    rule2 = create(:vulnerability_alert_rule, {
      name: "Dismiss if severity is low",
      enablement_behavior: "enabled_by_default",
      target_type: "Repository",
      target_id: alert2.repository.id,
      conditions: {
        severity: ["low"]
      },
      actions: {
        version: 1,
        alert_actions: {
          auto_dismiss: "indefinitely"
        }
      }
    })
    assert_equal "open", alert1.state
    assert_equal "open", alert2.state
    vulnerability.update!(severity: "low")
    RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: range.id, changes: ["severity"])
    RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: range.id, changes: ["severity"], org_rules: true)

    assert_equal "auto_dismissed", alert1.reload.state
    assert_equal "auto_dismissed", alert2.reload.state
  end

  test "enqueues Dependabot::RepositoryVulnerabilityCreatedJob if any alerts change state and are candidates for pull request" do
    vulnerability = create(:vulnerability, :published, { ecosystem: "npm", severity: "high" })
    range = create(:vulnerable_version_range, {
      vulnerability: vulnerability,
      ecosystem: "npm",
      affects: "npm-pkg",
      requirements: ">= 1.0.0, <= 1.2.0",
      fixed_in: "1.2.1",
    })
    alert = create(:repository_vulnerability_alert, :auto_dismissed, {
      dependency_scope: "development",
      vulnerability: vulnerability,
      vulnerable_version_range: range
    })

    alert.repository.enable_default_dependabot_rule(actor: alert.repository.owner)

    rule = create(:vulnerability_alert_rule, {
      name: "Dismiss until patch then create pull request",
      enablement_behavior: "enabled_by_default",
      target_type: "Repository",
      target_id: alert.repository.id,
      conditions: {
        ecosystem: [alert.ecosystem],
        severity: [alert.severity]
      },
      actions: {
        version: 1,
        alert_actions: {
          auto_dismiss: "until_patch"
        },
        update_actions: {
          create_pr: true
        }
      }
    })
    assert_equal "auto_dismissed", alert.state

    Dependabot::RepositoryVulnerabilityCreatedJob.expects(:enqueue).with(alert).once

    assert_changes -> { alert.reload.state }, from: "auto_dismissed", to: "open" do
      perform_enqueued_jobs(only: RefreshDependabotAlertsStateJob) do
        RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: range.id)
      end
    end
  end

  test "does not enqueue Dependabot::RepositoryVulnerabilityCreatedJob if an alert has been dismissed" do
    vulnerability = create(:vulnerability, :published, { ecosystem: "npm", severity: "high" })
    range = create(:vulnerable_version_range, {
      vulnerability: vulnerability,
      ecosystem: "npm",
      affects: "npm-pkg",
      requirements: ">= 1.0.0, <= 1.2.0",
      fixed_in: nil,
    })
    alert = create(:repository_vulnerability_alert, :open, {
      dependency_scope: "development",
      vulnerability: vulnerability,
      vulnerable_version_range: range
    })

    alert.repository.enable_default_dependabot_rule(actor: alert.repository.owner)

    rule = create(:vulnerability_alert_rule, {
      name: "Dismiss until patch then create pull request",
      enablement_behavior: "enabled_by_default",
      target_type: "Repository",
      target_id: alert.repository.id,
      conditions: {
        ecosystem: [alert.ecosystem],
        severity: [alert.severity]
      },
      actions: {
        version: 1,
        alert_actions: {
          auto_dismiss: "until_patch"
        },
        update_actions: {
          create_pr: true
        }
      }
    })
    assert_equal "open", alert.state

    Dependabot::RepositoryVulnerabilityCreatedJob.expects(:enqueue).never

    assert_changes -> { alert.reload.state }, from: "open", to: "auto_dismissed" do
      perform_enqueued_jobs(only: RefreshDependabotAlertsStateJob) do
        RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: range.id)
      end
    end
  end


  test "does not enqueue Dependabot::RepositoryVulnerabilityCreatedJob if no alerts change state" do
    vulnerability = create(:vulnerability, :published, { ecosystem: "npm", severity: "low" })
    range = create(:vulnerable_version_range, {
      vulnerability: vulnerability,
      ecosystem: "npm",
      affects: "npm-pkg",
      requirements: ">= 1.0.0, <= 1.2.0",
      fixed_in: "1.2.1",
    })
    alert = create(:repository_vulnerability_alert, :auto_dismissed, {
      dependency_scope: "development",
      vulnerability: vulnerability,
      vulnerable_version_range: range
    })

    alert.repository.enable_default_dependabot_rule(actor: alert.repository.owner)

    rule = create(:vulnerability_alert_rule, {
      name: "Dismiss until patch then create pull request",
      enablement_behavior: "enabled_by_default",
      target_type: "Repository",
      target_id: alert.repository.id,
      conditions: {
        ecosystem: [alert.ecosystem],
        severity: [alert.severity]
      },
      actions: {
        version: 1,
        alert_actions: {
          auto_dismiss: "indefinitely"
        }
      }
    })
    assert_equal "auto_dismissed", alert.state

    Dependabot::RepositoryVulnerabilityCreatedJob.expects(:enqueue).never

    assert_no_changes -> { alert.reload.state } do
      perform_enqueued_jobs(only: RefreshDependabotAlertsStateJob) do
        RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: range.id)
      end
    end
  end

  test "records Datadog metrics with correct calls to increment method" do
    GitHub::Dogstats.stubs(:monotonic_time).returns(Time.utc(2023, 1, 1, 12).to_f)

    repo = Repository.first
    alert1 = @range.repository_vulnerability_alerts.first
    alert2 = @range.repository_vulnerability_alerts.second

    # Stub increment to avoid actual API calls
    GitHub.dogstats.stubs(:increment)

    # Expect increment calls
    GitHub.dogstats.expects(:increment).with("refresh_dependabot_alerts_state_job.job_count").never # ensure labels are applied
    GitHub.dogstats.expects(:increment).with("refresh_dependabot_alerts_state_job.job_count", tags: ["rule_scope:repo"]).once
    GitHub.dogstats.expects(:increment).with("refresh_dependabot_alerts_state_job.job_count", tags: ["rule_scope:org"]).never

    GitHub.dogstats.expects(:increment).with("repository_vulnerability_alert.processed_alerts").never # ensure labels are applied
    GitHub.dogstats.expects(:increment).with("repository_vulnerability_alert.processed_alerts", tags: ["rule_type:none"]).twice

    GitHub.dogstats.expects(:increment).with("repository_vulnerability_alert.refreshed_alerts").never # ensure labels are applied
    GitHub.dogstats.expects(:increment).with("repository_vulnerability_alert.refreshed_alerts", tags: ["rule_type:none"]).twice

    GitHub.dogstats.expects(:increment).with("repository_vulnerability_alert.candidate_prs").never

    # Execute the job
    RefreshDependabotAlertsStateJob.perform_now(vulnerable_version_range_id: alert1.vulnerable_version_range_id)
  end

  context "vulnerability updates" do
    test "instrument vulnerability update event for severity change" do
      received_event = T.let(false, T::Boolean)
      payloads = T.let([], T::Array[Hash])
      GitHub.subscribe "repository_vulnerability_alert.vulnerability_update" do |event|
        received_event = true
        payloads << event.payload
      end

      perform_enqueued_jobs(only: RefreshDependabotAlertsStateJob) do
        RefreshDependabotAlertsStateJob.perform_later(vulnerable_version_range_id: @range.id, changes: ["severity"])
      end

      assert received_event
      assert_equal "severity_change", payloads.map { |p| p[:action] }.uniq.first
      assert payloads.all? { |p| p.key?(:severity) }
    end

    test "instrument vulnerability update event for other metadata changes" do
      received_event = T.let(false, T::Boolean)
      payloads = T.let([], T::Array[Hash])
      GitHub.subscribe "repository_vulnerability_alert.vulnerability_update" do |event|
        received_event = true
        payloads << event.payload
      end

      perform_enqueued_jobs(only: RefreshDependabotAlertsStateJob) do
        RefreshDependabotAlertsStateJob.perform_later(vulnerable_version_range_id: @range.id, changes: ["cwe_ids"])
      end

      assert received_event
      assert_equal "vulnerability_metadata_change", payloads.map { |p| p[:action] }.uniq.first
    end
  end
end
