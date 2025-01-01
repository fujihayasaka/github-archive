# typed: true
# frozen_string_literal: true

module ControllerMethods
  module PullRequests
    extend ActiveSupport::Concern
    extend T::Helpers

    include RelayHelper
    include ::PullRequests::MergeboxHelper

    requires_ancestor { ApplicationController }

    included do
      T.bind(self, T.class_of(ApplicationController))
      helper_method :tab_specified?
      helper_method :specified_tab
      helper_method :stats
    end

    def tab_specified?(tab_name)
      specified_tab.to_s == tab_name.to_s
    end

    def specified_tab
      return @specified_tab if defined?(@specified_tab)
      params[:tab].presence || "discussion"
    end

    def stats
      @_stats ||= ::PageStats.new(
        controller_name: "pull_request",
        action_name: action_name,
        viewer: current_user,
        pjax: pjax?,
      )
    end

    # Overrides the default `tree_name` method which pulls current tree from the URL or default branch
    # to prefer the pull requests head branch by default.
    def tree_name
      if @pull && @pull.open?
        @pull.head_ref_name
      elsif @pull
        @pull.head_sha
      else
        super
      end
    end

    private

    def exclude_item_types
      if current_user&.site_admin?
        params.fetch(:exclude_item_types, [])
      else
        []
      end
    end

    def show_prx?
      return false unless user_feature_enabled?(:prx)

      prx_query_param = params[:prx]
      if prx_query_param.present?
        return true if prx_query_param == "true"
        return false if prx_query_param == "false"
      end

      current_user&.feature_preview_enabled?(:prx)
    end

    def show_prx_commits?
      return false if params[:range].present?
      return true if params[:prx_commits].present? && !ENV["LUC_PERFORMANCE"].nil?
      return false if !user_feature_enabled?(:prx_commits)
      current_user&.feature_preview_enabled?(:prx_commits)
    end

    def set_mergebox_preload_header(pull, user)
      mergebox_preload_header = GraphQLRequest.new(
        query: MERGEBOX_QUERY,
        variables: { id: pull.global_relay_id, mergeMethod: default_merge_method_for_user(pull, user) }
      )

      set_preload_header([mergebox_preload_header])
    end
  end
end
