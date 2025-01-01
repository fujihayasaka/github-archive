# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class MentionableUsers < Platform::Resolvers::Users
      # setting to 10k because the 1k limit set in the mentionable_users_for method omits a number
      # of users for orgs with more than 1k members
      MENTIONABLES_LIMIT = 10_000
      argument :query, String, "Filters users with query on user name and login", required: false

      def resolve(query: nil)
        context[:permission].async_can_get_full_repo?(object).then do |can_get_full_repo|
          if can_get_full_repo
            Promise.all([object.async_parent, object.async_owner]).then do
              if object.owner.organization?
                Platform::Loaders::Configuration.load(object.owner, :default_repository_permission)
              end
            end.then do
              scope = filter_spam(object.mentionable_users_for(context[:viewer], limit: MENTIONABLES_LIMIT))

              query_string = ActiveRecord::Base.sanitize_sql_like(
                query.to_s.strip.downcase,
              )

              if scope && query_string.present?
                scope = scope.joins("LEFT JOIN profiles ON profiles.user_id = users.id")
                             .where(["users.login LIKE ? OR profiles.name LIKE ?", "%#{query_string}%", "%#{query_string}%"])
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
