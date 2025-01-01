# typed: true
# frozen_string_literal: true

module Businesses::Policies::SecurityAnalysis
  class DependabotAlertsEnablementComponent < ApplicationComponent
    include BasePolicy

    attr_reader :business, :system_arguments

    TEST_SELECTOR = "businesses-policies-security-analysis-dependabot-alerts-enablement"

    def initialize(business:, **system_arguments)
      @business = business
      @system_arguments = system_arguments
    end

    def menu_items
      [
        GitHub::Menu::ButtonComponent.new(
          text: "Allowed",
          description: "Repository admins can enable or disable Dependabot alerts.",
          replace_text: "Allowed",
          checked: business.repo_admins_can_modify_dependabot_alerts_enablement?,
          name: "all_orgs_repo_admins",
          value: "allowed",
          type: "submit",
        ),
        GitHub::Menu::ButtonComponent.new(
          text: "Not allowed",
          description: "Repository admins cannot enable or disable Dependabot alerts.",
          replace_text: "Not allowed",
          checked: !business.repo_admins_can_modify_dependabot_alerts_enablement?,
          name: "all_orgs_repo_admins",
          value: "not_allowed",
          type: "submit",
        ),
      ]
    end

    private

    sig { override.returns(String) }
    def policy_name
      "all_orgs_repo_admins"
    end

    sig do
      override
      .returns(T::Array[Businesses::Policies::SecurityAnalysis::BasePolicy::PolicyItem])
    end
    def policy_options
      [
        PolicyItem.new(
          label: "Allowed",
          description: "Repository admins can enable or disable Dependabot alerts.",
          active: business.repo_admins_can_modify_dependabot_alerts_enablement?,
          value: "allowed",
        ),
        PolicyItem.new(
          label: "Not allowed",
          description: "Repository admins cannot enable or disable Dependabot alerts.",
          active: !business.repo_admins_can_modify_dependabot_alerts_enablement?,
          value: "not_allowed",
        )
      ]
    end
  end
end
