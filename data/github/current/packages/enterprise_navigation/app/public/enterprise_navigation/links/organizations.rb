# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module Organizations
      extend T::Helpers
      include GitHub::Memoizer
      include UrlHelpers
      include EnterpriseNavigation::Links::SharedDependency

      sig { returns T::Array[EnterpriseNavigation::Group] }
      memoize def organizations_menu_groups
        [EnterpriseNavigation::Group.new(links: organizations_menu_items)]
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def organizations_menu_items
        menu_items = []

        menu_items << overview_menu_item

        if business_owner?
          menu_items << custom_properties_menu_item unless basic_account?
        end

        menu_items
      end

      sig { returns EnterpriseNavigation::Link }
      def overview_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Overview",
          link_path: enterprise_organizations_path(business),
          highlight: %i(
            business_organizations
            business_member_organizations
            business_pending_organizations
            business_unowned_organizations
            business_invite_organizations
            business_new_organizations
          ),
          icon: :home
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def custom_properties_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Custom Properties",
          link_path: business_organization_custom_properties_settings_enterprise_path(business),
          highlight: %i(
            business_organization_custom_properties_settings
          ),
          icon: :note,
          label: EnterpriseNavigation::Label::PREVIEW,
        )
      end

    end
  end
end
