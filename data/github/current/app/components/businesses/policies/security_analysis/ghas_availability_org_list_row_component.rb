# typed: true
# frozen_string_literal: true

module Businesses::Policies::SecurityAnalysis
  class GhasAvailabilityOrgListRowComponent < ApplicationComponent
    include BasePolicy

    TEST_SELECTOR = "businesses-policies-security-analysis-ghas-availability-org-list-row"

    attr_reader :organization

    def initialize(organization:, ghas_available:)
      @organization = organization
      @ghas_available = ghas_available
    end

    def ghas_available?
      !!@ghas_available
    end

    def avatar_src
      PrimaryAvatar.url_for(organization.primary_avatar_path, entity: organization)
    end

    def availability_menu_items
      [
        GitHub::Menu::ButtonComponent.new(
          checked: ghas_available?,
          text: "Available",
          name: "org_ghas_availability",
          value: "available",
          description: "GitHub Advanced Security is available for all repositories within this organization.",
          replace_text: "Available",
          type: "submit",
        ),
        GitHub::Menu::ButtonComponent.new(
          checked: !ghas_available?,
          text: "Not available",
          name: "org_ghas_availability",
          value: "not_available",
          description: "GitHub Advanced Security won’t be available for repositories within this organization.",
          replace_text: "Not available",
          type: "submit",
        ),
      ]
    end

    private

    sig { override.returns(String) }
    def policy_name
      "org_ghas_availability"
    end

    sig { override.returns(T::Array[PolicyItem]) }
    def policy_options
      [
        PolicyItem.new(
          label: "Available",
          description: "GitHub Advanced Security is available for all repositories within this organization.",
          active: ghas_available?,
          value: "available"
        ),
        PolicyItem.new(
          label: "Not available",
          description: "GitHub Advanced Security won’t be available for repositories within this organization.",
          active: !ghas_available?,
          value: "not_available"
        )
      ]
    end

    sig { returns(String) }
    def submit_path
      settings_security_analysis_policies_update_org_ghas_availability_enterprise_path(org_ids: [organization.id])
    end
  end
end
