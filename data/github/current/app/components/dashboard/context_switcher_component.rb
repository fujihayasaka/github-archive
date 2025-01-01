# typed: true
# frozen_string_literal: true

module Dashboard
  class ContextSwitcherComponent < ApplicationComponent
    include DashboardAnalyticsHelper

    FILTERABLE_THRESHOLD = 10
    DEFERRED_THRESHOLD   = 3

    # current_context      - The User or Organization that we are currently displaying
    #                        a dashboard for.
    # user_can_create_orgs - A Boolean indicating if the current viewer is able
    #                        to create organizations.
    def initialize(current_context:, user_can_create_orgs:, id: nil)
      @current_context      = current_context
      @user_can_create_orgs = fetch_or_fallback([true, false], user_can_create_orgs, false)
      @id = id
    end

    private

    attr_reader :current_context, :user_can_create_orgs, :id
    alias_method :user_can_create_orgs?, :user_can_create_orgs

    def render?
      return false unless logged_in?
      return false unless current_context.present?

      dashboard_contexts.switchable?
    end

    def dashboard_contexts
      current_user.dashboard_contexts
    end

    def filterable?
      dashboard_contexts.count > FILTERABLE_THRESHOLD
    end

    def defer_loading?
      dashboard_contexts.count > DEFERRED_THRESHOLD
    end

    def preload?
      dashboard_contexts.count <= DEFERRED_THRESHOLD
    end

    def deferred_loading_path
      return unless defer_loading?
      dashboard_ajax_context_list_path(current_context: current_context, id: id)
    end
  end
end
