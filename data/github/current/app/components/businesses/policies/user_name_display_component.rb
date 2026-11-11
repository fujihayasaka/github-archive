# typed: true
# frozen_string_literal: true

module Businesses::Policies
  class UserNameDisplayComponent < ApplicationComponent
    attr_reader :business, :organization, :system_arguments

    TEST_SELECTOR = "businesses-policies-user-name-display"

    def initialize(business: nil, organization: nil, **system_arguments)
      @business = business
      @organization = organization
      @system_arguments = system_arguments
    end

    def render?
      (business || organization)&.eligible_for_user_name_display_configuration?
    end

    sig { returns(T::Boolean) }
    def organization_component?
      @organization.present?
    end

    sig { returns(String) }
    def policy_id
      "user_name_display"
    end

    sig { returns(String) }
    def policy_name
      "user_name_display[value]"
    end

    sig { returns(String) }
    def policy_field
      "user_name_display[policy]"
    end

    sig { returns(String) }
    def display_name
      "Enable profile name visibility"
    end

    PolicyItem = Struct.new(:label, :description, :active, :value, :policy_value)

    sig do
      returns(T::Array[PolicyItem])
    end
    def policy_options
      [
        PolicyItem.new(
          label: "Enable everywhere",
          description: "Profile names are visible with handles in all organizations. Cannot be disabled at the organization level.",
          active: business_value == Configurable::UserNameDisplayConfiguration::NAME_AND_HANDLE && business.user_name_display_configuration_final?,
          value: Configurable::UserNameDisplayConfiguration::NAME_AND_HANDLE,
          policy_value: "1"
        ),
        PolicyItem.new(
          label: "Disable everywhere",
          description: "Profile names are not visible with handles. Cannot be enabled at the organization layer.",
          active: business_value == Configurable::UserNameDisplayConfiguration::HANDLE && business.user_name_display_configuration_final?,
          value: Configurable::UserNameDisplayConfiguration::HANDLE,
          policy_value: "1"
        ),
        PolicyItem.new(
          label: "Let organizations decide",
          description: "Owners can choose whether profile names are visible in their organization.",
          active: !business.user_name_display_configuration_final?,
          value: "no_policy",
          policy_value: "0"
        )
      ]
    end

    sig { returns(String) }
    def selected_policy_text
      T.must(policy_options.find(&:active)).label
    end

    sig { returns(T::Boolean) }
    def policy_enabled?
      organization_component? && organization.user_name_display_configuration_policy? || false
    end

    sig { returns(T::Boolean) }
    def checked?
      org_value == Configurable::UserNameDisplayConfiguration::NAME_AND_HANDLE
    end

    private

    sig { returns(String) }
    def org_value
      organization.user_name_display_configuration_value
    end

    sig { returns(String) }
    def business_value
      if policy_enabled?
        "no_policy"
      else
        business.user_name_display_configuration_value
      end
    end
  end
end
