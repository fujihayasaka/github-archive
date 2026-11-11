# typed: true
# frozen_string_literal: true

module Biztools
  module RepositoryActions
    class EditView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

      attr_reader :action, :categories

      def initialize(action:, categories:, current_user: nil, user_session: nil)
        @action = action
        @categories = categories
      end

      def regular_categories
        @regular_categories ||= categories.reject(&:acts_as_filter).map(&:name)
      end

      def filter_categories
        @filter_categories ||= categories.select(&:acts_as_filter).map(&:name)
      end

      def selected_regular_categories
        @selected_regular_categories ||= @action.regular_categories.map(&:name)
      end

      def selected_filter_categories
        @selected_filter_categories ||= @action.filter_categories.map(&:name)
      end

      def action_primary_category
        @action_primary_category ||= selected_regular_categories.first
      end

      def action_secondary_category
        @action_secondary_category ||= selected_regular_categories.second
      end

      def action_id
        action.id
      end

      def action_name
        action.name
      end
    end
  end
end
