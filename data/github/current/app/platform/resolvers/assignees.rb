# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class Assignees < Platform::Resolvers::Users
      include Helpers::AssigneesHelper

      sig { returns(Promise[T::Array[User]]) }
      def resolve
        object.async_repository.then do |repository|
          context[:permission].async_owner_if_org(repository).then do |org|
            if context[:permission].access_allowed?(:list_assignees, resource: repository, repo: repository, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
              if object.is_a?(PullRequest)
                object.async_issue.then do |issue|
                  get_assignees(issue)
                end
              elsif object.is_a?(IssueTemplate)
                logins = extract_logins_from_string(object.assignees_string)
                valid_users = get_valid_assignees_from_logins(repository, logins)

                copilot_bot = get_copilot_assignee(repository, logins, context[:viewer])
                copilot_bot ? ArrayWrapper.new(valid_users.to_a + [copilot_bot]) : valid_users
              else
                get_assignees(object)
              end
            else
              ::User.none
            end
          end
        end
      end

      private

      sig { params(issue: Issue).returns(Promise[T::Array[User]]) }
      def get_assignees(issue)
        issue.async_assignees.then do |assignees|
          # preload business_user_accounts for permission attributes, prevents n+1 for assignee.authorized? checks
          Promise.all(assignees.map(&:async_business_user_accounts)).then do
            filter_spam(ArrayWrapper.new(assignees))
          end
        end
      end
    end
  end
end
