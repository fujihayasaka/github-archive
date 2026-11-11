# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestStackEntry < Platform::Objects::Base
      model_name "PullRequests::StackEntry"
      docs_category :pulls
      description "A member of a PullRequestStack"
      visibility :public, environments: [:dotcom, :enterprise]
      feature_flag :pull_request_stacks_graphql

      implements_node templates: [[:prse, :repo_id, :id]], as: "PRSE", ready_date: "1970-01-01" do |stack_entry|
        {
          prefix: :prse,
          repo_id: stack_entry.repository_id,
          id: stack_entry.id,
        }
      end

      minimum_accepted_scopes ["repo"]

      sig do
        params(
          permission: Platform::Authorization::Permission,
          stack_entry: ::PullRequests::StackEntry,
        ).returns(Promise[T::Boolean])
      end
      def self.async_api_can_access?(permission, stack_entry)
        permission.async_repo_and_org_owner(stack_entry).then do |repo, org|
          next false unless ::PullRequests::Stacks.enabled?(repo)
          permission.load_pull_and_issue(stack_entry).then do |pull|
            permission.access_allowed?(
              :get_pull_request_stack_entry,
              resource: pull,
              repo: repo,
              current_org: org,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      sig do
        params(
          permission: Platform::Authorization::Permission,
          stack_entry: ::PullRequests::StackEntry,
        ).returns(Promise[T::Boolean])
      end
      def self.async_viewer_can_see?(permission, stack_entry)
        stack_entry.async_repository.then do |repo|
          if ::PullRequests::Stacks.enabled?(repo)
            permission.belongs_to_repository(stack_entry)
          else
            false
          end
        end
      end

      field :position, Integer, description: "This entry's position in the stack, where 1 is the closest to the base branch, 2 is stacked on top of 1, etc.", null: false

      field :stack, Objects::PullRequestStack, description: "The stack that this entry is a part of",
        null: true, method: :async_stack

      field :pull_request, Objects::PullRequest, description: "The pull request that occupies this position in the stack",
        null: true, method: :async_pull_request

      # TODO: is_unstackable field
    end
  end
end
