# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CodingAgentPolicySelectOrganizationsComponent < ApplicationComponent
      include GitHub::Memoizer

      sig { params(business: ::Business, can_write: T::Boolean).void }
      def initialize(business:, can_write: false)
        @business = business
        @copilot_business = T.let(Copilot::Business.new(business), Copilot::Business)
        @can_write = can_write
      end

      sig { returns(T::Boolean) }
      def render?
        !!logged_in?
      end

      sig { returns(Integer) }
      memoize def enabled_count
        all_organizations.count { |row| row[:enabled] }
      end

      private

      # All copilot-enabled orgs in the enterprise (for the dialog's searchable list with checkboxes)
      sig { returns(T::Array[{ organization: ::Organization, enabled: T::Boolean }]) }
      memoize def all_organizations
        coding_agent_state_by_org_id = Copilot::Policies::CodingAgent.coding_agent_state_by_org_id(copilot_business: @copilot_business)
        return [] if coding_agent_state_by_org_id.empty?

        orgs = ::Organization.where(id: coding_agent_state_by_org_id.keys).to_a

        orgs.map do |org|
          {
            organization: org,
            enabled: coding_agent_state_by_org_id[org.id] == "enabled",
          }
        end.sort_by { |row| [row[:enabled] ? 1 : 0, (row[:organization].display_login || "").downcase] }
      end

      sig { returns(T::Array[CustomPropertiesCore::IPropertyDefinition]) }
      memoize def custom_property_definitions
        Orgs.domain.custom_properties.get_definitions(@business)
      end

      sig { params(definition: CustomPropertiesCore::IPropertyDefinition).returns(T::Array[String]) }
      def property_value_options(definition)
        if definition.true_false_value_type?
          %w(true false)
        else
          definition.allowed_values || []
        end
      end

      sig { params(definition: CustomPropertiesCore::IPropertyDefinition).returns(T::Boolean) }
      def selectable_property?(definition)
        %w[single_select multi_select true_false].include?(definition.value_type)
      end

      sig { returns(String) }
      def submit_path
        update_coding_agent_orgs_enablement_enterprise_ai_controls_enterprise_path(@business)
      end

      sig { returns(String) }
      def search_orgs_by_custom_property_path
        search_orgs_by_custom_property_enterprise_ai_controls_enterprise_path(@business)
      end
    end
  end
end
