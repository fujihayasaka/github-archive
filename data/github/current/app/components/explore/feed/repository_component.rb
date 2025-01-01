# typed: true
# frozen_string_literal: true

module Explore
  module Feed
    class RepositoryComponent < ApplicationComponent
      extend T::Sig
      include ExploreHelper
      include DashboardAnalyticsHelper
      include ::TextHelper

      def initialize(repository:, current_visitor:, location: nil, is_sponsorable: false, is_sponsoring: false, label: "", recommendation: nil)
        @repository = repository
        @current_visitor = current_visitor
        @is_sponsorable = is_sponsorable
        @is_sponsoring = is_sponsoring
        @label = label
        @recommendation = recommendation
        @location = location
      end

      private

      def render?
        if @recommendation.present?
          @repository.present? && @recommendation.present? && @repository == @recommendation.repository
        else
          @repository.present? && @current_visitor.present?
        end
      end

      def sponsorable?
        @is_sponsorable
      end

      def sponsoring?
        @is_sponsoring
      end

      def sponsor_button_location
        return unless @location

        if sponsoring?
          "#{@location}_SPONSORING".to_sym
        else
          "#{@location}_SPONSOR".to_sym
        end
      end

      def open_graph_image_url
        custom_image = @repository.open_graph_image
        if custom_image.present?
          custom_image.storage_external_url(current_user)
        else
          nil
        end
      end

      def show_open_graph_image?
        @repository.uses_custom_open_graph_image? && open_graph_image_url.present?
      end

      def current_user_has_starred?
        @current_user_has_starred = if logged_in?
          @repository.starred_by?(current_user)
        else
          false
        end
      end

      def repository_description_html
        formatted_repo_description(@repository)
      end

      # Used by ExploreHelper#explore_click_tracking_attributes.
      def explore_click_context
        :REPOSITORY_CARD
      end

      # Required for IssuesHelper#issues_search_query, which is used by
      # LabelsHelper#label_with_description.
      #
      # This is nil for consistency with the implementation used by views
      # rendered by ExploreController, which does not override the default
      # implementation in ApplicationController.
      def current_repository
        nil
      end

      sig { override.returns(T.untyped) }
      def current_context; end
    end
  end
end
