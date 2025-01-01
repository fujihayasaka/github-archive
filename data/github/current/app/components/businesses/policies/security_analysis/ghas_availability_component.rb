# typed: true
# frozen_string_literal: true

module Businesses::Policies::SecurityAnalysis
  class GhasAvailabilityComponent < ApplicationComponent
    include BasePolicy
    include SecretScanning::Features::FeatureFlagHelper

    sig { returns Business }
    attr_reader :business

    TEST_SELECTOR = "businesses-policies-security-analysis-ghas-availability"

    sig { params(business: Business).void }
    def initialize(business:)
      @business = business
    end

    def menu_items
      [
        GitHub::Menu::ButtonComponent.new(
          text: "Allow for all organizations",
          description: "All organizations may enable GitHub Advanced Security for their repositories.",
          replace_text: "Allow for all organizations",
          checked: business.all_members_can_enable_advanced_security?,
          name: "ghas_availability",
          value: "all_orgs",
          type: "submit",
        ),
        GitHub::Menu::ButtonComponent.new(
          text: "Allow for selected organizations",
          description: "Only selected organizations may enable GitHub Advanced Security for their repositories.",
          replace_text: "Allow for selected organizations",
          checked: business.selected_members_can_enable_advanced_security?,
          name: "ghas_availability",
          value: "selected_orgs",
          type: "submit",
        ),
        GitHub::Menu::ButtonComponent.new(
          text: "Not available",
          description: "No organization may enable GitHub Advanced Security for their repositories.",
          replace_text: "Not available",
          checked: business.no_members_can_enable_advanced_security?,
          name: "ghas_availability",
          value: "not_available",
          type: "submit",
        ),
      ]
    end

    private

    sig { override.returns(String) }
    def policy_name
      "ghas_availability"
    end

    sig { override.returns(T::Array[PolicyItem]) }
    def policy_options
      [
        PolicyItem.new(
          label: "Allow for all organizations",
          description: "All organizations may enable GitHub Advanced Security for their repositories.",
          active: business.all_members_can_enable_advanced_security?,
          value: "all_orgs",
        ),
        PolicyItem.new(
          label: "Allow for selected organizations",
          description: "Only selected organizations may enable GitHub Advanced Security for their repositories.",
          active: business.selected_members_can_enable_advanced_security?,
          value: "selected_orgs",
        ),
        PolicyItem.new(
          label: "Not available",
          description: "No organization may enable GitHub Advanced Security for their repositories.",
          active: business.no_members_can_enable_advanced_security?,
          value: "not_available",
        )
      ]
    end
  end
end
