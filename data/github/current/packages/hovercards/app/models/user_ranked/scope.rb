# typed: false
# frozen_string_literal: true

module UserRanked
  module Scope
    extend ActiveSupport::Concern

    included do
      # Public: Refine the current scope by adding an ORDER clause based on
      # activity performed by the given user. Ranking is limited to first 1000
      # results, after which ordering goes by id.
      #
      # user - a User
      # scope - an ActiveRecord relation
      # direction - optional direction to order, either :asc or :desc
      #
      # Returns an ActiveRecord relation.
      def self.ranked_for(user, scope:, direction: :desc)
        ids = Cache.fetch_ranked_ids(name, user) do
          compute_ranked_ids(user: user)
        end

        return scope if ids.empty?
        direction = :desc unless [:asc, :desc].include?(direction)
        scope.order(ActiveRecord::Base.sanitize_sql_for_order(
          [Arel.sql("FIELD(#{table_name}.id, ?)"), ids.reverse],
        ) => direction).order(:id)
      end

      # Public: Returns the ids of the first 1000 ranked records.
      #
      # scoped_ids - Optional array of ids to limit results. The returned array
      #              will be a ranked version of this same list of ids, where
      #              ids with no ranking are last.
      #
      # Returns an array of ids (int).
      def self.ranked_for_ids(user, scoped_ids: nil)
        return [] if scoped_ids == []

        ids = Cache.fetch_ranked_ids(name, user) do
          compute_ranked_ids(user: user)
        end

        return ids unless scoped_ids
        scoped_ids.sort_by { |i| ids.index(i) || Float::INFINITY }
      end
    end
  end
end
