# typed: true
# frozen_string_literal: true

require "test_helper"

class DependabotOrgRulesControllerTest < GitHub::IntegrationTestCase
  include AuditLog::IntegrationTestHelpers
  include DependabotAlertsEnterpriseEnablementHelper

  EVENTS = %w[
    vulnerability_alert_rule.create
    vulnerability_alert_rule.delete
    vulnerability_alert_rule.disable
    vulnerability_alert_rule.enable
    vulnerability_alert_rule.force_disable
    vulnerability_alert_rule.force_enable
    vulnerability_alert_rule.update
  ]

  setup do
    if GitHub.enterprise?
      stub_dependabot_alerts_enterprise_enablement
    end
  end

  fixtures do
    @random_user = create(:user, name: "random-user")
    @owner = create(:user, name: "org-owner")
    @org = create(:organization, admin: @owner)
    @member = create(:user, name: "org-member")
    @org.add_member(@member)
    @security_manager = create(:user, name: "org-security-manager")
    @org.add_member(@security_manager)
    @security_manager_team = create(:security_manager_team, organization: @org)
    @security_manager_team.add_member(@security_manager)
    @org_custom_rule = create(:vulnerability_alert_rule, target: @org)

    @default_rule = VulnerabilityAlertRule.default_auto_dismissal_rule
  end

  context "#index" do
    test "renders 404 for users who are not a memeber of the organization" do
      as @random_user
      get "/organizations/#{@org.display_login}/settings/dependabot_rules"

      assert_response :not_found
    end

    test "renders 404 for org members who don't have access to rules" do
      as @member
      get "/organizations/#{@org.display_login}/settings/dependabot_rules"

      assert_response :not_found
    end

    test "returns 404 if dependabot rules are disabled in enterprise", enterprise_only: true do
      GitHub.stubs(dependabot_rules_enabled?: false)

      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules"

      assert_response :not_found
    end

    test "renders for security managers" do
      as @security_manager
      get "/organizations/#{@org.display_login}/settings/dependabot_rules"

      assert_response :success
    end

    test "renders for an org admin" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules"

      assert_response :success
    end

    test "renders Global settings title for org with security configurations enabled" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules"

      assert_response :success
      assert_select "[data-test-selector='show-rule-subtitle']" do
        assert_select "h2 a", text: "Global settings"
      end
    end

    test "lists github preset rules" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules"

      assert_response :success
      assert_template "orgs/dependabot_rules/index"

      assert_test_selector "github-preset-rules", count: 1 do
        assert_includes response.body, T.must(VulnerabilityAlertRule.global.first).name
        assert_test_selector "rule-status-label", count: 1
      end
    end

    test "lists custom rules" do
      second_org_rule = create(:vulnerability_alert_rule,
        name: "Dismiss alerts",
        enablement_behavior: "enabled_by_default",
        target: @org,
        actions: {
          version: 1,
          alert_actions: {
            auto_dismiss: "indefinitely"
          }
        },
        conditions: {
          cwe: ["CWE-1400"],
          severity: ["low"],
        }
      )
      # Create a rule owned by another org, just to validate that we don't grab it:
      another_org = create(:organization)
      not_our_org_rule = create(:vulnerability_alert_rule, target: another_org, name: "Not ours!")

      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules"

      assert_response :success
      assert_template "orgs/dependabot_rules/index"

      assert_test_selector "github-preset-rules", count: 1 do
        assert_includes response.body, T.must(VulnerabilityAlertRule.global.first).name
        assert_test_selector "rule-status-label", count: 1
      end

      assert_test_selector "custom-rules", count: 1 do
        assert_includes response.body, @org_custom_rule.name
        assert_includes response.body, second_org_rule.name
        assert_test_selector "rule-status-label", count: 2
      end

      refute_includes response.body, not_our_org_rule.name
    end

    test "list rules with proper status labels" do
      default_rule_override = create(:vulnerability_alert_rule_override,
        rule: VulnerabilityAlertRule.default_auto_dismissal_rule,
        target: @org,
        enabled: true,
        enforcement: "enforced_for_all",
      )

      create(:vulnerability_alert_rule,
        name: "Dismiss alerts",
        enablement_behavior: "force_disabled",
        target: @org,
        actions: {
          version: 1,
          alert_actions: {
            auto_dismiss: "indefinitely"
          }
        },
        conditions: {
          cwe: ["CWE-1400"],
          severity: ["low"],
        }
      )

      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules"

      assert_response :success
      assert_template "orgs/dependabot_rules/index"

      assert_test_selector "github-preset-rules", count: 1 do
        assert_test_selector "rule-status-label", count: 1, text: "Enforced"
      end

      assert_test_selector "custom-rules", count: 1 do
        assert_test_selector "rule-status-label", count: 1, text: "Enabled"
        assert_test_selector "rule-status-label", count: 1, text: "Disabled"
      end
    end

    test "will paginate if the number of custom rules is more than PAGE_SIZE" do
      (1..Dependabot::DependabotOrgRulesController::PAGE_SIZE + 1).each do |i|
        @org_custom_rule.dup.update(name: "Dismiss alert#{i}")
      end

      org_rules = OrganizationVulnerabilityAlertRules.new(organization: @org)
      assert org_rules.custom_rules.count > Dependabot::DependabotOrgRulesController::PAGE_SIZE

      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules"

      assert_response :success
      assert_template "orgs/dependabot_rules/index"

      assert_test_selector "custom-rules", count: 1
      assert_test_selector "custom-rule-row", count: 10
    end
  end

  context "#new" do
    test "renders 404 for users who are not a memeber of the organization" do
      as @random_user
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/new"

      assert_response :not_found
    end

    test "renders 404 for org members who don't have access to rules" do
      as @member
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/new"

      assert_response :not_found
    end

    test "returns 404 if dependabot rules are disabled in enterprise", enterprise_only: true do
      GitHub.stubs(dependabot_rules_enabled?: false)

      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/new"

      assert_response :not_found
    end

    test "renders for security managers" do
      as @security_manager
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/new"

      assert_response :success
    end

    test "renders for an org admin" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/new"

      assert_response :success
    end

    test "renders the input form" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/new"

      assert_response :success

      # Name field
      assert_select "[name=vulnerability_alert_rule\\[name\\]]", count: 1

      # Rule criteria bar
      assert_select "query-builder[data-test-selector=dependabot-alert-rule-criteria-bar]", count: 1

      # Checkbox for dismissing alerts
      assert_select "input[name=vulnerability_alert_rule\\[auto_dismiss\\]][checked=checked]", count: 1

      # Options for dismissing alerts
      assert_select "input[name=vulnerability_alert_rule\\[auto_dismiss_option\\]][value=until_patch][checked=checked]", count: 1
      assert_select "input[name=vulnerability_alert_rule\\[auto_dismiss_option\\]][value=indefinitely]", count: 1

      # Submit button
      assert_test_selector "rule_form_button", count: 1
    end

    test "renders Global settings title for org with security configurations enabled" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/new"

      assert_response :success

      assert_select "[data-test-selector='new-rule-subtitle']" do
        assert_select "h2 a", text: "Global settings"
      end
    end
  end

  context "#create" do
    test "prevents user from creating a rule if they already have the maximum number of rules in the org" do
      Dependabot::DependabotOrgRulesController.any_instance.stubs(:has_maximum_rules?).returns(true)

      assert_no_changes -> { VulnerabilityAlertRule.count } do
        as @owner
        post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
          vulnerability_alert_rule: {
            name: "Testing new",
            auto_dismiss: "1",
            auto_dismiss_option: "indefinitely",
            rule_behavior: "enabled_by_default"
          },
          rule_criteria: "severity:high package:faraday ecosystem:RubyGems scope:development cwe:391 severity:low  ",
        }
      end

      assert_match /Maximum number/, flash[:error]
      assert_response :redirect
    end

    test "returns 404 if dependabot rules are disabled in enterprise", enterprise_only: true do
      GitHub.stubs(dependabot_rules_enabled?: false)

      as @owner
      post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
        vulnerability_alert_rule: {
          name: "Testing new",
          auto_dismiss: "1",
          auto_dismiss_option: "indefinitely",
          rule_behavior: "enabled_by_default"
        },
        rule_criteria: "severity:high",
      }

      assert_response :not_found
    end

    test "creates a rule with the enablement behavior set to enabled_by_default" do
      assert_changes -> { VulnerabilityAlertRule.count }, 1 do
        as @owner
        post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
          vulnerability_alert_rule: {
            name: "Testing new",
            auto_dismiss: "1",
            auto_dismiss_option: "indefinitely",
            rule_behavior: "enabled_by_default"
          },
          rule_criteria: "severity:high package:faraday ecosystem:RubyGems scope:development cwe:391 severity:low  ",
        }
      end

      rule = VulnerabilityAlertRule.last
      assert_equal @org, T.must(rule).target
      assert_equal "enabled_by_default", T.must(rule).enablement_behavior
      assert_equal 0, VulnerabilityAlertRuleOverride.where(rule_id: T.must(rule).id).count

      assert_response :redirect
    end

    test "creates a rule with the enablement behavior set to force_enabled" do
      assert_changes -> { VulnerabilityAlertRule.count }, 1 do
        as @owner
        post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
          vulnerability_alert_rule: {
            name: "Testing new",
            auto_dismiss: "1",
            auto_dismiss_option: "indefinitely",
            rule_behavior: "force_enabled"
          },
          rule_criteria: "severity:high package:faraday ecosystem:RubyGems scope:development cwe:391 severity:low  ",
        }
      end

      rule = VulnerabilityAlertRule.last
      assert_equal @org, T.must(rule).target
      assert_equal "force_enabled", T.must(rule).enablement_behavior
      assert_equal 0, VulnerabilityAlertRuleOverride.where(rule_id: T.must(rule).id).count

      assert flash[:notice], "Rule saved. It may take a moment for this rule to be applied to matching alerts"
      assert_response :redirect
    end

    test "creates a rule with the enablement behavior set to force_disabled" do
      original_count = VulnerabilityAlertRule.count
      assert_changes -> { VulnerabilityAlertRule.count }, 1 do
        as @owner
        post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
          vulnerability_alert_rule: {
            name: "Testing new",
            auto_dismiss: "1",
            auto_dismiss_option: "indefinitely",
            rule_behavior: "force_disabled"
          },
          rule_criteria: "severity:high package:faraday ecosystem:RubyGems scope:development cwe:391 severity:low  ",
        }
      end

      rule = VulnerabilityAlertRule.last
      assert_equal @org, T.must(rule).target
      assert_equal "force_disabled", T.must(rule).enablement_behavior
      assert_equal 0, VulnerabilityAlertRuleOverride.where(rule_id: T.must(rule).id).count

      assert_response :redirect
    end

    test "requires the rule name to be present" do
      as @owner
      post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
        vulnerability_alert_rule: {
          name: " ",
          auto_dismiss: "1",
          auto_dismiss_option: "indefinitely",
          rule_behavior: "force_enabled"
        },
        rule_criteria: "severity:high package:faraday ecosystem:RubyGems scope:development cwe:391 severity:low  ",
      }

      assert_test_selector "rule-form-error-message" do
        assert_select "div", /The following inputs have errors/
        assert_select "span", text: "Rule name", count: 1
      end

      assert_test_selector "dependabot-alert-rule-name" do
        assert_select "span", text: "Enter rule name", count: 1
      end
      assert_response :ok
    end

    test "requires the alert criteria be present" do
      as @owner
      post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
        vulnerability_alert_rule: {
          name: "foo",
          auto_dismiss: "1",
          auto_dismiss_option: "indefinitely",
          rule_behavior: "force_enabled"
        },
        rule_criteria: "",
      }

      assert_test_selector "rule-form-error-message" do
        assert_select "div", /The following inputs have errors/
        assert_select "span", text: "Target alerts", count: 1
      end

      assert_test_selector "dependabot-alert-rule-criteria-bar" do
        assert_select "span", text: "Enter alert metadata", count: 1
      end
      assert_response :ok
    end

    test "requires the alert criteria to be valid" do
      as @owner
      post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
        vulnerability_alert_rule: {
          name: "foo",
          auto_dismiss: "1",
          auto_dismiss_option: "indefinitely",
          rule_behavior: "force_enabled"
        },
        rule_criteria: "severity:foo",
      }

      assert_test_selector "rule-form-error-message" do
        assert_select "div", /The following inputs have errors/
        assert_select "span", text: "Target alerts", count: 1
      end

      assert_test_selector "dependabot-alert-rule-criteria-bar" do
        assert_select "span", text: "severity has an invalid value: foo", count: 1
      end
      assert_response :ok
    end

    test "requires that a rule action be selected" do
      as @owner
      post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
        vulnerability_alert_rule: {
          name: "foo",
          rule_behavior: "force_enabled"
        },
        rule_criteria: "severity:High package:faraday ecosystem:RubyGems scope:development cwe:391 severity:Low ",
      }
      assert_response :ok

      assert_test_selector "rule-form-error-message" do
        assert_select "div", /The following inputs have errors/
        assert_select "span", text: "Rules", count: 1
      end

      assert_test_selector "rules-form-control" do
        assert_select "span", text: "At least one selection is required", count: 1
      end
    end

    test "requires that auto-dismiss rule action have a valid value" do
      as @owner
      post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
        vulnerability_alert_rule: {
          name: "foo",
          auto_dismiss: "1",
          auto_dismiss_option: "never",
          rule_behavior: "force_enabled"

        },
        rule_criteria: "severity:High package:faraday ecosystem:RubyGems scope:development cwe:391 severity:Low ",
      }
      assert_response :ok

      assert_test_selector "rule-form-error-message" do
        assert_select "div", /The following inputs have errors/
        assert_select "span", text: "Rules", count: 1
      end
    end

    test "requires that enforcement to have a valid value" do
      as @owner

      assert_no_difference -> { VulnerabilityAlertRule.count } do
        post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
          vulnerability_alert_rule: {
            name: "foo",
            auto_dismiss: "1",
            auto_dismiss_option: "indefinitely",
            rule_behavior: "give me GHAS",
          },
          rule_criteria: "severity:High package:faraday ecosystem:RubyGems scope:development cwe:391 severity:Low ",
        }
      end

      assert_test_selector "rule-form-error-message" do
        assert_test_selector "attribute-with-error", text: "State", count: 1
      end
    end

    test "manifest filter cannot be used in alert criteria" do
      as @owner
      post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
        vulnerability_alert_rule: {
          name: "foo",
          auto_dismiss: "1",
          auto_dismiss_option: "indefinitely",
          rule_behavior: "force_enabled"
        },
        rule_criteria: "manifest:package-lock.json",
      }

      assert_test_selector "rule-form-error-message" do
        assert_select "div", /The following inputs have errors/
        assert_select "span", text: "Target alerts", count: 1
      end

      assert_test_selector "dependabot-alert-rule-criteria-bar" do
        assert_select "span", text: "cannot use manifest filter on organization rule", count: 1
      end
      assert_response :ok
    end

    if GitHub.rate_limiting_enabled?
      test "returns an error if rate limit is exceeded" do
        Dependabot::DependabotOrgRulesController.any_instance.expects(:rate_limit_increment_limited?).once.returns(true)

        assert_no_changes -> { VulnerabilityAlertRule.count } do
          as @owner
          post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
            vulnerability_alert_rule: {
              name: "This should fail!",
              auto_dismiss: "1",
              auto_dismiss_option: "indefinitely",
              rule_behavior: "enabled_by_default"
            },
            rule_criteria: "severity:high package:faraday ecosystem:RubyGems scope:development cwe:391 severity:low  ",
          }
        end

        assert_response :redirect; follow_redirect!
        assert_test_selector "flash-container",
          text: "You have exceeded our rule change rate limit. Please wait an hour before you try again."
      end
    end

    test "creates an audit log entry when creating a rule" do
      as @owner

      # During rule creation, we only want a "create" audit log entry
      # with no corresponding "enable" or "disable" entry.
      events =
        assert_performed_audit_entries(count: 1, only: EVENTS) do
          assert_difference -> { VulnerabilityAlertRule.count }, 1 do
            post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
              vulnerability_alert_rule: {
                name: "foo",
                auto_dismiss: "1",
                auto_dismiss_option: "indefinitely",
                rule_behavior: "enabled_by_default"
              },
              rule_criteria: "severity:low",
            }
          end
        end

      rule = VulnerabilityAlertRule.order(:id).last
      event = events.sole
      assert_equal "vulnerability_alert_rule.create", event[:action]
      assert_equal @owner.id, event[:actor_id]
      assert_equal @org.id, event[:org_id]
      assert_equal T.must(rule).id, event[:vulnerability_alert_rule_id]
    end
  end

  context "#edit" do
    test "renders 404 for users who are not a memeber of the organization" do
      as @random_user
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit/#{@org_custom_rule.id}"

      assert_response :not_found
    end

    test "renders 404 for org members who don't have access to rules" do
      as @member
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit/#{@org_custom_rule.id}"

      assert_response :not_found
    end

    test "returns 404 if dependabot rules are disabled in enterprise", enterprise_only: true do
      GitHub.stubs(dependabot_rules_enabled?: false)

      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit/#{@org_custom_rule.id}"

      assert_response :not_found
    end

    test "renders for security managers" do
      as @security_manager
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit/#{@org_custom_rule.id}"

      assert_response :success
    end

    test "renders for an org admin" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit/#{@org_custom_rule.id}"

      assert_response :success
    end

    test "renders the form with the rule attributes" do
      GitHub.stubs(dependabot_enabled?: true)
      rule = create(
        :vulnerability_alert_rule,
        target: @org,
        name: "one-rule-to-rule-them-all",
        conditions: {
          "severity": ["low"],
          "ecosystem": ["npm"],
          "package": ["lodash"],
          "scope": ["development"],
          "cwe": ["CWE-123"]
        },
        actions: {
          "version" => 1,
          "alert_actions" => { "auto_dismiss" => "indefinitely" }
        },
        enablement_behavior: "enabled_by_default"
      )

      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit/#{rule.id}"

      assert_response :success

      assert_select "[name=vulnerability_alert_rule\\[name\\]][value=one-rule-to-rule-them-all]", count: 1
      assert_select "[data-target='dependabot-alert-rule-form.rule']", count: 1 do |checkbox|
        assert_equal "checked", checkbox[0].attributes["checked"].value
      end
      assert_select "[value=until_patch]", count: 1 do |radio|
        assert_nil radio[0].attributes["checked"]
      end
      assert_select "[value=indefinitely]", count: 1 do |radio|
        assert_equal "checked", radio[0].attributes["checked"].value
      end
      assert_select "[data-target='dependabot-alert-rule-form.updateRule']", count: 1 do |checkbox|
        assert_nil checkbox[0].attributes["checked"]
      end
      assert_select "#rule-criteria-input-combobox", count: 1 do |search_bar|
        assert_equal "severity:low package:lodash ecosystem:npm scope:development cwe:123 ", search_bar[0].attributes["value"].value
      end
    end

    test "renders Global settings title for org with security configurations enabled" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit/#{@org_custom_rule.id}"

      assert_response :success

      assert_select "[data-test-selector='edit-rule-subtitle']" do
        assert_select "h2 a", text: "Global settings"
      end
    end

    test "does not render the 'open a PR' portion of the form when Dependabot is disabled" do
      GitHub.stubs(:dependabot_enabled?).returns(false)

      rule = create(
        :vulnerability_alert_rule,
        target: @org,
        name: "one-rule-to-rule-them-all",
        conditions: {
          "severity": ["low"],
          "ecosystem": ["npm"],
          "package": ["lodash"],
          "scope": ["development"],
          "cwe": ["CWE-123"]
        },
        actions: {
          "version" => 1,
          "alert_actions" => { "auto_dismiss" => "indefinitely" }
        },
        enablement_behavior: "enabled_by_default"
      )

      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit/#{rule.id}"

      assert_response :success

      assert_select "[name=vulnerability_alert_rule\\[name\\]][value=one-rule-to-rule-them-all]", count: 1
      refute_select "[data-target='dependabot-alert-rule-form.updateRule']"
    end
  end

  context "#edit_global_rule" do
    test "renders for security managers" do
      org_global_rule = create(:vulnerability_alert_rule, :global)
      as @security_manager
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit_default/#{org_global_rule.id}"

      assert_response :success
    end

    test "returns 404 if dependabot rules are disabled in enterprise", enterprise_only: true do
      org_global_rule = create(:vulnerability_alert_rule, :global)
      GitHub.stubs(dependabot_rules_enabled?: false)

      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit_default/#{org_global_rule.id}"

      assert_response :not_found
    end

    test "renders form with global rule enforcement options" do
      org_global_rule = create(:vulnerability_alert_rule, :global)
      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit_default/#{org_global_rule.id}"

      assert_response :success
      assert_test_selector "edit-global-rule", count: 1
      assert_test_selector "dependabot-alert-enforcement-options-menu", count: 1
    end

    test "renders Global settings title for org with security configurations enabled" do
      org_global_rule = create(:vulnerability_alert_rule, :global)
      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit_default/#{org_global_rule.id}"

      assert_response :success

      assert_test_selector "edit-global-rule-subtitle"  do
        assert_select "h2 a", text: "Global settings"
      end
    end

    test "rule enforcement form renders 'Enabled' by default" do
      org_global_rule = create(:vulnerability_alert_rule, :global)
      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit_default/#{org_global_rule.id}"

      assert_response :success
      assert_test_selector "enforcement-options-menu"
      assert_select "[data-value=enabled_by_default][aria-checked=true]", count: 1
    end

    test "rule enforcement form renders 'Enforced' when an org override is set to enabled: true" do
      org_global_rule = create(:vulnerability_alert_rule, :global, :enabled_by_default_for_public)

      org_global_rule_override = VulnerabilityAlertRuleOverride.create(
        target: @org,
        rule_id: org_global_rule.id,
        enabled: true,
        enforcement: "enforced_for_all"
      )
      assert VulnerabilityAlertRuleOverride.exists?(org_global_rule_override.id)

      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit_default/#{org_global_rule.id}"

      assert_response :success
      assert_test_selector "enforcement-options-menu"
      assert_select "[data-value=force_enabled][aria-checked=true]", count: 1
    end

    test "rule enforcement form renders 'Disabled' when an org override is set to enabled: false" do
      org_global_rule = create(:vulnerability_alert_rule, :global, :enabled_by_default_for_public)

      org_global_rule_override = VulnerabilityAlertRuleOverride.create(
        target: @org,
        rule_id: org_global_rule.id,
        enabled: false,
        enforcement: "enforced_for_all"
      )
      assert VulnerabilityAlertRuleOverride.exists?(org_global_rule_override.id)

      as @owner
      get "/organizations/#{@org.display_login}/settings/dependabot_rules/edit_default/#{org_global_rule.id}"

      assert_response :success
      assert_test_selector "enforcement-options-menu"
      assert_select "[data-value=force_disabled][aria-checked=true]", count: 1
    end
  end

  context "#update" do
    test "returns 404 if dependabot rules are disabled in enterprise", enterprise_only: true do
      GitHub.stubs(dependabot_rules_enabled?: false)

      as @owner
      post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
        vulnerability_alert_rule: {
          name: "foo",
          auto_dismiss: "1",
          auto_dismiss_option: "indefinitely",
          rule_behavior: "enabled_by_default"
        },
        rule_criteria: "severity:low",
      }

      assert_response :not_found
    end

    test "creates an audit log entry when updating the rule" do
      as @owner
      assert_difference -> { VulnerabilityAlertRule.count }, 1 do
        post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
          vulnerability_alert_rule: {
            name: "foo",
            auto_dismiss: "1",
            auto_dismiss_option: "indefinitely",
            rule_behavior: "enabled_by_default"
          },
          rule_criteria: "severity:low",
        }
      end
      rule = VulnerabilityAlertRule.order(:id).last

      events =
        assert_performed_audit_entries(count: 1, only: EVENTS) do
          put "/organizations/#{@org.display_login}/settings/dependabot_rules/#{T.must(rule).id}", params: {
            vulnerability_alert_rule: {
              name: "bar",
              auto_dismiss: "1",
              auto_dismiss_option: "indefinitely",
              rule_behavior: "enabled_by_default"
            },
            rule_criteria: "severity:low",
          }
        end

      event = events.sole
      assert_equal "vulnerability_alert_rule.update", event[:action]
      assert_equal @owner.id, event[:actor_id]
      assert_equal @org.id, event[:org_id]
      assert_equal T.must(rule).id, event[:vulnerability_alert_rule_id]
    end

    test "creates an audit log entry when enabling the rule" do
      as @owner
      assert_difference -> { VulnerabilityAlertRule.count }, 1 do
        post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
          vulnerability_alert_rule: {
            name: "foo",
            auto_dismiss: "1",
            auto_dismiss_option: "indefinitely",
            rule_behavior: "force_disabled"
          },
          rule_criteria: "severity:low",
        }
      end
      rule = VulnerabilityAlertRule.order(:id).last

      events =
        assert_performed_audit_entries(count: 1, only: EVENTS) do
          put "/organizations/#{@org.display_login}/settings/dependabot_rules/#{T.must(rule).id}", params: {
            vulnerability_alert_rule: {
              name: "foo",
              auto_dismiss: "1",
              auto_dismiss_option: "indefinitely",
              rule_behavior: "enabled_by_default"
            },
            rule_criteria: "severity:low",
          }
        end

      event = events.sole
      assert_equal "vulnerability_alert_rule.enable", event[:action]
      assert_equal @owner.id, event[:actor_id]
      assert_equal @org.id, event[:org_id]
      assert_equal T.must(rule).id, event[:vulnerability_alert_rule_id]
    end

    test "creates an audit log entry when force enabling the rule" do
      as @owner
      assert_difference -> { VulnerabilityAlertRule.count }, 1 do
        post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
          vulnerability_alert_rule: {
            name: "foo",
            auto_dismiss: "1",
            auto_dismiss_option: "indefinitely",
            rule_behavior: "force_disabled"
          },
          rule_criteria: "severity:low",
        }
      end
      rule = VulnerabilityAlertRule.order(:id).last

      events =
        assert_performed_audit_entries(count: 1, only: EVENTS) do
          put "/organizations/#{@org.display_login}/settings/dependabot_rules/#{T.must(rule).id}", params: {
            vulnerability_alert_rule: {
              name: "foo",
              auto_dismiss: "1",
              auto_dismiss_option: "indefinitely",
              rule_behavior: "force_enabled"
            },
            rule_criteria: "severity:low",
          }
        end

      event = events.sole
      assert_equal "vulnerability_alert_rule.force_enable", event[:action]
      assert_equal @owner.id, event[:actor_id]
      assert_equal @org.id, event[:org_id]
      assert_equal T.must(rule).id, event[:vulnerability_alert_rule_id]
    end

    test "creates an audit log entry when force disabling the rule" do
      as @owner
      assert_difference -> { VulnerabilityAlertRule.count }, 1 do
        post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
          vulnerability_alert_rule: {
            name: "foo",
            auto_dismiss: "1",
            auto_dismiss_option: "indefinitely",
            rule_behavior: "enabled_by_default"
          },
          rule_criteria: "severity:low",
        }
      end
      rule = VulnerabilityAlertRule.order(:id).last

      events =
        assert_performed_audit_entries(count: 1, only: EVENTS) do
          put "/organizations/#{@org.display_login}/settings/dependabot_rules/#{T.must(rule).id}", params: {
            vulnerability_alert_rule: {
              name: "foo",
              auto_dismiss: "1",
              auto_dismiss_option: "indefinitely",
              rule_behavior: "force_disabled"
            },
            rule_criteria: "severity:low",
          }
        end

      event = events.sole
      assert_equal "vulnerability_alert_rule.force_disable", event[:action]
      assert_equal @owner.id, event[:actor_id]
      assert_equal @org.id, event[:org_id]
      assert_equal T.must(rule).id, event[:vulnerability_alert_rule_id]
    end

    test "creates two audit log entries when updating and enabling then rule" do
      as @owner
      assert_difference -> { VulnerabilityAlertRule.count }, 1 do
        post "/organizations/#{@org.display_login}/settings/dependabot_rules", params: {
          vulnerability_alert_rule: {
            name: "foo",
            auto_dismiss: "1",
            auto_dismiss_option: "indefinitely",
            rule_behavior: "force_disabled"
          },
          rule_criteria: "severity:low",
        }
      end
      rule = VulnerabilityAlertRule.order(:id).last

      update_event, enable_event =
        assert_performed_audit_entries(count: 2, only: EVENTS) do
          put "/organizations/#{@org.display_login}/settings/dependabot_rules/#{T.must(rule).id}", params: {
            vulnerability_alert_rule: {
              name: "bar",
              auto_dismiss: "1",
              auto_dismiss_option: "indefinitely",
              rule_behavior: "enabled_by_default"
            },
            rule_criteria: "severity:low",
          }
        end

      assert_equal "vulnerability_alert_rule.update", update_event[:action]
      assert_equal @owner.id, update_event[:actor_id]
      assert_equal @org.id, update_event[:org_id]
      assert_equal T.must(rule).id, update_event[:vulnerability_alert_rule_id]

      assert_equal "vulnerability_alert_rule.enable", enable_event[:action]
      assert_equal @owner.id, enable_event[:actor_id]
      assert_equal @org.id, enable_event[:org_id]
      assert_equal T.must(rule).id, enable_event[:vulnerability_alert_rule_id]
    end
  end

  context "#update_global_rule" do
    test "returns 404 if dependabot rules are disabled in enterprise", enterprise_only: true do
      default_rule = VulnerabilityAlertRule.default_auto_dismissal_rule
      GitHub.stubs(dependabot_rules_enabled?: false)

      as @owner
      put "/organizations/#{@org.display_login}/settings/dependabot_rules/update_default/#{default_rule.id}", params: {
        rule_behavior: "enabled_by_default"
      }

      assert_response :not_found
    end

    test "when the default rule is changed to be enabled by default" do
      as @owner
      assert_enqueued_jobs 1, only: ReprocessOrganizationAlertRulesJob do
        put "/organizations/#{@org.display_login}/settings/dependabot_rules/update_default/#{@default_rule.id}", params: {
          rule_behavior: "enabled_by_default"
        }
      end

      override = VulnerabilityAlertRuleOverride.for_organization(@org).where(rule_id: @default_rule.id).first
      refute_nil override
      assert_equal true, T.must(override).enabled?
      assert_equal true,  T.must(override).not_enforced?
    end

    test "when the default rule is changed to be enforced" do
      as @owner
      assert_enqueued_jobs 1, only: ReprocessOrganizationAlertRulesJob do
        put "/organizations/#{@org.display_login}/settings/dependabot_rules/update_default/#{@default_rule.id}", params: {
          rule_behavior: "force_enabled"
        }
      end

      override = VulnerabilityAlertRuleOverride.for_organization(@org).where(rule_id: @default_rule.id).first
      refute_nil override
      assert_equal true, T.must(override).enabled?
      assert_equal true,  T.must(override).enforced_for_all?
    end

    test "when the default rule is changed to be disabled" do
      as @owner
      assert_enqueued_jobs 1, only: ReprocessOrganizationAlertRulesJob do
        put "/organizations/#{@org.display_login}/settings/dependabot_rules/update_default/#{@default_rule.id}", params: {
          rule_behavior: "force_disabled"
        }
      end

      override = VulnerabilityAlertRuleOverride.for_organization(@org).where(rule_id: @default_rule.id).first
      refute_nil override
      assert_equal false, T.must(override).enabled?
      assert_equal true,  T.must(override).enforced_for_all?
    end

    test "does not enqueue job to reprocess alerts when rule behavior does not change" do

      %w[force_enabled force_disabled enabled_by_default].each do |rule_behavior|
        # Remove all overrides for the org to start at a clean slate
        VulnerabilityAlertRuleOverride.where(target: @org).destroy_all

        # Update the behavior of the default rule the first time
        as @owner
        put "/organizations/#{@org.display_login}/settings/dependabot_rules/update_default/#{@default_rule.id}", params: {
          rule_behavior:
        }

        # Update the behavior of the default rule the second time and assert that no job is enqueued
        assert_no_enqueued_jobs only: ReprocessOrganizationAlertRulesJob do
          as @owner
          put "/organizations/#{@org.display_login}/settings/dependabot_rules/update_default/#{@default_rule.id}", params: {
            rule_behavior:
          }
        end
      end
    end

    test "creates an audit log entry when enabling the default rule" do
      as @owner

      events =
        assert_performed_audit_entries(count: 1, only: EVENTS) do
          put "/organizations/#{@org.display_login}/settings/dependabot_rules/update_default/#{@default_rule.id}", params: {
            rule_behavior: "enabled_by_default"
          }
        end

      event = events.sole
      assert_equal "vulnerability_alert_rule.enable", event[:action]
      assert_equal @owner.id, event[:actor_id]
      assert_equal @org.id, event[:org_id]
      assert_equal @default_rule.id, event[:vulnerability_alert_rule_id]
    end

    test "creates an audit log entry when enabling the previously disabled default rule" do
      as @owner
      create(:vulnerability_alert_rule_override, :force_disabled, rule: @default_rule, target: @org)

      events =
        assert_performed_audit_entries(count: 1, only: EVENTS) do
          put "/organizations/#{@org.display_login}/settings/dependabot_rules/update_default/#{@default_rule.id}", params: {
            rule_behavior: "enabled_by_default"
          }
        end

      event = events.sole
      assert_equal "vulnerability_alert_rule.enable", event[:action]
      assert_equal @owner.id, event[:actor_id]
      assert_equal @org.id, event[:org_id]
      assert_equal @default_rule.id, event[:vulnerability_alert_rule_id]
    end

    test "creates an audit log entry when force enabling the default rule" do
      as @owner

      events =
        assert_performed_audit_entries(count: 1, only: EVENTS) do
          put "/organizations/#{@org.display_login}/settings/dependabot_rules/update_default/#{@default_rule.id}", params: {
            rule_behavior: "force_enabled"
          }
        end

      event = events.sole
      assert_equal "vulnerability_alert_rule.force_enable", event[:action]
      assert_equal @owner.id, event[:actor_id]
      assert_equal @org.id, event[:org_id]
      assert_equal @default_rule.id, event[:vulnerability_alert_rule_id]
    end

    test "creates an audit log entry when force disabling the default rule" do
      as @owner

      events =
        assert_performed_audit_entries(count: 1, only: EVENTS) do
          put "/organizations/#{@org.display_login}/settings/dependabot_rules/update_default/#{@default_rule.id}", params: {
            rule_behavior: "force_disabled"
          }
        end

      event = events.sole
      assert_equal "vulnerability_alert_rule.force_disable", event[:action]
      assert_equal @owner.id, event[:actor_id]
      assert_equal @org.id, event[:org_id]
      assert_equal @default_rule.id, event[:vulnerability_alert_rule_id]
    end
  end

  context "#destroy" do
    test "isn't accessible to users who don't have admin permission on the org" do
      as @random_user
      delete "/organizations/#{@org.display_login}/settings/dependabot_rules/#{@org_custom_rule.id}"

      assert_response :not_found
    end

    test "is accessible to security managers" do
      as @security_manager
      delete "/organizations/#{@org.display_login}/settings/dependabot_rules/#{@org_custom_rule.id}"

      assert_response :redirect # Not :success because we don't get a 200 OK but instead a 302 Found redirect to index
    end

    test "renders 404 if the rule doesn't exist" do
      as @owner
      missing_rule_id = VulnerabilityAlertRule.maximum(:id).to_i + 1
      delete "/organizations/#{@org.display_login}/settings/dependabot_rules/#{missing_rule_id}"

      assert_response :not_found
    end

    test "returns 404 if dependabot rules are disabled in enterprise", enterprise_only: true do
      GitHub.stubs(dependabot_rules_enabled?: false)

      as @owner
      delete "/organizations/#{@org.display_login}/settings/dependabot_rules/#{@org_custom_rule.id}"

      assert_response :not_found
    end

    test "deletes a rule from the org" do
      org_rule = create(:vulnerability_alert_rule,
        target: @org,
        name: "Delete me",
        enablement_behavior: "force_enabled"
      )
      assert VulnerabilityAlertRule.exists?(org_rule.id)

      as @owner
      delete "/organizations/#{@org.display_login}/settings/dependabot_rules/#{org_rule.id}"

      assert_redirected_to "/organizations/#{@org.display_login}/settings/dependabot_rules"

      assert VulnerabilityAlertRule.exists?(org_rule.id)
      assert_equal "deleted", org_rule.reload.state
    end

    test "deletes any existing overrides when rule is deleted" do
      org_rule = create(:vulnerability_alert_rule,
        target: @org,
        name: "Delete me",
        enablement_behavior: "force_enabled"
      )
      assert VulnerabilityAlertRule.exists?(org_rule.id)

      VulnerabilityAlertRuleOverride.create(target: @org, rule: org_rule, enabled: false)

      assert VulnerabilityAlertRuleOverride.exists?(target: @org, rule: org_rule)

      as @owner
      delete "/organizations/#{@org.display_login}/settings/dependabot_rules/#{org_rule.id}"

      assert_response :redirect

      refute VulnerabilityAlertRuleOverride.exists?(target: @org, rule: org_rule)
      assert VulnerabilityAlertRule.exists?(org_rule.id)
      assert_equal "deleted", org_rule.reload.state
    end

    test "creates an audit log entry when deleting the rule" do
      as @owner
      rule = create(:vulnerability_alert_rule, :force_disabled, target: @org)

      events =
        assert_performed_audit_entries(count: 1, only: EVENTS) do
          assert_changes -> { rule.reload.active? }, from: true, to: false do
            delete "/organizations/#{@org.display_login}/settings/dependabot_rules/#{rule.id}"
          end
        end

      event = events.sole
      assert_equal "vulnerability_alert_rule.delete", event[:action]
      assert_equal @owner.id, event[:actor_id]
      assert_equal @org.id, event[:org_id]
      assert_equal rule.id, event[:vulnerability_alert_rule_id]
    end
  end
end
