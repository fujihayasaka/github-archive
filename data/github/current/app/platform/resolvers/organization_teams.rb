# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class OrganizationTeams < Resolvers::Base
      type Connections.define(Objects::Team), null: false

      argument :privacy, Enums::TeamPrivacy, "If non-null, filters teams according to privacy", required: false
      argument :notification_setting, Enums::TeamNotificationSetting, "If non-null, filters teams according to notification setting", required: false
      argument :role, Enums::TeamRole, "If non-null, filters teams according to whether the viewer is an admin or member on team", required: false
      argument :query, String, "If non-null, filters teams with query on team name and team slug", required: false
      argument :user_logins, [String], "User logins to filter by", required: false
      argument :order_by, Inputs::TeamOrder, "Ordering options for teams returned from the connection", required: false
      argument :members_filter, Enums::TeamMembersFilter, Enums::TeamMembersFilter.description, required: false
      argument :ldap_mapped, Boolean, "If true, filters teams that are mapped to an LDAP Group (Enterprise only)", required: false
      argument :root_teams_only, Boolean, "If true, restrict to only root teams", required: false, default_value: false

      def resolve(**arguments)
        return ::Team.none if !context[:permission].can_list_teams?(object)

        members_filter = arguments[:members_filter].try(:downcase)

        # apply members filter
        scope = if context[:viewer].present? && members_filter == "me"
          object.teams_for(context[:viewer])
        elsif members_filter == "empty"
          ::Team.without_members(object.visible_teams_for(context[:viewer]).pluck(:id))
        else
          object.visible_teams_for(context[:viewer])
        end

        if arguments[:ldap_mapped]
          # only select teams with an LDAP Mapping
          scope = scope.joins(:ldap_mapping)
        end

        # Scope teams to those where users matching user_logins are members
        if Array.wrap(arguments[:user_logins]).size > 0
          found_users = []
          Array.wrap(arguments[:user_logins]).each_with_index do |name, i|
            break if i > ::TeamSearchQuery::USER_FILTER_MAX
            found_users << ::User.find_by_login(name)
          end

          if found_users.all?(&:nil?)
            scope = ::Team.none
          else
            found_users.compact.each do |found_user|
              found_user_teams = object.teams_for(found_user)
              teams_scoped_to_found_user = scope.pluck(:id) & found_user_teams.pluck(:id)
              scope = ::Team.where(id: teams_scoped_to_found_user)
            end
          end
        end

        case arguments[:privacy]
        when "secret"
          scope = scope.secret
        when "closed"
          scope = scope.closed
        end

        case arguments[:notification_setting]
        when "notifications_enabled"
          scope = scope.notifications_enabled
        when "scope.notifications_disabled"
          scope = scope.notifications_disabled
        end

        if arguments[:root_teams_only]
          root_team_ids = object.root_teams.pluck(:id)
          scope = scope.where(id: root_team_ids)
        end

        query = ActiveRecord::Base.sanitize_sql_like(
          arguments[:query].to_s.strip.downcase,
        )

        if query.present?
          scope = scope.where(["name LIKE ? OR slug LIKE ?", "%#{query}%", "%#{query}%"])
        end

        if arguments[:order_by] && ::Team.column_names.include?(arguments[:order_by][:field])
          scope = scope.order(arguments[:order_by][:field] => arguments[:order_by][:direction])
        end

        case arguments[:role]
        when :admin
          if object.adminable_by?(context[:viewer])
            scope
          else
            criteria = {
              "actor_type"   => "User",
              "actor_id"     => context[:viewer].id,
              "subject_type" => "Team",
              "priority"     => Ability.priorities[:direct],
              "action"       => Ability.actions[:admin],
            }

            team_ids = Ability.where(criteria).distinct.pluck(:subject_id)
            scope.where(id: team_ids)
          end
        when :member
          criteria = {
            "actor_type"   => "User",
            "actor_id"     => context[:viewer].id,
            "subject_type" => "Team",
            "priority"     => Ability.priorities[:direct],
            "action"       => Ability.actions[:read],
          }

          team_ids = Ability.where(criteria).distinct.pluck(:subject_id)
          scope.where(id: team_ids)
        else
          scope
        end
      end
    end
  end
end
