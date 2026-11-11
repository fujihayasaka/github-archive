# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    class NameWithOwnerRepositoryProvider < ApplicationProvider
      def self.modes
        [
          :global_jump_to,
          :owner_jump_to,
          :modeless_global,
          :modeless_owner
        ]
      end

      def search(query)
        return [] if query.blank?
        return [] unless query.match?(Repository::NAME_WITH_OWNER_PATTERN)

        search_repos_by_nwo(query).map do |object|
          Result.jump_to(object, context: context)
        end
      end

      def search_repos_by_nwo(query)
        repository = Repository.with_name_with_owner(query)
        if repository&.readable_by?(current_user)
          [repository]
        else
          []
        end
      end
    end
  end
end
