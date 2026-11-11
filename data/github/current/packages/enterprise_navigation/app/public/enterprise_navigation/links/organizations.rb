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
        groups = [EnterpriseNavigation::Group.new(links: organizations_menu_items)]
        if FeatureFlag.vexi.enabled?("glc_ia_enterprise_organizations_sidebar", user, business, default: false)
          groups << organizations_repository_policies_group
        end
        groups
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def organizations_menu_items
        menu_items = []

        menu_items << overview_menu_item

        if business_owner?
          menu_items << custom_properties_menu_item unless basic_account?
        end

        if FeatureFlag.vexi.enabled?("glc_ia_enterprise_organizations_sidebar", user, business, default: false)
          menu_items << organizations_member_privileges_menu_item if business_owner? && !basic_account?
          menu_items << organizations_projects_menu_item if business_owner?
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
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def organizations_repository_policies_group
        menu_items = []
        menu_items << organizations_repository_policies_menu_item if business_owner? && !basic_account? && T.must(business).member_privilege_rulesets_enabled?
        menu_items << organizations_code_rules_menu_item if business_owner? && !basic_account?
        menu_items << organizations_code_rule_insights_menu_item if business_owner? && !basic_account?
        menu_items << organizations_code_rule_bypass_requests_menu_item if business_owner? && !basic_account?
        menu_items << organizations_repo_custom_properties_menu_item if business_owner? && !basic_account?

        EnterpriseNavigation::Group.new(
          name: "Repository policies",
          type: EnterpriseNavigation::GroupType::FLAT,
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def organizations_member_privileges_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Member privileges",
          link_path: settings_member_privileges_enterprise_path(business),
          highlight: :business_member_privileges_settings,
          icon: :shield,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def organizations_projects_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Projects",
          link_path: settings_projects_enterprise_path(business),
          highlight: :business_projects_settings,
          icon: :project,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def organizations_repository_policies_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Custom policies",
          link_path: settings_repository_policies_enterprise_path(business),
          highlight: :business_repository_policies,
          icon: nil,
          label: EnterpriseNavigation::Label::PREVIEW,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def organizations_repo_custom_properties_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Repo custom properties",
          link_path: settings_custom_properties_enterprise_path(business),
          highlight: :business_custom_properties_settings,
          icon: nil,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def organizations_code_rules_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Rulesets",
          link_path: settings_code_rules_enterprise_path(business),
          highlight: :business_code_rulesets,
          icon: nil,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def organizations_code_rule_insights_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Ruleset insights",
          link_path: settings_code_rule_insights_enterprise_path(business),
          highlight: :business_code_rule_insights,
          icon: nil,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def organizations_code_rule_bypass_requests_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Bypass requests",
          link_path: settings_code_rules_bypass_requests_enterprise_path(business),
          highlight: :business_code_rule_bypass_requests,
          icon: nil,
        )
      end
    end
  end
end
