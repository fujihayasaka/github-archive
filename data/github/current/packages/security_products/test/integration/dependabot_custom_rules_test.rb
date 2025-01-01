# typed: true
# frozen_string_literal: true

require "test_helper"

# This class encapsulates integration tests for the full end-to-end Dependabot Custom Rules experience.
# There are other tests for verifying rendering and behavior for individual controllers/routes, but we will verify the
# full functionality of the entire feature in this file.
#
# NOTE: This entire class is disabled for GitHub Enterprise since we DO NOT support Dependabot Custom Rules there yet.
class DependabotCustomRulesTest < GitHub::IntegrationTestCase
  ALL_THE_JOBS = [ReprocessAlertRulesJob].freeze

  setup do
    as @owner
  end

  fixtures do
    GitHub.flipper[:repository_security_settings].disable
    @owner = create(:user)
    @public_repo = create(:public_repository, :vulnerability_alerts_enabled, owner: @owner)

    business = create(:business)
    org = create(:organization, admin: @owner, business: business)
    business.mark_advanced_security_as_purchased_for_entity(actor: @owner)

    @private_repo = create(:private_repository, :vulnerability_alerts_enabled, owner: org)
    @private_repo.enable_advanced_security!(actor: @owner)

    @global_rule = VulnerabilityAlertRule.default_auto_dismissal_rule
  end

  context "global default rule" do
    # NOTE: We are skipping EMU tests here because EMUs don't support public repos.
    # We will test similar functionality below in "can be enabled on private repositories"
    test "is enabled by default on public repositories with Enabled status", skip_with_all_emus: true do
      # Verify that the Security & Analysis settings page lists 1 rule enabled:
      get "/#{@public_repo.name_with_display_owner}/settings/security_analysis"
      assert_response :success
      assert_includes response.body, "1 rule enabled"

      # Verify that "clicking" the cog icon lists all rules, with the global checked:
      edit_button = assert_test_selector("edit-dependabot-rules").first
      get edit_button["href"]
      assert_response :success
      assert_includes response.body, @global_rule.name
      assert_test_selector "github-preset-rule_enablement", match: "Enabled"
    end

    test "is disabled by default on private repositories"  do
      # Verify that the Security & Analysis settings page lists no rules enabled:
      get "/#{@private_repo.name_with_display_owner}/settings/security_analysis"
      assert_response :success
      assert_includes response.body, "0 rules enabled"

      # Verify that "clicking" the cog icon lists all rules, with the global NOT checked:
      edit_button = assert_test_selector("edit-dependabot-rules").first
      get edit_button["href"]
      assert_response :success
      assert_includes response.body, @global_rule.name
      assert_test_selector "github-preset-rule_enablement", match: "Disabled"
    end

    # NOTE: We are skipping EMU tests here because EMUs don't support public repos. This test is on a public repo,
    # so we will confirm functionality in another test in the custom rules section.
    test "does not update or delete rules and alerts when dependabot alerts are disabled", skip_with_all_emus: true do
      # Ensure we have an auto-dismissed alert:
      auto_dismissed_alert = create(:repository_vulnerability_alert, :auto_dismissed, repository: @public_repo)
      assert_equal "auto_dismissed", auto_dismissed_alert.state
      assert_equal 1, auto_dismissed_alert.events.count

      # Verify that the Security & Analysis settings page lists 1 rule enabled:
      get "/#{@public_repo.name_with_display_owner}/settings/security_analysis"
      assert_response :success
      assert_includes response.body, "1 rule enabled"

      @public_repo.disable_vulnerability_alerts(actor: @owner)

      # Verify that the alert and rule are not updated or deleted:
      assert_equal "auto_dismissed", auto_dismissed_alert.state
      assert_equal 1, auto_dismissed_alert.events.count
      assert_equal 1, VulnerabilityAlertRule.count
      assert_nil VulnerabilityAlertRuleOverride.find_by(target_id: @public_repo.id)
    end
  end

  context "repository custom rules" do
    test "creating a new rule applies it to existing alerts" do
      [
        alert_to_auto_dismiss = create(:repository_vulnerability_alert, repository: @private_repo, ecosystem: "RubyGems"),
        alert_to_stay_the_same = create(:repository_vulnerability_alert, repository: @private_repo, ecosystem: "pip")
      ].each do |alert|
        assert_equal "open", alert.state
        assert_equal 0, alert.events.count
      end

      get "/#{@private_repo.name_with_display_owner}/settings/dependabot_rules"
      assert_response :success

      new_button = assert_test_selector("new-button").first
      get new_button["href"]
      assert_response :success

      new_form = assert_select("dependabot-alert-rule-form > form").first
      create_form_url = new_form["action"]

      new_rule_params = {
        vulnerability_alert_rule: {
          name: "I Got New Rules, I Count 'Em",
          auto_dismiss: 1,
          auto_dismiss_option: "indefinitely",
          rule_behavior: "enabled_by_default",
        },
        rule_criteria: "ecosystem:RubyGems"
      }

      # Ensure a new VulnerabilityAlertRule is created:
      assert_changes -> { VulnerabilityAlertRule.count }, from: 1, to: 2 do
        perform_enqueued_jobs(only: ALL_THE_JOBS) do
          post create_form_url, params: new_rule_params
          assert_redirected_to "/#{@private_repo.name_with_display_owner}/settings/dependabot_rules"
        end
      end

      # Ensure that existing RubyGems alert is auto-dismissed:
      alert_to_auto_dismiss.reload
      assert_equal "auto_dismissed", alert_to_auto_dismiss.state
      assert_equal 1, alert_to_auto_dismiss.events.count

      # And that the existing PIP alert stayed the same:
      alert_to_stay_the_same.reload
      assert_equal "open", alert_to_stay_the_same.state
      assert_equal 0, alert_to_stay_the_same.events.count
    end

    test "creating a new until_patch rule applies it to existing alerts without a patch" do
      range = create(:vulnerable_version_range, {
        requirements: "< 4.17.21",
        fixed_in: nil,
        ecosystem: "RubyGems",
      })

      vulnerability = create(:published_vulnerability, vulnerable_version_ranges: [range])

      [
        alert_to_auto_dismiss = create(:repository_vulnerability_alert,
          repository: @private_repo,
          vulnerability: vulnerability,
          vulnerable_version_range: range,
          ecosystem: "RubyGems"),
        alert_to_stay_the_same = create(:repository_vulnerability_alert, repository: @private_repo, ecosystem: "RubyGems")
      ].each do |alert|
        assert_equal "open", alert.state
        assert_equal 0, alert.events.count
      end

      get "/#{@private_repo.name_with_display_owner}/settings/dependabot_rules"
      assert_response :success

      new_button = assert_test_selector("new-button").first
      get new_button["href"]
      assert_response :success

      new_form = assert_select("dependabot-alert-rule-form > form").first
      create_form_url = new_form["action"]

      new_rule_params = {
        vulnerability_alert_rule: {
          name: "I Got New Rules, I Count 'Em",
          auto_dismiss: 1,
          auto_dismiss_option: "until_patch",
          rule_behavior: "enabled_by_default",
        },
        rule_criteria: "ecosystem:RubyGems"
      }

      # Ensure a new VulnerabilityAlertRule is created:
      assert_changes -> { VulnerabilityAlertRule.count }, from: 1, to: 2 do
        perform_enqueued_jobs(only: ALL_THE_JOBS) do
          post create_form_url, params: new_rule_params
          assert_redirected_to "/#{@private_repo.name_with_display_owner}/settings/dependabot_rules"
        end
      end

      # Ensure that existing RubyGems alert is auto-dismissed:
      alert_to_auto_dismiss.reload
      assert_equal "auto_dismissed", alert_to_auto_dismiss.state
      assert_equal 1, alert_to_auto_dismiss.events.count

      # And that the existing PIP alert stayed the same:
      alert_to_stay_the_same.reload
      assert_equal "open", alert_to_stay_the_same.state
      assert_equal 0, alert_to_stay_the_same.events.count
    end

    test "editing an existing rule updates existing alerts" do
      existing_rule = VulnerabilityAlertRule.create!(
        name: "Dismiss Gemfile.lock alerts",
        target: @private_repo,
        enablement_behavior: "enabled_by_default",
        actions: { version: 1, alert_actions: { auto_dismiss: "indefinitely" } },
        conditions: {
          "manifest": ["Gemfile.lock"]
        }
      )

      # Create existing auto-dismissed alerts
      alert_to_reopen = create(:repository_vulnerability_alert,
        :auto_dismissed,
        repository: @private_repo,
        ecosystem: "RubyGems",
        vulnerable_manifest_path: "Gemfile.lock",
        last_state_change_rule_id: existing_rule.id
      )
      assert_equal "auto_dismissed", alert_to_reopen.state
      assert_equal 1, alert_to_reopen.events.count

      alert_to_dismiss = create(:repository_vulnerability_alert,
        repository: @private_repo,
        ecosystem: "npm",
        vulnerable_manifest_path: "package-lock.json"
      )
      assert_equal "open", alert_to_dismiss.state
      assert_equal 0, alert_to_dismiss.events.count

      get "/#{@private_repo.name_with_display_owner}/settings/dependabot_rules/edit/#{existing_rule.id}"
      assert_response :success
      edit_form = assert_select("dependabot-alert-rule-form > form").first
      edit_form_url = edit_form["action"]

      updated_rule_params = {
        vulnerability_alert_rule: {
          name: "Dismiss package-lock.json alerts",
          auto_dismiss: 1,
          auto_dismiss_option: "indefinitely",
          rule_behavior: "enabled_by_default",
        },
        rule_criteria: "manifest:package-lock.json" # This is changing from Gemfile.lock
      }

      perform_enqueued_jobs(only: ALL_THE_JOBS) do
        put edit_form_url, params: updated_rule_params
        assert_redirected_to "/#{@private_repo.name_with_display_owner}/settings/dependabot_rules"
      end

      existing_rule.reload
      assert_equal "Dismiss package-lock.json alerts", existing_rule.name
      assert_equal ["package-lock.json"], existing_rule.conditions.dig("manifest")

      # Ensure that existing package-lock.json alert is auto-dismissed:
      alert_to_dismiss.reload
      assert_equal "auto_dismissed", alert_to_dismiss.state
      assert_equal "rule_updated", alert_to_dismiss.last_state_change_reason
      assert_equal existing_rule.id, alert_to_dismiss.last_state_change_rule_id
      assert_equal 1, alert_to_dismiss.events.count
      last_alert_to_dismiss_event = alert_to_dismiss.events.last
      assert_equal "rule_updated", last_alert_to_dismiss_event.reason
      assert_equal existing_rule.id, last_alert_to_dismiss_event.rule_id

      # And that the existing Gemfile.lock alert was reopened:
      alert_to_reopen.reload
      assert_equal "open", alert_to_reopen.state
      assert_equal "previous_rule_updated", alert_to_reopen.last_state_change_reason
      assert_nil alert_to_reopen.last_state_change_rule_id
      assert_equal 2, alert_to_reopen.events.count
      last_alert_to_reopen_event = alert_to_reopen.events.last
      assert_equal "previous_rule_updated", last_alert_to_reopen_event.reason
      assert_equal existing_rule.id, last_alert_to_reopen_event.rule_id
    end

    test "deleting a rule reopens affected alerts" do
      existing_rule = VulnerabilityAlertRule.create!(
        name: "Dismiss Gemfile.lock alerts",
        target: @private_repo,
        enablement_behavior: "enabled_by_default",
        actions: { version: 1, alert_actions: { auto_dismiss: "indefinitely" } },
        conditions: {
          "manifest": ["Gemfile.lock"]
        }
      )

      alert_to_reopen = create(:repository_vulnerability_alert,
        :auto_dismissed,
        repository: @private_repo,
        ecosystem: "RubyGems",
        vulnerable_manifest_path: "Gemfile.lock",
        last_state_change_rule_id: existing_rule.id
      )
      assert_equal "auto_dismissed", alert_to_reopen.state
      assert_equal 1, alert_to_reopen.events.count

      get "/#{@private_repo.name_with_display_owner}/settings/dependabot_rules/edit/#{existing_rule.id}"
      assert_response :success
      delete_dialog = assert_test_selector("delete-dialog").first
      delete_form = assert_select(delete_dialog, "form").first
      delete_url = delete_form["action"]

      perform_enqueued_jobs(only: ALL_THE_JOBS) do
        delete delete_url
        assert_redirected_to "/#{@private_repo.name_with_display_owner}/settings/dependabot_rules"
      end

      assert VulnerabilityAlertRule.exists?(existing_rule.id)
      assert_equal "deleted", existing_rule.reload.state

      alert_to_reopen.reload
      assert_equal "open", alert_to_reopen.state
      assert_equal "previous_rule_deleted", alert_to_reopen.last_state_change_reason
      assert_nil alert_to_reopen.last_state_change_rule_id
      assert_equal 2, alert_to_reopen.events.count

      last_event = alert_to_reopen.events.last
      assert_equal "auto_reopened", last_event.event
      assert_equal "previous_rule_deleted", last_event.reason
      assert_equal existing_rule.id, last_event.rule_id
      assert_equal existing_rule.name, last_event.rule_name
      assert_equal existing_rule.conditions, last_event.rule_conditions
    end
  end
end unless GitHub.enterprise?
