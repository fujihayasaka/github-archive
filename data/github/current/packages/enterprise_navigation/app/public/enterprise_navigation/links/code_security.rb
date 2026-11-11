# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module CodeSecurity
      extend T::Helpers
      include GitHub::Memoizer
      include UrlHelpers
      include EnterpriseNavigation::Links::SharedDependency

      sig { returns T::Array[EnterpriseNavigation::Group] }
      memoize def code_security_groups
        return [] unless business_owner? || member_of_owned_org?
        groups = [overview_and_risk_group, enablement_and_metrics_group]
        groups << alerts_and_scanning_group
        groups << dismissal_requests_group
        groups << access_and_policies_group if FeatureFlag.vexi.enabled?("glc_ia_enterprise_security_sidebar", user, business, default: false)
        groups
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def code_security_menu_items
        code_security_groups.flat_map(&:flat_links)
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def overview_and_risk_group
        links = [
          code_security_overview_menu_item,
          code_security_risk_menu_item,
        ]
        pubmon_feature = SecretScanning::Features::Business::PublicMonitoring.new(T.must(business))
        links << code_security_public_monitoring_menu_item if (pubmon_feature.enabled? || pubmon_feature.settings_available?) && SecretScanning::AccessControl::PublicMonitoring.can_access?(T.must(business), T.must(user))
        links << code_security_coverage_menu_item
        EnterpriseNavigation::Group.new(
          type: EnterpriseNavigation::GroupType::DIVIDER,
          links: links
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def enablement_and_metrics_group
        menu_items = []
        menu_items << code_security_enablement_menu_item
        menu_items << code_security_metrics_code_scanning_menu_item if show_code_security_alerts_code_scanning_menu_item?
        menu_items << code_security_metrics_secret_scanning_menu_item if SecretScanning::Features::Business::TokenScanning.new(T.must(business)).feature_available?
        EnterpriseNavigation::Group.new(
          name: "Insights",
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def alerts_and_scanning_group
        menu_items = []
        if ::SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
          if show_dependabot_split_tabs?
            menu_items << dependabot_folding_group
          else
            menu_items << code_security_alerts_dependabot_menu_item
          end
        end
        menu_items << code_security_alerts_code_scanning_menu_item if show_code_security_alerts_code_scanning_menu_item?
        menu_items << code_security_alerts_secret_scanning_menu_item if SecretScanning::Features::Business::TokenScanning.new(T.must(business)).feature_available?
        EnterpriseNavigation::Group.new(
          name: "Findings",
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Group }
      def dismissal_requests_group
        menu_items = []
        menu_items << code_security_dismissal_requests_dependabot_menu_item if show_code_security_dismissal_requests_dependabot_menu_item?
        menu_items << code_security_dismissal_requests_code_scanning_menu_item if show_code_security_dismissal_requests_code_scanning_menu_item?
        if SecretScanning::Features::Business::DelegatedClosures.new(T.must(business)).feature_available?
          menu_items << code_security_dismissal_requests_secret_scanning_menu_item
        end
        if SecretScanning::Features::Business::DelegatedBypass.new(T.must(business)).enabled_for_security_configuration?
          menu_items << secret_scanning_delegated_bypass_menu_item
        end
        menu_items << license_compliance_dismissal_requests_dependabot_menu_item if show_license_compliance_bypass_requests_dependency_graph_menu_item?
        EnterpriseNavigation::Group.new(
          name: "Dismissal requests",
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def access_and_policies_group
        EnterpriseNavigation::Group.new(
          name: "Access and policies",
          type: EnterpriseNavigation::GroupType::DIVIDER,
          links: [
            selected_organizations_access_menu_item,
            configurations_menu_item
          ]
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_overview_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Overview",
          link_path: enterprise_security_center_overview_dashboard_path(business),
          highlight: %i(
            business_security_center_overview
          ),
          icon: :home
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_risk_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Risk",
          link_path: security_center_risk_enterprise_path(business),
          highlight: %i(
            business_security_center_risk
          ),
          icon: :shield
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_coverage_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Coverage",
          link_path: security_center_coverage_enterprise_path(business),
          highlight: %i(
            business_security_center_coverage
          ),
          icon: :meter
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_enablement_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Enablement",
          link_path: enterprise_security_center_metrics_enablement_path(business),
          highlight: %i(
            business_security_center_metrics_enablement
          ),
          icon: :graph
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_metrics_code_scanning_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "CodeQL pull requests",
          link_path: enterprise_security_center_metrics_codeql_path(business),
          highlight: %i(
            business_code_scanning_metrics
          ),
          icon: :codescan
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_metrics_secret_scanning_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Secret scanning",
          link_path: enterprise_security_center_metrics_secret_scanning_path(business),
          highlight: %i(
            business_secret_scanning_metrics
          ),
          icon: :key
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_alerts_dependabot_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Dependabot",
          link_path: security_center_alerts_dependabot_enterprise_path(business),
          highlight: %i(
            business_security_center_alerts_dependabot
          ),
          icon: :dependabot
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def dependabot_folding_group
        EnterpriseNavigation::Group.new(
          type: EnterpriseNavigation::GroupType::FOLDING,
          name: "Dependabot",
          icon: :dependabot,
          links: [
            code_security_alerts_dependabot_malware_menu_item,
            code_security_alerts_dependabot_vulnerabilities_menu_item
          ]
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_alerts_dependabot_malware_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Malware",
          link_path: security_center_alerts_dependabot_malware_enterprise_path(business),
          highlight: %i(
            business_security_center_alerts_dependabot_malware
          )
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_alerts_dependabot_vulnerabilities_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Vulnerabilities",
          link_path: security_center_alerts_dependabot_enterprise_path(business),
          highlight: %i(
            business_security_center_alerts_dependabot_vulnerabilities
          )
        )
      end

      sig { returns T::Boolean }
      memoize def show_dependabot_split_tabs?
        ::SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_alerts_code_scanning_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Code scanning",
          link_path: security_center_alerts_code_scanning_enterprise_path(business),
          highlight: %i(
            business_security_center_alerts_code_scanning
          ),
          icon: :codescan
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_alerts_secret_scanning_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Secret scanning",
          link_path: security_center_alerts_secret_scanning_enterprise_path(business),
          highlight: %i(
            business_security_center_alerts_secret_scanning
          ),
          icon: :key
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_public_monitoring_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Public monitoring",
          link_path: enterprise_security_center_public_monitoring_index_path(business),
          highlight: %i(
            business_security_center_public_monitoring
          ),
          icon: :key
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_dismissal_requests_secret_scanning_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Secret scanning",
          link_path: enterprise_security_center_dismissal_requests_secret_scanning_index_path(business),
          highlight: %i(
            business_security_center_dismissal_requests_secret_scanning
          ),
          icon: :key,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def license_compliance_dismissal_requests_dependabot_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Licenses",
          link_path: enterprise_security_center_bypass_requests_license_compliance_index_path(business, request_status: "open"),
          highlight: %i(
            business_security_center_bypass_requests_license_compliance
          ),
          icon: :law,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def secret_scanning_delegated_bypass_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Push protection bypass",
          link_path: enterprise_security_center_bypass_requests_secret_scanning_index_path(business),
          highlight: %i(
            business_security_center_bypass_requests_secret_scanning
          ),
          icon: :key,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_dismissal_requests_code_scanning_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Code scanning",
          link_path: enterprise_security_center_dismissal_requests_code_scanning_index_path(business),
          highlight: %i(
            business_security_center_dismissal_requests_code_scanning
          ),
          icon: :codescan,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_dismissal_requests_dependabot_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Dependabot",
          link_path: enterprise_security_center_dismissal_requests_dependabot_index_path(business),
          highlight: %i(
            business_security_center_dismissal_requests_dependabot
          ),
          icon: :dependabot,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def selected_organizations_access_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Selected organizations access",
          link_path: settings_security_analysis_policies_enterprise_path(@business),
          icon: :shield,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def configurations_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Configurations",
          link_path: settings_security_analysis_enterprise_path(business),
          icon: :"shield-lock"
        )
      end
    end
  end
end
