# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class AssignableUsers < Platform::Resolvers::Users
      include Helpers::AssigneesHelper

      argument :query, String, "Filters users with query on user name and login.", required: false
      argument :login_names, String, "A comma separated list of login names to filter users by. Only the first #{MAX_LOGIN_NAMES_LENGTH} logins will be used.", required: false, visibility: :internal

      def resolve(**arguments)
        context[:permission].async_can_get_full_repo?(object).then do |can_get_full_repo|
          if can_get_full_repo
            if arguments[:login_names].present?
              logins = extract_logins_from_string(arguments[:login_names])
              get_valid_assignees_from_logins(object, logins)
            else
              ids = object.visible_available_assignee_ids(context[:viewer], limit: Issue::AssignmentDependency::PLATFORM_ASSIGNEE_LIMIT)

              scope = User.where(id: ids).includes(:profile)

              scope = filter_spam(scope.order("login"))

              query = ActiveRecord::Base.sanitize_sql_like(
                arguments[:query].to_s.strip.downcase,
              )

              if scope && query.present?
                scope = scope.joins("LEFT JOIN profiles ON profiles.user_id = users.id")
                            .where(["users.login LIKE ? OR profiles.name LIKE ?", "%#{query}%", "%#{query}%"])
              end

              scope
            end
          else
            ArrayWrapper.new([])
          end
        end
      end
    end
  end
end
