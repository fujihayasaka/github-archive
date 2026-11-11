# typed: true
# frozen_string_literal: true

module Actions
  module Policy
    class PublicForkPullRequestComponent < ApplicationComponent
      include GitHub::Memoizer

      def initialize(entity:, action:)
        @entity = entity
        @action = action
      end

      def title
        return "Fork pull request workflows" if @entity.is_a?(Repository)
        "Fork pull request workflows in public repositories"
      end

      def show_description?
        !@entity.is_a?(Repository)
      end

      def description
        return "Applies to public repositories. Organization and repository administrators will only be able to change enabled settings." if @entity.is_a?(Business)
        "Applies to public repositories. Repository administrators will only be able to change enabled settings."
      end
    end
  end
end
