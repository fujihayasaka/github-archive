# typed: true
# frozen_string_literal: true

module Dashboard
  module ContextSwitcher
    class ListComponent < ApplicationComponent
      include DashboardAnalyticsHelper
      include AvatarHelper

      # contexts        - An Array of User::DashboardContexts::Context.
      # current_context - The User or Organization that we are currently
      #                   displaying a dashboard for.
      # id              - id of the context switcher component.
      def initialize(contexts:, current_context:, id: nil)
        @contexts        = contexts
        @current_context = current_context
        @id = id
      end

      private

      attr_reader :contexts, :current_context, :id

      def render?
        contexts.present? && current_context.present?
      end

      def context_path(context:)
        if show_billing_settings?(context)
          settings_org_billing_path(context.account)
        else
          if context.account.organization?
            org_dashboard_path(context.account)
          else
            home_path
          end
        end
      end

      def context_link(context:, &block)
        data_attrs = test_selector_hash("context-#{context.account.id}")

        GitHub::Menu::LinkComponent.new(
          data: data_attrs,
          href: context_path(context: context),
          checked: context.account.id == current_context.id,
        ) { yield }
      end

      # Private: Indicates if we should be linking to the billing settings instead of the dashboard for a context.
      #
      # context - The User::DashboardContexts::Context to check.
      #
      # Returns a Boolean.
      def show_billing_settings?(context)
        return false if context.adminable?
        context.billing_manager?
      end

      def account_src(context)
        avatar_url_for(context.account, 20 * 2)
      end
    end
  end
end
