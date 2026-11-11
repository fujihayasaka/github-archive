# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module Insights
      extend T::Helpers
      include GitHub::Memoizer
      include UrlHelpers
      include EnterpriseNavigation::Links::SharedDependency

      sig { returns T::Array[EnterpriseNavigation::Group] }
      memoize def insights_menu_groups
        groups = []
        groups << EnterpriseNavigation::Group.new(links: [copilot_impact_menu_item]) if show_copilot_impact_link?
        groups << EnterpriseNavigation::Group.new(links: copilot_insights_menu_items) if copilot_insights_menu_items.any?
        groups << EnterpriseNavigation::Group.new(links: actions_insights_menu_items) if actions_insights_menu_items.any?
        groups
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def insights_menu_items
        copilot_insights_menu_items + actions_insights_menu_items
      end

      private

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def copilot_insights_menu_items
        items = []
        items << copilot_insights_menu_item if permissions_object.copilot_insights_usage_feature_available?
        items << copilot_code_generation_insights_menu_item if permissions_object.copilot_insights_code_generation_feature_available?
        items
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def actions_insights_menu_items
        items = []
        items << insights_actions_usage_metrics_menu_item if actions_items_available?
        items << insights_actions_performance_metrics_menu_item if actions_items_available?
        items
      end

      sig { returns T::Boolean }
      memoize def show_copilot_impact_link?
        return false unless permissions_object.copilot_insights_usage_feature_available?
        FeatureFlag.vexi.enabled?("glc_copilot_metrics_v2", user, business, default: false)
      end

      sig { returns EnterpriseNavigation::Link }
      def copilot_impact_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Copilot impact",
          link_path: copilot_insights_impact_enterprise_insights_url(business, only_path: true),
          highlight: %i(
            copilot_impact
          ),
          icon: :copilot
        )
      end

      sig { returns(CopilotInsightsPermissions::PermissionCheck) }
      memoize def permissions_object
        CopilotInsightsPermissions::PermissionCheck.new(business: business, user: user)
      end

      sig { returns T::Boolean }
      memoize def actions_items_available?
        return false if basic_account?

        business&.actions_usage_metrics_enabled?(user) || false
      end

      sig { returns EnterpriseNavigation::Link }
      def copilot_insights_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Copilot usage",
          link_path: copilot_insights_usage_enterprise_insights_url(business, only_path: true),
          highlight: %i(
            copilot_insights
          ),
          icon: :copilot
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def copilot_code_generation_insights_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Code generation",
          link_path: copilot_insights_code_generation_enterprise_insights_url(business, only_path: true),
          highlight: %i(
            copilot_insights_code_generation
          ),
          icon: :copilot
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def insights_actions_usage_metrics_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Actions usage metrics",
          link_path: actions_usage_metrics_enterprise_url(business, only_path: true),
          highlight: %i(
            business_actions_usage_metrics
          ),
          icon: :play
        )
      end

      sig { returns EnterpriseNavigation::Link }
      def insights_actions_performance_metrics_menu_item
        EnterpriseNavigation::Link.new(
          link_name: "Actions performance metrics",
          link_path: actions_performance_metrics_enterprise_url(business, only_path: true),
          highlight: %i(
            business_actions_performance_metrics
          ),
          icon: :play
        )
      end
    end
  end
end
