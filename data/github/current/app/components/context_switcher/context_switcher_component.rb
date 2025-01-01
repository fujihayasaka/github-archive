# typed: true
# frozen_string_literal: true

module ContextSwitcher
  class ContextSwitcherComponent < ApplicationComponent

    # current_context  - The User or Organization that we are currently using the app.
    # redirect_paths - A Hash of the redirect paths for the different contexts.
    # defer_loading - Whether or not to defer loading the context switcher.
    # show_only_owning - Whether or not to show only owned orgs.
    def initialize(current_context:, redirect_paths: nil, defer_loading: true, show_only_owning: false)
      @current_context = current_context
      @defer_loading   = defer_loading
      @redirect_paths  = redirect_paths
      @show_only_owning = show_only_owning
    end

    private

    attr_reader :current_context, :defer_loading, :filterable, :redirect_paths, :show_only_owning
    alias_method :defer_loading?, :defer_loading

    def render?
      return false unless logged_in?
      current_context && dashboard_contexts.switchable?
    end

    def dashboard_contexts
      current_user.dashboard_contexts
    end

    def deferred_loading_path
      return unless defer_loading?
      contexts_path(current_context: current_context, redirect_paths: redirect_paths, show_only_owning: show_only_owning)
    end
  end
end
