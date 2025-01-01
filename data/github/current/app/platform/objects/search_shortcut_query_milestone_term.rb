# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SearchShortcutQueryMilestoneTerm < Platform::Objects::Base
      description "Known milestone term and value extracted from a search shortcut query string"
      scopeless_tokens_as_minimum
      mobile_only true

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # This `object` is a Hash. Authorization and nilification is handled by the parent object and field resolvers.
      def self.async_api_can_access?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # This `object` is a Hash. Authorization and nilification is handled by the parent object and field resolvers.
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      implements Interfaces::SearchShortcutQueryBasicTerm
      implements Interfaces::SearchShortcutQueryParsedTerm

      field :milestone, Objects::Milestone, "The milestone referenced in this term", null: true

      def milestone
        return nil unless object[:scoping_repository_id]

        Loaders::ActiveRecord.load(::Repository, object[:scoping_repository_id], security_violation_behaviour: :nil).then do |repo|
          next unless repo.present?
          Loaders::MilestoneByTitle.load(repo.id, object[:value])
        end
      end
    end
  end
end
