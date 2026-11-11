# typed: true
# frozen_string_literal: true

module ContextSwitcher
  class ListComponent < ApplicationComponent
    include DashboardAnalyticsHelper

    # contexts        - An Array of available contexts.
    # current_context - The User or Organization that we are currently
    #                   displaying the page for.
    # redirect_paths - A Hash of the redirect paths for the different contexts.
    def initialize(contexts:, current_context:, redirect_paths: nil)
      @contexts        = contexts
      @current_context = current_context
      @redirect_paths  = redirect_paths
    end

    attr_reader :contexts, :current_context, :redirect_paths

    def render?
      contexts.present? && current_context.present? && redirect_paths.present?
    end

    def context_path(context:)
      custom_path_for(context.account) || user_path(context.account)
    end

    def context_link(context:, &block)
      GitHub::Menu::LinkComponent.new(
        data: test_selector_hash("context-#{context.account.id}"),
        href: context_path(context: context),
        checked: context.account.id == current_context.id,
      ) { yield }
    end

    private

    def context_key(account)
      account.organization? ? :org : :user
    end

    def custom_path_for(account)
      case redirect_paths[context_key(account)]&.to_sym
      when :org_move_work_new_path
        org_move_work_new_path(account)
      when :user_move_work_new_path
        user_move_work_new_path
      else
        nil
      end
    end
  end
end
