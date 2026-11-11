# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # A filter that searches for Pull Requests where a team the named user
    # belongs to has been requested for review. This queries only the
    # `requested_reviewer_team_ids` field (resolved from the user's team
    # memberships), unlike ReviewRequestFilter which also includes direct
    # user requests.
    class TeamReviewRequestedByUserFilter < UserFilter
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
        team_ids = users.map { |u| u.teams(with_ancestors: true).closed.pluck(:id) }.flatten

        return if team_ids.blank?
        hash = { requested_reviewer_team_ids: team_ids }
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
