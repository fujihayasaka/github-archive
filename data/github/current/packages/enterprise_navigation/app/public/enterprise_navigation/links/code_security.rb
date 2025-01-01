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
        [overview_and_risk_group, enablement_and_metrics_group, alerts_and_scanning_group, dismissal_requests_group]
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def code_security_menu_items
        code_security_groups.flat_map(&:links)
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def overview_and_risk_group
        EnterpriseNavigation::Group.new(
          type: EnterpriseNavigation::GroupType::DIVIDER,
          links: [
            code_security_overview_menu_item,
            code_security_risk_menu_item,
            code_security_coverage_menu_item
          ]
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def enablement_and_metrics_group
        menu_items = []
        menu_items << code_security_enablement_trends_menu_item
        menu_items << code_security_metrics_code_scanning_menu_item if show_code_security_alerts_code_scanning_menu_item?
        menu_items << code_security_metrics_secret_scanning_menu_item if SecretScanning::Features::Business::TokenScanning.new(T.must(business)).feature_available?
        EnterpriseNavigation::Group.new(
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Group }
      memoize def alerts_and_scanning_group
        menu_items = []
        menu_items << code_security_alerts_dependabot_menu_item if ::SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
        menu_items << code_security_alerts_code_scanning_menu_item if show_code_security_alerts_code_scanning_menu_item?
        menu_items << code_security_alerts_secret_scanning_menu_item if SecretScanning::Features::Business::TokenScanning.new(T.must(business)).feature_available?
        EnterpriseNavigation::Group.new(
          links: menu_items
        )
      end

      sig { returns EnterpriseNavigation::Group }
      def dismissal_requests_group
        menu_items = []
        if SecretScanning::Features::Business::DelegatedClosures.new(T.must(business)).feature_available?
          menu_items << code_security_dismissal_requests_secret_scanning_menu_item
        end
        menu_items << code_security_dismissal_requests_code_scanning_menu_item if show_code_security_dismissal_requests_code_scanning_menu_item?
        EnterpriseNavigation::Group.new(
          links: menu_items
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
      def code_security_enablement_trends_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Enablement trends",
          link_path: enterprise_security_center_metrics_enablement_path(business),
          highlight: %i(
            business_security_center_metrics_enablement
          ),
          icon: :meter
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_metrics_code_scanning_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "CodeQL pull request alerts",
          link_path: enterprise_security_center_metrics_codeql_path(business),
          highlight: %i(
            business_code_scanning_metrics
          ),
          icon: :graph
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_metrics_secret_scanning_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Secret scanning metrics",
          link_path: enterprise_security_center_metrics_secret_scanning_path(business),
          highlight: %i(
            business_secret_scanning_metrics
          ),
          icon: :graph
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_alerts_dependabot_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Dependabot alerts",
          link_path: security_center_alerts_dependabot_enterprise_path(business),
          highlight: %i(
            business_security_center_alerts_dependabot
          ),
          icon: :dependabot
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_alerts_code_scanning_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Code scanning alerts",
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
          link_name: "Secret scanning alerts",
          link_path: security_center_alerts_secret_scanning_enterprise_path(business),
          highlight: %i(
            business_security_center_alerts_secret_scanning
          ),
          icon: :key
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_dismissal_requests_secret_scanning_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Secret scanning dismissal requests",
          link_path: enterprise_security_center_dismissal_requests_secret_scanning_index_path(business),
          highlight: %i(
            business_security_center_dismissal_requests_secret_scanning
          ),
          icon: :key,
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def code_security_dismissal_requests_code_scanning_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Code scanning dismissal requests",
          link_path: enterprise_security_center_dismissal_requests_code_scanning_index_path(business),
          highlight: %i(
            business_security_center_dismissal_requests_code_scanning
          ),
          icon: :codescan,
          label: Label::PREVIEW
        )
      end
    end
  end
end
