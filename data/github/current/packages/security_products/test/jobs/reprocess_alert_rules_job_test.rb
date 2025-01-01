# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ReprocessAlertRulesJobTest < GitHub::TestCase
  include JobTestHelper
  include DependabotAlertsEnterpriseEnablementHelper

  setup do
    stub_dependabot_alerts_enterprise_enablement if GitHub.enterprise?
    @user = create(:verified_user)
    @org = create(:organization, admin: @user)
    @repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)
    GitHub.flipper[:dependabot_alerts_update_alert_metadata].enable(@repo)
    @repo.enable_default_dependabot_rule(actor: @repo.owner)

    @pip_range = create(:vulnerable_version_range, ecosystem: "pip")
    @auto_dismissable_pip_vulnerability = create(:published_vulnerability,
      vulnerable_version_ranges: [@pip_range]
    )

    @pip_custom_rule = create(:vulnerability_alert_rule, {
      name: "Dismiss development pip alerts",
      enablement_behavior: "enabled_by_default",
      target_type: "Repository",
      target_id: @repo.id,
      conditions: {
          ecosystem: ["pip"],
          scope: ["development"],
        }
    })

    @ruby_custom_rule = create(:vulnerability_alert_rule, {
      name: "Dismiss RubyGem alerts",
      enablement_behavior: "enabled_by_default",
      target_type: "Repository",
      target_id: @repo.id,
      conditions: {
        ecosystem: ["RubyGems"],
      }
    })

    @alert = create(:repository_vulnerability_alert, :auto_dismissed, {
      repository: @repo,
      ecosystem: "pip",
      dependency_scope: "development",
      last_state_change_rule_id: @pip_custom_rule.id,
      vulnerability: @auto_dismissable_pip_vulnerability,
    })
  end

  context "enabled_rule_ids" do
    test "auto-dismisses alerts affected by the rule" do
      npm_alert = create(:repository_vulnerability_alert, repository: @repo, ecosystem: "npm")
      assert_equal "open", npm_alert.state
      assert_nil npm_alert.last_state_change_rule_id

      # Create a new custom rule, let's pretend we're just enabling it:
      npm_custom_rule = create(:vulnerability_alert_rule, {
        name: "Dismiss all npm alerts",
        enablement_behavior: "enabled_by_default",
        target_type: "Repository",
        target_id: @repo.id,
        conditions: { ecosystem: ["npm"] }
      })

      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, enabled_rule_ids: [npm_custom_rule.id])

      npm_alert.reload
      assert_equal "auto_dismissed", npm_alert.state
      assert_equal "rule_enabled", npm_alert.last_state_change_reason
      assert_equal npm_custom_rule.id, npm_alert.last_state_change_rule_id

      # Ensure auto-reopened event metadata is correct:
      event = npm_alert.events.last
      assert_equal "auto_dismissed", event.event
      assert_equal "rule_enabled", event.reason
      assert_equal npm_custom_rule.id, event.rule_id
    end
  end

  context "disabled_rule_ids" do
    test "auto-reopens alerts auto-dismissed by the disabled rule" do
      # Disable the custom rule:
      @pip_custom_rule.update(enablement_behavior: "disabled_by_default")

      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, disabled_rule_ids: [@pip_custom_rule.id])

      @alert.reload
      assert_equal "open", @alert.state
      assert_equal "previous_rule_disabled", @alert.last_state_change_reason
      assert_nil @alert.last_state_change_rule_id

      # Ensure auto-reopened event metadata is correct:
      event = @alert.events.last
      assert_equal "auto_reopened", event.event
      assert_equal "previous_rule_disabled", event.reason
      assert_equal @pip_custom_rule.id, event.rule_id # The event refers to the rule which was disabled
    end

    test "existing alerts remain auto-dismissed when another rule applies" do
      # Disable the custom rule:
      @pip_custom_rule.update(enablement_behavior: "disabled_by_default")

      pip_custom_rule_2 = create(:vulnerability_alert_rule, {
        name: "Dismiss all pip alerts",
        enablement_behavior: "enabled_by_default",
        target_type: "Repository",
        target_id: @repo.id,
        conditions: {
            ecosystem: ["pip"],
          }
      })

      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, disabled_rule_ids: [@pip_custom_rule.id])

      @alert.reload

      assert_equal "previous_rule_disabled", @alert.last_state_change_reason
      assert_equal pip_custom_rule_2.id, @alert.last_state_change_rule_id
      assert_equal "auto_dismissed", @alert.state

      # Assert alert event values match newly applied rule
      event = @alert.events.last
      assert_equal "auto_dismissed", event.event
      assert_equal "previous_rule_disabled", event.reason
      assert_equal pip_custom_rule_2.name, event.rule_name
      assert_equal pip_custom_rule_2.id, event.rule_id
    end
  end

  context "deleted_rule_id" do
    test "auto-reopens alerts affected by deleted rule if no other rule can dismiss alerts" do
      rule = @pip_custom_rule
      @pip_custom_rule.destroy!

      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, deleted_rule_id: @pip_custom_rule.id)

      @alert.reload
      assert_equal @alert.state, "open"
      assert_equal @alert.last_state_change_reason, "previous_rule_deleted"
      assert_nil @alert.last_state_change_rule_id

      # Assert alert event auto-reopened event is created
      event = @alert.events.order(:id).last
      assert_equal "auto_reopened", event.event
      assert_equal "previous_rule_deleted", event.reason
      assert_equal rule.id, event.rule_id
      assert_equal rule.conditions, event.rule_conditions
      assert_equal rule.name, event.rule_name
    end

    test "auto-dismisses alerts affected by rule deletion with a new applicable rule" do
      pip_custom_rule_2 = create(:vulnerability_alert_rule, {
        name: "Dismiss all pip alerts",
        enablement_behavior: "enabled_by_default",
        target_type: "Repository",
        target_id: @repo.id,
        conditions: {
            ecosystem: ["pip"],
          }
      })

      @pip_custom_rule.destroy!

      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, deleted_rule_id: @pip_custom_rule.id)

      @alert.reload
      assert_equal @alert.last_state_change_rule_id, pip_custom_rule_2.id

      # Assert alert event values match newly applied rule
      event = @alert.events.order(:id).last
      assert_equal "auto_dismissed", event.event
      assert_equal "previous_rule_deleted", event.reason
      assert_equal pip_custom_rule_2.id, event.rule_id
    end
  end

  context "created_rule_id" do
    test "auto-dismisses alerts affected by rule creation" do
      npm_alert = create(:repository_vulnerability_alert, repository: @repo, ecosystem: "npm")
      assert_equal "open", npm_alert.state
      assert_nil npm_alert.last_state_change_rule_id

      # Create a new custom rule
      npm_custom_rule = create(:vulnerability_alert_rule, {
        name: "Dismiss all npm alerts",
        enablement_behavior: "enabled_by_default",
        target_type: "Repository",
        target_id: @repo.id,
        conditions: { ecosystem: ["npm"] }
      })

      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, created_rule_id: @pip_custom_rule.id)

      npm_alert.reload
      assert_equal "auto_dismissed", npm_alert.state, "open"
      assert_equal "rule_created", npm_alert.last_state_change_reason
      assert_equal npm_custom_rule.id, npm_alert.last_state_change_rule_id

      # Ensure auto-reopened event metadata is correct:
      event = npm_alert.events.last
      assert_equal "auto_dismissed", event.event
      assert_equal "rule_created", event.reason
      assert_equal npm_custom_rule.id, event.rule_id
    end
  end

  context "edited_rule_id" do
    test "auto-reopens alerts if rule is edited and they can't be auto-dismissed by any other rule" do
      ruby_alert = create(:repository_vulnerability_alert, :auto_dismissed, {
        repository: @repo,
        ecosystem: "RubyGems",
        dependency_scope: "runtime",
        last_state_change_rule_id: @ruby_custom_rule.id,
      })

      @ruby_custom_rule.update(
        conditions: {
          "ecosystem" => ["RubyGems"],
          "scope" => ["development"],
        }
      )

      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, edited_rule_id: @ruby_custom_rule.id)

      ruby_alert.reload
      assert_equal "open", ruby_alert.state
      assert_equal "previous_rule_updated", ruby_alert.last_state_change_reason
      assert_nil ruby_alert.last_state_change_rule_id

      # Assert alert event auto-reopened event is created
      event = ruby_alert.events.order(:id).last
      assert_equal "auto_reopened", event.event
      assert_equal "previous_rule_updated", event.reason
      assert_equal @ruby_custom_rule.id, event.rule_id
    end

    test "continues to keep alert auto-dismissed by edited ruled if alert still matches" do
      ruby_alert = create(:repository_vulnerability_alert, :auto_dismissed, {
        repository: @repo,
        ecosystem: "RubyGems",
        dependency_scope: "development",
        last_state_change_rule_id: @ruby_custom_rule.id,
        last_state_change_reason: "rule_enabled",
      })

      @ruby_custom_rule.update(
        name: "Dismiss RubyGem development alerts",
      )

      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, edited_rule_id: @ruby_custom_rule.id)

      ruby_alert.reload
      assert_equal "rule_enabled", ruby_alert.last_state_change_reason
      assert_equal @ruby_custom_rule.id, ruby_alert.last_state_change_rule_id
    end

    test "auto-dismisses alerts affected by rule edit with a new applicable rule" do
      pip_custom_rule_2 = create(:vulnerability_alert_rule, {
        name: "Dismiss all pip alerts",
        enablement_behavior: "enabled_by_default",
        target_type: "Repository",
        target_id: @repo.id,
        conditions: {
            ecosystem: ["pip"],
          }
      })

      @pip_custom_rule.update(
        conditions: {
          "ecosystem" => ["pip"],
          "scope" => ["runtime"],
        }
      )

      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, edited_rule_id: @pip_custom_rule.id)

      @alert.reload
      assert_equal "previous_rule_updated", @alert.last_state_change_reason
      assert_equal pip_custom_rule_2.id, @alert.last_state_change_rule_id

      # Assert alert event values match newly applied rule
      event = @alert.events.order(:id).last
      assert_equal "auto_dismissed", event.event
      assert_equal "previous_rule_updated", event.reason
      assert_equal pip_custom_rule_2.id, event.rule_id
    end

    test "auto-dismisses open alerts affected by rule edit" do
      pip_alert = create(:repository_vulnerability_alert, {
        repository: @repo,
        ecosystem: "pip",
        dependency_scope: "runtime",
      })

      @pip_custom_rule.update(
        conditions: {
          "ecosystem" => ["pip"],
          "scope" => ["runtime"],
        }
      )

      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, edited_rule_id: @pip_custom_rule.id)

      pip_alert.reload
      assert_equal "rule_updated", pip_alert.last_state_change_reason
      assert_equal @pip_custom_rule.id, pip_alert.last_state_change_rule_id

      # Assert alert event values match newly applied rule
      event = pip_alert.events.order(:id).last
      assert_equal "auto_dismissed", event.event
      assert_equal "rule_updated", event.reason
      assert_equal @pip_custom_rule.id, event.rule_id
    end
  end

  context "unpausing dependabot updates" do
    test "delegates to DependabotVulnerabilityAlertRulesActivityManager for each kind of alert rule activity" do
      DependabotVulnerabilityAlertRulesActivityManager.any_instance.expects(:on_create).with(@pip_custom_rule.id).once
      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, created_rule_id: @pip_custom_rule.id)

      DependabotVulnerabilityAlertRulesActivityManager.any_instance.expects(:on_update).with(@pip_custom_rule.id).once
      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, edited_rule_id: @pip_custom_rule.id)

      DependabotVulnerabilityAlertRulesActivityManager.any_instance.expects(:on_enable).with([@pip_custom_rule.id]).once
      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, enabled_rule_ids: [@pip_custom_rule.id])

      DependabotVulnerabilityAlertRulesActivityManager.any_instance.expects(:on_disable).with([@pip_custom_rule.id]).once
      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, disabled_rule_ids: [@pip_custom_rule.id])

      DependabotVulnerabilityAlertRulesActivityManager.any_instance.expects(:on_delete).with(@pip_custom_rule.id).once
      @pip_custom_rule.soft_delete_rule
      ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, deleted_rule_id: @pip_custom_rule.id)
    end
  end

  context "requesting RepositoryDependencyUpdates for alerts" do
    test "does not enqueue Dependabot::RepositoryVulnerabilityCreatedJob if some alerts are auto-dismissed but " \
      "no alerts are auto-reopened or candidates for pull request" do
      rule = create(:vulnerability_alert_rule, {
        name: "Dismiss until patch for all npm alerts",
        enablement_behavior: "enabled_by_default",
        target_type: "Repository",
        target_id: @repo.id,
        conditions: {
          ecosystem: ["npm"]
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

      alert = create(:repository_vulnerability_alert, :meets_auto_dismiss_conditions, {
        repository: @repo,
        ecosystem: "npm"
      })

      Dependabot::RepositoryVulnerabilityCreatedJob.expects(:enqueue).never

      assert_changes -> { alert.reload.state }, from: "open", to: "auto_dismissed" do
        ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, created_rule_id: rule.id)
      end
    end

    test "enqueues Dependabot::RepositoryVulnerabilityCreatedJob if some alerts are auto-reopened", skip_enterprise: true do
      dev_rule = create(:vulnerability_alert_rule, {
        name: "Dismiss until patch then open PR for alerts on npm dev dependencies",
        enablement_behavior: "enabled_by_default",
        target_type: "Repository",
        target_id: @repo.id,
        conditions: {
          ecosystem: ["npm"],
          scope: ["development"]
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

      runtime_rule = create(:vulnerability_alert_rule, {
        name: "Dismiss until patch for low-severity alerts on npm runtime dependencies",
        enablement_behavior: "enabled_by_default",
        target_type: "Repository",
        target_id: @repo.id,
        conditions: {
          ecosystem: ["npm"],
          scope: ["runtime"],
          severity: ["low"]
        },
        actions: {
          version: 1,
          alert_actions: {
            auto_dismiss: "until_patch"
          }
        }
      })

      dev_alert = create(:repository_vulnerability_alert, :auto_dismissed, {
        repository: @repo,
        ecosystem: "npm",
        dependency_scope: "development",
        last_state_change_rule_id: dev_rule.id
      })
      assert_equal "auto_dismissed", dev_alert.state

      runtime_alert = create(:repository_vulnerability_alert, :auto_dismissed, {
        repository: @repo,
        ecosystem: "npm",
        dependency_scope: "runtime",
        vulnerability: create(:vulnerability, :auto_dismissable, severity: "low"),
        last_state_change_rule_id: runtime_rule.id
      })
      assert_equal "auto_dismissed", runtime_alert.state

      runtime_rule.update!({
        name: "Dismiss until patch then open PR for low-severity alerts on npm runtime dependencies",
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

      Dependabot::RepositoryVulnerabilityCreatedJob.expects(:enqueue).with(runtime_alert).once

      assert_no_changes -> { dev_alert.reload.state } do
        assert_changes -> { runtime_alert.reload.state }, from: "auto_dismissed", to: "open" do
          ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, edited_rule_id: runtime_rule.id)
        end
      end
    end

    test "does not enqueue Dependabot::RepositoryVulnerabilityCreatedJob if no alerts are auto-dismissed, auto-reopened, or " \
      "candidates for pull request" do
      rule = create(:vulnerability_alert_rule, {
        name: "Dismiss until patch for all npm alerts",
        enablement_behavior: "enabled_by_default",
        target_type: "Repository",
        target_id: @repo.id,
        conditions: {
          ecosystem: ["npm"]
        },
        actions: {
          version: 1,
          alert_actions: {
            auto_dismiss: "until_patch"
          }
        }
      })

      alert = create(:repository_vulnerability_alert, {
        repository: @repo,
        ecosystem: "npm",
        dependency_scope: "runtime",
        state_auto_changeable: false
      })
      assert_equal "open", alert.state
      refute_predicate alert, :candidate_for_pull_request?

      Dependabot::RepositoryVulnerabilityCreatedJob.expects(:enqueue).never

      assert_no_changes -> { alert.reload.state } do
        ReprocessAlertRulesJob.perform_now(repository_id: @repo.id, created_rule_id: rule.id)
      end
    end
  end

  context "retries" do
    test "raises RuleNotYetDeleted error if maximum retries are reached" do
      RepositoryVulnerabilityAlert.any_instance.stubs(:auto_dismiss_or_reopen).raises(ReprocessAlertRulesJob::RuleNotYetDeleted)

      ReprocessAlertRulesJob.perform_later(repository_id: @repo.id, deleted_rule_id: @pip_custom_rule.id)

      assert_nothing_raised do
        9.times { perform_enqueued_jobs(only: ReprocessAlertRulesJob) }
      end

      assert_raises ReprocessAlertRulesJob::RuleNotYetDeleted do
        perform_enqueued_jobs(only: ReprocessAlertRulesJob)
      end
    end

    test "retries on certain errors" do
      args = { repository_id: @repo.id, deleted_rule_id: @pip_custom_rule.id }

      assert_retry_on_dirty_exit job: ReprocessAlertRulesJob, args: [args]
      assert_retry_on_recoverable_exceptions job: ReprocessAlertRulesJob, args: [args]
    end
  end
end
