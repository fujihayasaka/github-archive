# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class RuleOptionsForm < ApplicationForm
    form do |f|
      T.bind(self, RuleOptionsForm)

      f.radio_button_group(
        name: :auto_dismiss_option,
        mt: 1,
        data: {
          action: "change:dependabot-alert-rule-form#selectedRuleOptionDidChange",
          target: "dependabot-alert-rule-form.ruleOptions"
        }
      ) do |radio_group|
        radio_group.radio_button(
          value: "until_patch",
          label: "Until patch is available",
          checked: until_patch_selected?,
        )

        radio_group.radio_button(
          value: "indefinitely",
          label: "Indefinitely",
          checked: dismiss_indefinitely_selected?,
        )
      end
    end

    def initialize(rule: nil)
      @rule = rule
    end

    def until_patch_selected?
      # Default to auto-dismiss until patch when creating a new rule
      return true if @rule.nil?

      @rule.dismiss_until_patch?
    end

    def dismiss_indefinitely_selected?
      return false if @rule.nil?

      @rule.dismiss_indefinitely?
    end
  end
end
