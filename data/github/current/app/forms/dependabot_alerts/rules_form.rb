# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class RulesForm < ApplicationForm
    form do |f|
      T.bind(self, RulesForm)

      f.hidden(
        label: "",
        name: "dependabot_updates_enabled",
        value: dependabot_updates_enabled?,
        scope_name_to_model: false
      )

      f.check_box_group(
        border: true,
        border_radius: 2,
        mt: 1,
        mb: 0,
        pt: 3,
        pr: 3,
        pb: 0,
        pl: 3,
        border_color: invalid? ? :danger_emphasis : nil,
      ) do |check_group|
        check_group.check_box(
          name: :auto_dismiss,
          label: "Dismiss alerts",
          caption: "Dependabot will automatically close or reopen alerts based on selected criteria.",
          checked: auto_dismiss_selected?,
          data: {
            action: "
              change:dependabot-alert-rule-form#toggleRuleCheckbox
            ",
            target: "dependabot-alert-rule-form.rule"
          }
        ) do |check_box|
          check_box.nested_form do |builder|
            RuleOptionsForm.new(builder, rule: @rule)
          end
        end

        if should_render_update_rule?
          check_group.check_box(
            name: :create_pr,
            label: "Open a pull request to resolve alerts",
            caption: update_rule_caption,
            checked: create_pull_request_selected?,
            disabled: !create_pull_request_enabled?,
            data: {
              target: "dependabot-alert-rule-form.updateRule"
            }
          )
        end
      end
    end

    sig { params(rule: VulnerabilityAlertRule).void }
    def initialize(rule:)
      @rule = rule
    end

    sig { returns(T::Boolean) }
    def auto_dismiss_selected?
      !@rule.actions.nil? && @rule.actions["alert_actions"] && @rule.actions["alert_actions"].has_key?("auto_dismiss")
    end

    sig { returns(T::Boolean) }
    def create_pull_request_selected?
      return true if dependabot_updates_enabled?

      !@rule.actions.nil? &&
        !@rule.actions["update_actions"].nil? &&
        @rule.actions["update_actions"]["create_pr"].to_s == "true"
    end

    sig { returns(T::Boolean) }
    def create_pull_request_enabled?
      return false if dependabot_updates_enabled?

      @rule.dismiss_until_patch?
    end

    sig { returns(T::Boolean) }
    def dependabot_updates_enabled?
      return false unless GitHub.dependabot_enabled?

      @rule.target.try(:vulnerability_updates_enabled?) || false
    end

    sig { returns(T::Boolean) }
    def should_render_update_rule?
      return false if @rule.global? || @rule.target.nil?

      GitHub.dependabot_enabled?
    end

    sig { returns(String) }
    def update_rule_caption
      return "Dependabot will always try to open a pull request to resolve open alerts when security updates are enabled." \
        if @rule.target_type == "Repository" && dependabot_updates_enabled?

      "Dependabot will attempt to open security updates based on selected criteria. This will only target repositories without security updates enabled."
    end

    sig { returns(T::Boolean) }
    def invalid?
      @rule.errors.include?(:actions)
    end
  end
end
