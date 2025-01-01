# typed: true
# frozen_string_literal: true

module Search
  module Filters
    class NotificationOwnerFilter < ::Search::Filter
      attr_reader :unauthorized_account_ids

      # Create a new NotificationOwnerFilter instance using the given options.
      #
      # opts - The options Hash
      #   :qualifiers - The Hash of qualifiers parsed from the search phrase
      #   :unauthorized_account_ids - a list of unauthorized User/Organization ids
      #
      def initialize(opts = {})
        super(opts)

        @field = :owner_id
        @keys = nil

        @unauthorized_account_ids = options.fetch(:unauthorized_account_ids, [])

        map_bool_collection
      end

      def bool_collection
        return @bool_collection if defined? @bool_collection
        @bool_collection = ::Search::ParsedQuery::BoolCollection.new

        must_user_ids = user_ids_from_logins(qualifiers[:owner].must)
        @bool_collection.must(must_user_ids) if must_user_ids.present?

        must_not_user_ids = user_ids_from_logins(qualifiers[:owner].must_not) + unauthorized_account_ids
        @bool_collection.must_not(must_not_user_ids) if must_not_user_ids.present?

        @bool_collection
      end

      def user_ids_from_logins(logins)
        return [] unless logins.present?

        User.where(login: logins.map(&:downcase).compact, spammy: false).pluck(:id)
      end
    end  # NotificationOwnerFilter
  end  # Filters
end  # Search
