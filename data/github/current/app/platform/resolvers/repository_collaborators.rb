# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class RepositoryCollaborators < Resolvers::Base
      argument :affiliation, Enums::CollaboratorAffiliation, "Collaborators affiliation level with a repository.", required: false
      argument :login, String, "The login of one specific collaborator.", required: false
      argument :query, String, "Filters users with query on user name and login", required: false

      type Platform::Connections::RepositoryCollaborator, null: true

      def resolve(**arguments)
        Promise.all([object.async_parent, object.async_owner]).then do
          context[:permission].async_can_list_collaborators?(object).then do |can_list_collabs|
            raise Errors::Forbidden, "You do not have permission to view repository collaborators." unless can_list_collabs

            object.async_organization.then do
              if object.in_organization?
                object.async_advisory_workspace?.then do
                  Platform::Loaders::Configuration.load(object.organization, :default_repository_permission)
                end
              end
            end.then do
              member_ids = filtered_member_ids(affiliation: arguments[:affiliation])
              if member_ids.empty?
                relation_wrapper = Platform::ConnectionWrappers::RepositoryCollaborators.new(::User.none, arguments,
                  parent: @object, context: @context, collaborators_count: 0, inverse_relation_exists: false)
                next relation_wrapper
              end

              relation, count, inverse_relation_exists = build_relation(member_ids, arguments)
              wrapper = Platform::ConnectionWrappers::RepositoryCollaborators.new(relation, arguments,
                parent: @object, context: @context, collaborators_count: count, inverse_relation_exists: inverse_relation_exists)
            end
          end
        end
      end

      private

      def build_relation(member_ids, arguments)
        if arguments[:login].present?
          return [build_login_filter_relation(member_ids, arguments[:login]), nil, nil]
        end

        if arguments[:query].present?
          return [build_query_filter_relation(member_ids, arguments[:query]), nil, nil]
        end

        count = member_ids.size
        inverse_relation_exists = false
        # We always have a user here as cursor, we
        # also know member_ids is sorted here

        if after = arguments[:after]
          after_user_id = ConnectionWrappers::CursorGenerator.resolve_cursor(after).first
          after_position = member_ids.bsearch_index { |x| x > after_user_id }
          if after_position
            member_ids.shift(after_position)
            inverse_relation_exists = after_position > 0
          else
            inverse_relation_exists = member_ids.size > 0
            member_ids.clear
          end
        end

        if before = arguments[:before]
          before_user_id = ConnectionWrappers::CursorGenerator.resolve_cursor(before).first
          before_position = member_ids.bsearch_index { |x| x >= before_user_id }
          if before_position
            to_drop = member_ids.size - before_position
            member_ids.pop(to_drop)
            inverse_relation_exists = to_drop > 0
          else
            inverse_relation_exists = member_ids.size > 0
            member_ids.clear
          end
        end

        if first = arguments[:first]
          # Grab one more since pagination checks if there's more results
          member_ids = member_ids.first(first + 1)
        end

        if last = arguments[:last]
          # Grab one more since pagination checks if there's more results
          member_ids = member_ids.last(last + 1)
        end

        [::User.where(id: member_ids), count, inverse_relation_exists]
      end

      def build_login_filter_relation(member_ids, login)
        members = ::User.where(id: member_ids)
        apply_login_filter(members, login)
      end

      def apply_login_filter(scope, login)
        return scope if login.blank?
        filtered_user = ::User.find_by_login(login)
        scope.where(id: filtered_user&.id)
      end

      def build_query_filter_relation(member_ids, query)
        members = ::User.where(id: member_ids)
        apply_query_filter(members, query)
      end

      def apply_query_filter(scope, query)
        query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
        return scope unless query.present?

        if GitHub.multi_tenant_enterprise?
          scope.includes(:profile)
               .where(["users.display_login LIKE :query OR profiles.name LIKE :query AND users.business_id = :business_id", { query: "%#{query}%", business_id: object.owner.business_id }])
               .references(:profile)
        else
          scope.includes(:profile)
               .where(["users.login LIKE :query OR profiles.name LIKE :query", { query: "%#{query}%" }])
               .references(:profile)
        end
      end

      def filtered_member_ids(affiliation:)
        case affiliation
        when "outside"
          object.outside_collaborators_ids.sort
        when "direct"
          object.direct_member_ids.sort
        else
          if object.in_organization? && object.advisory_workspace?
            # Org owned advisory workspaces are an edge case where the default repo permission does not apply. Instead only admins and those who
            # have been granted direct permission can see these repos
            (Set.new(object.organization.admin_ids) + object.direct_member_ids).sort
          else
            object.direct_or_team_member_ids(viewer: context[:viewer], immediate_only: false).sort
          end
        end
      end
    end
  end
end
