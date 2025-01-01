# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module Insights
      extend T::Helpers
      include GitHub::Memoizer
      include UrlHelpers
      include EnterpriseNavigation::Links::SharedDependency
      include CopilotInsightsPermissions

      sig { returns T::Array[EnterpriseNavigation::Group] }
      memoize def insights_menu_groups
        groups = []
        groups << EnterpriseNavigation::Group.new(
          links: insights_menu_items
        )
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def insights_menu_items
        menu_item = []
        menu_item << copilot_insights_menu_item if copilot_insights_usage_available?(business: business, user: user)
        menu_item << copilot_code_generation_insights_menu_item if copilot_insights_code_generation_available?(business: business, user: user)
        menu_item << insights_actions_usage_metrics_menu_item if actions_items_available?
        menu_item << insights_actions_performance_metrics_menu_item if actions_items_available?
        menu_item
      end

      private

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
          label: Label::PRIVATE_PREVIEW,
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
          label: Label::PRIVATE_PREVIEW,
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
          label: Label::PREVIEW,
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
          label: Label::PREVIEW,
          icon: :play
        )
      end

    end
  end
end
