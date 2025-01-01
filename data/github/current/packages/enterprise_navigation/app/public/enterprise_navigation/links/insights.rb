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
        groups << EnterpriseNavigation::Group.new(
          links: insights_menu_items
        )
      end

      sig { returns T::Array[EnterpriseNavigation::Link] }
      memoize def insights_menu_items
        menu_item = []
        menu_item << insights_actions_usage_metrics_menu_item
        menu_item << insights_actions_performance_metrics_menu_item
        menu_item
      end

      private

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
