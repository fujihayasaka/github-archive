# typed: true
# frozen_string_literal: true

module Repositories
  module New
    class OwnerEmptySelectionOption # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      def id
        nil
      end

      def default_repo_visibility
        "private"
      end

      def default_new_repo_branch
        "main"
      end

      def has_any_trade_restrictions?
        false
      end

      def organization?
        false
      end

      def login
        "Select an owner"
      end

      def display_login
        "Select an owner"
      end
      alias_method :to_s, :display_login
    end
  end
end
