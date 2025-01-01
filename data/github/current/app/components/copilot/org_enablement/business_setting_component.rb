# typed: strict
# frozen_string_literal: true

module Copilot
  module OrgEnablement
    class BusinessSettingComponent < ApplicationComponent
      renders_one :form_content

      sig { params(copilot_business: Copilot::Business).void }
      def initialize(copilot_business)
        @copilot_business = T.let(copilot_business, Copilot::Business)
      end

      sig { returns(ActiveRecord::Relation) }
      memoize def organizations
        @copilot_business.business_object.organizations
      end

      # Unfortunately, this can't be memoized. If an admin changes plans for one or more businesses, and then
      # triggers the disable for all modal, the license plans won't reflect the change until the page is reloaded.
      sig { returns(Integer) }
      def total_cost
        @copilot_business.total_cost
      end

      sig { returns(Integer) }
      memoize def org_count
        @copilot_business.copilot_enabled_organizations_count
      end

      sig { returns(Integer) }
      memoize def member_count
        @copilot_business.copilot_enabled_members_count
      end

      sig { returns(String) }
      memoize def org_count_text
        "#{org_count} #{"organization".pluralize(org_count)}"
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      memoize def menu_items
        [
          {
            label: "Disabled",
            value: "disabled",
            name: "copilot_enabled",
            description: "Disable GitHub Copilot access for my organizations in this enterprise.",
            type: "button",
            data: {
              "show-dialog-id": "copilot-business-settings-access-component"
            }
          },
          {
            label: "Allow for: All organizations",
            value: "all_organizations",
            name: "copilot_enabled",
            description: "Allow access to GitHub Copilot for all organizations, including any created in the future.",
            type: "submit",
          },
          {
            label: "Allow for: Specific organizations",
            value: "selected_organizations",
            name: "copilot_enabled",
            description: "Only specifically-selected organizations may use GitHub Copilot.",
            type: "submit",
          }
        ]
      end

      sig { returns(String) }
      memoize def current_label
        return "Allow for all organizations" if @copilot_business.copilot_enabled_for_all_organizations?
        return "Allow for specific organizations" if @copilot_business.copilot_enabled_for_selected_organizations?
        "Disabled"
      end

      sig { returns(String) }
      memoize def billing_overview_path
        business = @copilot_business.business_object
        enterprise_billing_path(business)
      end
    end
  end
end
