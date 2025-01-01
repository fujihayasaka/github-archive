# typed: true
# frozen_string_literal: true

module Businesses::Policies::SecurityAnalysis
  class GhasEnablementComponent < ApplicationComponent
    include BasePolicy
    extend T::Sig

    attr_reader :business, :system_arguments

    TEST_SELECTOR = "businesses-policies-security-analysis-ghas-enablement"

    def initialize(business:, **system_arguments)
      @business = business
      @system_arguments = system_arguments
    end

    def menu_items
      [
        GitHub::Menu::ButtonComponent.new(
          text: "Allowed",
          description: "Repository admins can enable or disable GitHub Advanced Security.",
          replace_text: "Allowed",
          checked: business.repo_admins_can_modify_advanced_security_enablement?,
          name: "all_repo_admins",
          value: "allowed",
          type: "submit",
        ),
        GitHub::Menu::ButtonComponent.new(
          text: "Not allowed",
          description: "Repository admins cannot enable or disable GitHub Advanced Security.",
          replace_text: "Not allowed",
          checked: !business.repo_admins_can_modify_advanced_security_enablement?,
          name: "all_repo_admins",
          value: "not_allowed",
          type: "submit",
        ),
      ]
    end

    def repo_scope_text
      base = "By allowing this policy, repository admins can choose to enable or disable Github Advanced Security"
      include_emus = AdvancedSecurity::Features::Business::AdvancedSecurity.new(business).feature_available_for_user_repositories?
      if include_emus
        "#{base} on organization-owned and user-owned repositories"
      else
        "#{base} on organization-owned repositories"
      end
    end

    private

    sig { override.returns(String) }
    def policy_name
      "all_repo_admins"
    end

    sig { override.returns(T::Array[PolicyItem]) }
    def policy_options
      [
        PolicyItem.new(
          label: "Allowed",
          description: "Repository admins can enable or disable GitHub Advanced Security.",
          active: business.repo_admins_can_modify_advanced_security_enablement?,
          value: "allowed",
        ),
        PolicyItem.new(
          label: "Not allowed",
          description: "Repository admins cannot enable or disable GitHub Advanced Security.",
          active: !business.repo_admins_can_modify_advanced_security_enablement?,
          value: "not_allowed",
        )
      ]
    end
  end
end
