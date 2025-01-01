# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # The ReviewRequestFilter is used to limit search results to a particular user or
    # collection of users and teams that have been requested for review.
    # This class encapsulates the logic of looking up users and generating ElasticSearch term filters.
    class ReviewRequestFilter < UserFilter
      def must
        filter = build(bool_collection.must)

        if filter.is_a? Array
          { bool: { should: filter } }
        else
          filter
        end
      end

      def must_not
        if bool_collection.must
          filter = Array(build(bool_collection.must_not))

          bool_collection.must.each do |user_id, _arry|
            filter << build_term_filter(:author_id, user_id)
          end

          filter
        else
          build(bool_collection.must_not)
        end
      end

      def filter_users(values)
        @users ||= User.where(id: values, type: "User")
      end

      def build(values)
        return if values.blank?
        values = values.first if singular?

        if values.first == :missing
          { bool: { must_not: [
            { exists: { field: :requested_reviewer_ids } },
            { exists: { field: :requested_reviewer_team_ids } },
          ] } }
        else
          users = filter_users(values)
          team_ids = users.map { |u| u.teams(with_ancestors: true).closed.pluck(:id) }.flatten
          hash = { requested_reviewer_ids: values, requested_reviewer_team_ids: team_ids }

          ary = hash.map { |current_field, value| build_term_filter(current_field, value, execution: execution) }
          ary.compact!

          case ary.length
          when 0 then nil
          when 1 then ary.first
          else ary
          end
        end
      end
    end  # ReviewRequestFilter
  end  # Filters
end  # Search
