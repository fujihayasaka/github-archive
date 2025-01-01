# typed: true
# frozen_string_literal: true

module Businesses::Policies::SecurityAnalysis
  class GhasSKUAvailabilityOrgListRowComponent < ApplicationComponent
    include BasePolicy

    TEST_SELECTOR = "businesses-policies-security-analysis-ghas-sku-availability-org-list-row"

    attr_reader :organization

    def initialize(organization:, policy:)
      @organization = organization
      @policy = policy
    end

    def avatar_src
      PrimaryAvatar.url_for(organization.primary_avatar_path, entity: organization)
    end

    private

    sig { override.returns(String) }
    def policy_name
      "org_ghas_sku_availability"
    end

    sig { override.returns(T::Array[PolicyItem]) }
    def policy_options
      [
        PolicyItem.new(
          label: "All plans",
          description: "Organization can enable all Advanced Security features and consume Secret Protection and Code Security licenses.",
          active: @policy == Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL,
          value: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL,
        ),
        PolicyItem.new(
          label: "Secret Protection only",
          description: "Organization can only enable Secret Protection features and consume Secret Protection licenses.",
          active: @policy == Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_SECRET_PROTECTION_ONLY,
          value: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_SECRET_PROTECTION_ONLY,
        ),
        PolicyItem.new(
          label: "Code Security only",
          description: "Organization can only enable Code Security features and consume Code Security licenses.",
          active: @policy == Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_CODE_SECURITY_ONLY,
          value: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_CODE_SECURITY_ONLY,
        ),
        PolicyItem.new(
          label: render(Primer::Beta::Text.new(tag: :span, color: :danger).with_content("Not available")),
          description: "Organization will not be able to enable any Advanced Security features.",
          active: @policy == Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_NONE,
          value: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_NONE,
        ),
      ]
    end

    sig { returns(String) }
    def submit_path
      settings_security_analysis_policies_update_org_ghas_sku_availability_enterprise_path(org_ids: [organization.id])
    end
  end
end
