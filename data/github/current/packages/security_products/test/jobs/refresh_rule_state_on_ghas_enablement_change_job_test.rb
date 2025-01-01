# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RefreshRuleStateOnGhasEnablementChangeJobTest < GitHub::TestCase
  include JobTestHelper
  include DependabotAlertsEnterpriseEnablementHelper

  fixtures do
    @business = create(:business)
    @admin = create(:user)
    @org = create(:business_plus_org, admin: @admin, business: @business)
    @private_repo = create(:private_repository, :vulnerability_alerts_enabled, owner: @org)
    @public_repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)
  end

  setup do
    stub_dependabot_alerts_enterprise_enablement if GitHub.enterprise?
    @business.mark_advanced_security_as_purchased_for_entity(actor: create(:user))
    GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
    @private_repo.enable_default_dependabot_rule(actor: @private_repo.owner)
    @public_repo.enable_default_dependabot_rule(actor: @public_repo.owner)

    @pip_custom_rule = create(:vulnerability_alert_rule, {
      state: "ghas_disabled",
      name: "Dismiss development pip alerts",
      enablement_behavior: "enabled_by_default",
      target_type: "Repository",
      target_id: @private_repo.id,
      conditions: {
          ecosystem: ["pip"],
          scope: ["development"],
        }
    })

    @ruby_custom_rule = create(:vulnerability_alert_rule, {
      state: "ghas_disabled",
      name: "Dismiss RubyGem alerts",
      enablement_behavior: "enabled_by_default",
      target_type: "Repository",
      target_id: @private_repo.id,
      conditions: {
        ecosystem: ["RubyGems"],
      }
    })

    @maven_custom_rule = create(:vulnerability_alert_rule, {
      state: "deleted",
      name: "Dismiss Maven alerts",
      enablement_behavior: "enabled_by_default",
      target_type: "Repository",
      target_id: @private_repo.id,
      conditions: {
        ecosystem: ["maven"],
      }
    })
  end

  context "ghas_enabled: true" do
    test "does not set rules that were ghas_disabled as active if repo doesnt really have GHAS enabled" do
      refute @private_repo.advanced_security_enabled?
      # Ensure repo is not enable via freebie or private beta flags else jobs will run
      disable_feature_flag(:dependabot_alerts_freebies, @private_repo)
      disable_feature_flag(:security_center_private_beta, @private_repo)
      assert_no_changes -> { VulnerabilityAlertRule.active.for_repository(@private_repo).count } do
        RefreshRuleStateOnGhasEnablementChangeJob.perform_now(repository: @private_repo, ghas_enabled: true)
      end
    end

    test "sets rules that were ghas_disabled as active and evaluates open alerts if repo has GHAS enabled" do
      @private_repo.enable_advanced_security!(actor: @admin)
      assert @private_repo.advanced_security_enabled?

      # This ruby alert should be auto dismissed by ruby custom rule after state change from ghas_disabled to active
      ruby_alert = create(:repository_vulnerability_alert, repository: @private_repo, ecosystem: "RubyGems")
      assert_equal "open", ruby_alert.state
      assert_nil ruby_alert.last_state_change_rule_id

      perform_enqueued_jobs(only: ReprocessAlertRulesJob) do
        assert_changes -> { VulnerabilityAlertRule.active.for_repository(@private_repo).count }, from: 0, to: 2 do
          RefreshRuleStateOnGhasEnablementChangeJob.perform_now(repository: @private_repo, ghas_enabled: true)
        end
      end

      ruby_alert.reload
      @ruby_custom_rule.reload
      assert_equal "active", @ruby_custom_rule.state

      assert_equal "auto_dismissed", ruby_alert.state
      assert_equal "rule_enabled", ruby_alert.last_state_change_reason
      assert_equal @ruby_custom_rule.id, ruby_alert.last_state_change_rule_id

      # Ensure auto-reopened event metadata is correct:
      event = ruby_alert.events.last
      assert_equal "auto_dismissed", event.event
      assert_equal "rule_enabled", event.reason
      assert_equal @ruby_custom_rule.id, event.rule_id
    end
  end

  context "ghas_enabled: false" do
    test "does not set rules that are active as ghas_disabled if repo doesnt really have GHAS disabled" do
      custom_rule = create(:vulnerability_alert_rule, {
        state: "active",
        name: "Dismiss development pip alerts",
        enablement_behavior: "enabled_by_default",
        target_type: "Repository",
        target_id: @public_repo.id,
        conditions: {
            ecosystem: ["pip"],
            scope: ["development"],
          }
      })

      assert_no_changes -> { VulnerabilityAlertRule.active.for_repository(@public_repo).count } do
        RefreshRuleStateOnGhasEnablementChangeJob.perform_now(repository: @public_repo, ghas_enabled: false)
      end
    end

    test "sets rules that are active as ghas_disabled if repo is GHAS disabled" do
      disable_feature_flag(:dependabot_alerts_freebies, @private_repo)
      disable_feature_flag(:security_center_private_beta, @private_repo)

      refute @private_repo.advanced_security_enabled?

      @pip_custom_rule.update!(state: "active")
      alert = create(:repository_vulnerability_alert,
        :auto_dismissed,
        repository: @private_repo,
        last_state_change_rule_id: @pip_custom_rule.id,
        ecosystem: "pip"
      )

      perform_enqueued_jobs(only: ReprocessAlertRulesJob) do
        assert_changes -> { VulnerabilityAlertRule.active.for_repository(@private_repo).count }, from: 1, to: 0 do
          RefreshRuleStateOnGhasEnablementChangeJob.perform_now(repository: @private_repo, ghas_enabled: false)
        end
      end

      alert.reload
      @pip_custom_rule.reload

      assert_equal "ghas_disabled", @pip_custom_rule.state
      assert_equal "open", alert.state
      assert_equal "previous_rule_disabled", alert.last_state_change_reason
      assert_nil alert.last_state_change_rule_id
    end
  end
end unless GitHub.enterprise?
