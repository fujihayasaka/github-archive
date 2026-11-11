# typed: true
# frozen_string_literal: true

module Search
  module Filters
    # A filter that searches for Pull Requests where the named user has been
    # requested as a reviewer directly (i.e. not a team they belong to) This is
    # in constract to ReviewRequestFilter, which returns PRs with a direct
    # review request from the named user or requests on their teams.
    class UserReviewRequestFilter < UserFilter
      def must
        filter = build(bool_collection.must)

        if filter.is_a? Array
          { bool: { should: filter } }
        else
          filter
        end
      end

      # Exclude results where the requested user is an author.
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

        users = filter_users(values)
        hash = { requested_reviewer_ids: values }

        ary = hash.map { |current_field, value| build_term_filter(current_field, value, execution: execution) }
        ary.compact!

        case ary.length
        when 0 then nil
        when 1 then ary.first
        else ary
        end
      end
    end
  end
end
