# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SearchShortcutQueryCategoryTerm < Platform::Objects::Base
      description "Known discussion catregory term and value extracted from a search shortcut query string"
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

      field :discussion_category, Objects::DiscussionCategory, "The discussion category that the term refers to.", null: true

      def discussion_category
        return nil unless object[:value] && object[:scoping_repository_id]

        Loaders::ActiveRecord.load(::Repository, object[:scoping_repository_id], security_violation_behaviour: :nil).then do |repo|
          if repo.present?
            repo.discussion_categories.where(slug: object[:value]).first
          else
            Promise.resolve(nil)
          end
        end
      end
    end
  end
end
