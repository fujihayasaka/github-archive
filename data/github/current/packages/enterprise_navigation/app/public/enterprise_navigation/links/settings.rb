# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module Settings
      extend T::Helpers
      include GitHub::Memoizer
      include UrlHelpers
      include EnterpriseNavigation::Links::SharedDependency

      sig { returns T::Array[EnterpriseNavigation::Group] }
      memoize def settings_menu_groups
        groups = []
        groups << EnterpriseNavigation::Group.new(
          links: settings_menu_items
        )
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def settings_menu_items
        menu_items = []

        if business_owner?
          menu_items << profile_menu_item

          if GitHub.billing_enabled?
            if !GitHub.proxima_billing_enabled?
              menu_items << billing_menu_item unless @business&.disable_legacy_billing_page?
            end
            menu_items << enterprise_licensing_menu_item unless billing_menu_accessible?
          end

          # Show Packages only when Packages v2 enabled and atleast one docker image exists
          menu_items << packages_menu_item if GitHub.subdomain_isolation? && GitHub.registry_v2_enabled_for_enterprise? && Registry::Package.any_package_exists("docker").count > 0
          menu_items << license_menu_item if GitHub.licensed_mode?
          menu_items << security_menu_item
          menu_items << code_security_settings_menu_item if show_code_security_settings_menu_item?
          menu_items << verified_domains_menu_item if GitHub.verified_domains_enabled?
          menu_items << audit_log_menu_item
          menu_items << retired_namespaces_menu_item if GitHub.multi_tenant_enterprise?
          menu_items << hooks_menu_item if !basic_account?
          menu_items << virtual_networks_menu_item if !GitHub.single_business_environment? && @business&.feature_enabled?(:codespaces_vnet_settings)
          menu_items << network_configurations_menu_item if network_configurations_sub_menu_item_available?
          menu_items << github_insights_menu_item if GitHub.insights_available?
          menu_items << gh_apps_menu_item

          # add the repos-owned "announcement" item only on dotcom
          menu_items << announcement_banner_menu_item if !GitHub.single_business_environment?

          unless GitHub.single_business_environment?
            menu_items << support_menu_item
          end

          if GitHub.single_business_environment?
            menu_items << custom_messages_menu_item
            menu_items << site_admin_menu_item
          end

          menu_items << linked_accounts_menu_item if show_linked_accounts_sub_menu_item?
        elsif business_billing_manager?
          if GitHub.billing_enabled?
            menu_items << billing_menu_item unless @business&.disable_legacy_billing_page?
            menu_items << enterprise_licensing_menu_item unless billing_menu_accessible?
          end
          menu_items << security_menu_item if !@business&.enterprise_managed_user_enabled? && permission_grants[:read_enterprise_sso]
          if @business&.feature_enabled?(:use_biz_audit_log_fgp_ui)
            menu_items.concat(settings_menu_items_from_fgp_access)
          end
        else
          menu_items << security_menu_item if !@business&.enterprise_managed_user_enabled? && permission_grants[:read_enterprise_sso]

          menu_items << code_security_settings_menu_item if show_code_security_settings_menu_item?
          if @business&.feature_enabled?(:use_biz_audit_log_fgp_ui)
            menu_items.concat(settings_menu_items_from_fgp_access)
          end
        end

        menu_items
      end

      sig { returns EnterpriseNavigation::Link }
      def profile_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Profile",
          link_path: settings_profile_enterprise_path(business),
          highlight: %i(
            business_profile_settings
          ),
          icon: :globe
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def billing_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Billing",
          link_path: settings_billing_enterprise_path(business),
          highlight: %i(
            business_billing_settings,
          ),
          icon: :"credit-card"
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def packages_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Packages",
          link_path: settings_packages_migration_enterprise_path(business),
          highlight: %i(
            business_packages_settings
            ),
            icon: :package
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def license_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "License",
          link_path: settings_license_enterprise_path(business),
          highlight: %i(
            business_license_settings
            ),
            icon: :law
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def security_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Authentication security",
          link_path: settings_security_enterprise_path(business),
          highlight: %i(
            business_security_settings
            ssh_certificate_authorities
            ip_allowlist_entries
          ),
          icon: :"shield-lock"
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_settings_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Advanced Security",
          link_path: settings_security_analysis_enterprise_path(business),
          highlight: %i(
            business_security_analysis
            business_security_analysis_settings
          ),
          icon: :codescan
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def verified_domains_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Verified & approved domains",
          link_path: settings_enterprise_domains_enterprise_path(business),
          highlight: %i(
            business_domains_settings
            ),
            icon: :verified
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def audit_log_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Audit log",
          link_path: settings_audit_log_enterprise_path(business),
          highlight: %i(
            business_audit_log_settings
            business_audit_log_streams_settings
            business_audit_log_event_settings_settings
            business_audit_log_event_settings_export_logs
          ),
          icon: :log
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def retired_namespaces_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Retired namespaces",
          link_path: settings_retired_namespaces_enterprise_path(business),
          highlight: %i(
            retired_namespaces_settings
            ),
            icon: :"circle-slash"
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def hooks_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Hooks",
          link_path: hooks_enterprise_path(business),
          highlight: %i(
            hooks
          ),
          icon: :webhook
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def network_configurations_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Hosted compute networking",
          link_path: settings_network_configurations_path(business),
          highlight: %i(
            network_configurations
            ),
          icon: :cpu
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def github_insights_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "GitHub Insights",
          link_path: settings_enterprise_insights_path(business),
          highlight: %i(
            business_insights_settings
          ),
          icon: :graph
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def gh_apps_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "GitHub Apps",
          link_path: gh_apps_sub_menu_item_link_path,
          highlight: %i[
            integrations
            integration_installations
          ],
          icon: :apps
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def announcement_banner_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Announcement",
          link_path: edit_announcement_enterprise_path(business),
          highlight: %i(
            business_messages_settings
          ),
          icon: :megaphone
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def support_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Support",
          link_path: enterprise_support_index_path(business),
          highlight: %i(
            business_support_settings
          ),
          icon: :question
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def custom_messages_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Messages",
          link_path: custom_messages_enterprise_path(business),
          highlight: %i(
            business_custom_messages
          ),
          icon: :inbox
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def site_admin_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Site admin",
          link_path: stafftools_path,
          icon: :"passkey-fill"
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def linked_accounts_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Linked accounts",
          link_path: settings_linked_accounts_enterprise_path(business),
          highlight: %i(
            linked_accounts_settings
          ),
          icon: :people
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def enterprise_licensing_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Enterprise licensing",
          link_path: enterprise_licensing_path(business),
          highlight: %i(
            enterprise_licensing
          ),
          icon: :law
        )
      end

      sig { returns(T.nilable(EnterpriseNavigation::Link)) }
      def virtual_networks_menu_item
        if @business&.feature_enabled?(:codespaces_vnet_settings)
          EnterpriseNavigation::Link.new(
            link_name: "Networking",
            link_path: settings_virtual_networks_path(business),
            highlight: %i(
              virtual_networks
            ),
            icon: :cloud
          )
        end
      end

      sig { returns(T::Array[EnterpriseNavigation::Link]) }
      memoize def settings_menu_items_from_fgp_access
        sub_items = []
        sub_items << audit_log_menu_item if permission_grants[:read_enterprise_audit_logs]

        sub_items
      end

      sig { returns(T::Boolean) }
      memoize def business_billing_manager?
        @business&.billing_manager?(user)
      end

      sig { returns(T::Boolean) }
      memoize def show_code_security_settings_menu_item?
        return false if basic_account?
        SecurityProduct::Permissions::BusinessAuthz.new(T.must(business), actor: user).can_view_code_security_settings?
      end

      sig { returns(T::Boolean) }
      memoize def network_configurations_sub_menu_item_available?
        return false if @business&.downgraded_to_free_plan?
        return false if GitHub.single_business_environment?
        true
      end

      sig { returns(T::Boolean) }
      memoize def show_linked_accounts_sub_menu_item?
        !!(@business&.enterprise_managed_user_enabled? && @business.feature_enabled?(:enterprise_linked_accounts))
      end

      sig { returns(T::Boolean) }
      memoize def billing_menu_accessible?
        return false if !GitHub.billing_enabled?
        return true if @business&.customer&.billed_via_billing_platform? && (
          business_owner? || business_org_owner? || business_billing_manager?)
        false
      end

      sig { returns(String) }
      memoize def gh_apps_sub_menu_item_link_path
        settings_apps_enterprise_path(business)
      end
    end
  end
end
