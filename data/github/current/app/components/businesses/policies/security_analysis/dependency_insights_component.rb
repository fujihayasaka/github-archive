# typed: true
# frozen_string_literal: true

module Businesses::Policies::SecurityAnalysis
  class DependencyInsightsComponent < ApplicationComponent
    include BasePolicy

    attr_reader :business

    TEST_SELECTOR = "businesses-policies-security-analysis-dependency-insights-management"

    def initialize(business:)
      @business = business
    end

    def menu_items
      [
        GitHub::Menu::ButtonComponent.new(
          text: "No policy",
          description: "Organizations choose whether to allow members to view dependency insights.",
          replace_text: "No policy",
          checked: business_value == "no_policy",
          name: "members_can_view_dependency_insights",
          value: "no_policy",
          type: "submit",
        ),
        GitHub::Menu::ButtonComponent.new(
          text: "Enabled",
          description: "Organizations always allow members to view dependency insights.",
          replace_text: "Enabled",
          checked:  business_value == "enabled",
          name: "members_can_view_dependency_insights",
          value: "enabled",
          type: "submit",
        ),
        GitHub::Menu::ButtonComponent.new(
          text: "Disabled",
          description: "Organizations never allow members to view dependency insights",
          replace_text: "Disabled",
          checked: business_value == "disabled",
          name: "members_can_view_dependency_insights",
          value: "disabled",
          type: "submit",
        ),
      ]
    end

    private

    sig { override.returns(String) }
    def policy_name
      "members_can_view_dependency_insights"
    end

    sig do
      override
      .returns(T::Array[Businesses::Policies::SecurityAnalysis::BasePolicy::PolicyItem])
    end
    def policy_options
      [
        PolicyItem.new(
          label: "No policy",
          description: "Organizations choose whether to allow members to view dependency insights.",
          active: business_value == "no_policy",
          value: "no_policy"
        ),
        PolicyItem.new(
          label: "Enabled",
          description: "Organizations always allow members to view dependency insights.",
          active:  business_value == "enabled",
          value: "enabled",
        ),
        PolicyItem.new(
          label: "Disabled",
          description: "Organizations never allow members to view dependency insights",
          active: business_value == "disabled",
          value: "disabled",
        )
      ]
    end

    sig { returns(String) }
    def business_value
      if !business.members_can_view_dependency_insights_policy?
        "no_policy"
      elsif business.members_can_view_dependency_insights?
        "enabled"
      else
        "disabled"
      end
    end
  end
end
