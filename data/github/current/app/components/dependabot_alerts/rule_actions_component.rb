# typed: strict
# frozen_string_literal: true

module DependabotAlerts
  class RuleActionsComponent < ApplicationComponent
    ACTION_NAMES_AND_DESCRIPTIONS = T.let({
      "alert_actions" => {
        "auto_dismiss" => {
          "until_patch" => {
            name: "Dismiss the alert until patch is available",
            description: "Auto-dismiss the alert. Reopen if the alert metadata changes, voiding the rule."
          },
          "indefinitely" => {
            name: "Dismiss the alert indefinitely",
            description: "Auto-dismiss the alert. Reopen if the alert metadata changes, voiding the rule."
          }
        },
      },
      "update_actions" => {
        "create_pr" => {
          "true" => {
            name: "Open a pull request to resolve the alert",
            description: "If possible, Dependabot will open a pull request with suggested changes to resolve the alert."
          },
          "false" => nil # Action is disabled, return nothing.
        }
      }
    }.freeze, T::Hash[T.untyped, T.untyped])

    sig { returns(VulnerabilityAlertRule) }
    attr_accessor :rule

    sig { returns(T::Hash[Symbol, Symbol]) }
    attr_accessor :border_box_args

    sig { params(rule: VulnerabilityAlertRule, border_box_args: T::Hash[Symbol, Symbol]).void }
    def initialize(rule:, border_box_args: {})
      @rule = rule
      @border_box_args = border_box_args
    end

    # Transform the rule actions into an Array containing the human readable title and description.
    #
    # e.g. {"alert_actions" => {"auto_dismiss" => "indefinitely"}} turns into
    #   [{ title: "Dismiss this alert indefinitely", description: "Auto-dismiss the alert..." }]
    #
    # Meant to be used with `.each` to iterate over active actions for front-end display.
    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    def action_names_and_descriptions
      rule.actions.without("version").map do |category, rules|
        rules.map do |k, v|
          ACTION_NAMES_AND_DESCRIPTIONS.dig(category, k, v.to_s)
        end.compact
      end.flatten
    end
  end
end
