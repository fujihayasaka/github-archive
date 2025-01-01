# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SearchShortcutQueryLoginRefTerm < Platform::Objects::Base
      description "Known login term and value extracted from a search shortcut query string"
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

      ME_VALUE = "@me".freeze

      field :login_ref, Unions::SearchShortcutQueryTermsLoginReference, <<~DESC, null: true
        "The user, bot, or organization that the term refers to."
      DESC

      def login_ref
        return nil unless object[:value]
        return context[:viewer] if object[:value] == ME_VALUE

        # Can be any of the User sub-classes such as User, Bot, or Organization.
        Loaders::ActiveRecord.load(::User, object[:value], column: :login, security_violation_behaviour: :nil).then do |user|
          next unless user

          context[:permission].typed_can_see?(user.class.name, user).then do |readable|
            user if readable && !user.hide_from_user?(context[:viewer])
          end
        end
      end
    end
  end
end
