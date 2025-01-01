# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class SuggestedRepositoryActors < Platform::Resolvers::Users
      include Helpers::AssigneesHelper

      # Defines how many results we want to return for type ahead assignment suggestions
      TYPE_AHEAD_PAGE_SIZE = 100

      argument :query, String, "Search actors with query on user name and login.", required: false
      argument :login_names, String, "A comma separated list of login names to filter actors by. Only the first #{MAX_LOGIN_NAMES_LENGTH} logins will be used.", required: false
      argument :capabilities, [Enums::RepositorySuggestedActorFilter], "A list of capabilities to filter actors by.", required: true

      sig { params(arguments: T.untyped).returns(Promise[ArrayWrapper]) }
      def resolve(**arguments)
        query = arguments[:query]
        login_names = arguments[:login_names]
        capabilities = arguments[:capabilities]

        context[:permission].async_can_get_full_repo?(object).then do |can_get_full_repo|
          if can_get_full_repo
            if login_names.present?
              logins = extract_logins_from_string(login_names)
              users = get_valid_assignees_from_logins(object, logins)

              async_bots(capabilities, context[:viewer], object, logins: logins).then do |capable_bots|
                sort_actors(users, capable_bots)
              end
            else
              if query.present? && resolve_without_limit?
                suggested_assignees_without_limit(context[:viewer], query, capabilities)
              else
                suggested_assignees(capabilities, query)
              end
            end
          else
            ArrayWrapper.new([])
          end
        end
      end

      def suggested_assignees(capabilities, query)
        ids = object.visible_available_assignee_ids(context[:viewer], limit: Issue::AssignmentDependency::PLATFORM_ASSIGNEE_LIMIT)

        scope = User.where(id: ids).includes(:profile)

        scope = filter_spam(scope.order("login"))

        query = ActiveRecord::Base.sanitize_sql_like(
          query.to_s.strip.downcase,
        )

        if scope && query.present?
          scope = scope.joins("LEFT JOIN profiles ON profiles.user_id = users.id")
                      .where(["users.login LIKE ? OR profiles.name LIKE ?", "%#{query}%", "%#{query}%"])
        end

        users = scope&.to_a
        async_bots(capabilities, context[:viewer], object, query: query).then do |capable_bots|
          sort_actors(users, capable_bots)
        end
      end

      def suggested_assignees_without_limit(current_user, search_query, capabilities = nil)
        ids = object.visible_available_assignee_ids(current_user)
        suggested_assignees = get_filtered_assignees_list(current_user, search_query, ids, TYPE_AHEAD_PAGE_SIZE, "suggested_repository_actors")
        async_bots(capabilities, current_user, object, query: search_query).then do |bots|
          sort_actors(suggested_assignees, bots)
        end
      end

      def persisted_query?
        context[:operation_id].present?
      end

      def resolve_without_limit?
        enabled_for_viewer = context[:viewer].present? && context[:viewer].feature_enabled?(:issues_react_assignee_suggestions_unlimited)
        feature_enabled = enabled_for_viewer || GitHub.flipper[:issues_react_assignee_suggestions_unlimited].enabled?

        feature_enabled && persisted_query?
      end
    end
  end
end
