# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module Compliance
      extend T::Helpers
      include GitHub::Memoizer
      include UrlHelpers
      include EnterpriseNavigation::Links::SharedDependency
      include ComplianceReportHelper

      sig { returns T::Array[EnterpriseNavigation::Group] }
      memoize def compliance_menu_groups
        groups = []
        groups << EnterpriseNavigation::Group.new(
          links: compliance_menu_items
        )
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def compliance_menu_items
        menu_item = []
        menu_item << compliance_resources_menu_item if compliance_menu_item_available?
        menu_item
      end

      sig { returns EnterpriseNavigation::Link }
      def compliance_resources_menu_item
        EnterpriseNavigation::Link.new(

            link_name: "Resources",
            link_path: settings_compliance_enterprise_path(business),
            highlight: %i(
              business_compliance_settings
            ),
            icon: :globe
        )
      end

      sig { returns(T::Boolean) }
      def compliance_menu_item_available?
        GitHub.multi_tenant_enterprise? || compliance_reports_available_for_account?(@business)
      end
    end
  end
end
