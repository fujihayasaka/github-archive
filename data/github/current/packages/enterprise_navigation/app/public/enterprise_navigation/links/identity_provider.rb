# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module IdentityProvider
      extend T::Helpers
      include GitHub::Memoizer
      include UrlHelpers
      include EnterpriseNavigation::Links::SharedDependency

      sig { returns T::Array[EnterpriseNavigation::Group] }
      memoize def identity_provider_groups
        groups = []
        groups << EnterpriseNavigation::Group.new(
          links: identity_provider_menu_items
        )
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def identity_provider_menu_items
        menu_items = []
        menu_items << sso_configuration_menu_item if include_sso_configuration_menu_item?
        menu_items << external_groups_menu_item if business_owner?
        menu_items
      end

      sig { returns EnterpriseNavigation::Link }
      def external_groups_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Groups",
          link_path: external_groups_enterprise_path(business),
          highlight: %i(
            external_groups
            linked_members
            linked_teams
          ),
          icon: :people
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def sso_configuration_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Single sign-on configuration",
          link_path: enterprise_single_sign_on_configuration_path(business),
          highlight: %i(
            single_sign_on_configuration
            edit_saml_configuration
            saml_to_oidc_migration
          ),
          icon: :"id-badge"
        )
      end

      private

      sig { returns T::Boolean }
      def include_sso_configuration_menu_item?
        return false unless @business&.enterprise_managed_user_enabled?
        # Open SCIM is not supported in OIDC so we only need to check if the user can read SSO
        return @business.actor_can_read_sso?(@user) if @business.oidc_enabled?
        @business.actor_can_read_sso_or_scim?(@user)
      end
    end
  end
end
