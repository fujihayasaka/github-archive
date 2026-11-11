# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ChildTeams < Resolvers::Base
      argument :order_by, Inputs::TeamOrder, "Order for connection", required: false
      argument :query, String, "The search string to look for.", required: false, visibility: :internal
      argument :user_logins, [String], "User logins to filter by", required: false
      argument :members_filter, Enums::TeamMembersFilter, Enums::TeamMembersFilter.description, required: false
      argument :immediate_only, Boolean, "Whether to list immediate child teams or all descendant child teams.", required: false, default_value: true

      type Connections.define(Objects::Team), null: false

      # Other pagination args are added by the field, then used by connection wrappers (`numeric_page:`)
      def resolve(order_by: nil, query: nil, user_logins: nil, members_filter: nil, immediate_only: nil, **_rest)
        return ArrayWrapper.new([]) if object.new_record?

        object.async_organization.then do
          async_members_filter(object, members_filter, immediate_only: immediate_only, viewer: context[:viewer]).then do |scope|

            scope = apply_ordering(scope, order_by)

            scope = apply_user_logins_filter(scope, object, user_logins)

            scope = apply_query_filter(scope, query)

            scope
          end
        end
      end

      private

      def async_members_filter(team, filter, immediate_only:, viewer: nil)
        filter = filter.try(:downcase)

        if viewer.present? && filter == "me"
          Promise.resolve(
            team.descendants_where_user_is_a_member(viewer, immediate_only: immediate_only),
          )
        elsif filter == "empty"
          Promise.resolve(
            team.descendants_without_members(immediate_only: immediate_only),
          )
        else
          team.async_descendants(immediate_only: immediate_only)
        end
      end

      def apply_ordering(scope, order)
        return scope if order.blank?
        scope.order("teams.#{order[:field]} #{order[:direction]}")
      end

      # scope teams to teams where users from userLogins are a member
      def apply_user_logins_filter(scope, team, logins)
        Array.wrap(logins).each_with_index do |name, i|
          break if i > ::TeamSearchQuery::USER_FILTER_MAX
          if searched_user = ::User.find_by_login(name)
            searched_user_teams = team.descendants_where_user_is_a_member(searched_user)
            teams_scoped_to_searched_user = scope & searched_user_teams
            scope = ::Team.where(id: teams_scoped_to_searched_user.map(&:id))
          end
        end
        scope
      end

      def apply_query_filter(scope, query)
        query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
        return scope unless query.present?

        scope.where(["name LIKE ? OR slug LIKE ?", "%#{query}%", "%#{query}%"])
      end
    end
  end
end
