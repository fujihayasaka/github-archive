# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestStack < Platform::Objects::Base
      model_name "PullRequests::Stack"
      docs_category :pulls
      description "A stack of PullRequests"
      visibility :public, environments: [:dotcom, :enterprise]
      feature_flag :pull_request_stacks_graphql

      implements_node templates: [[:prs, :repo_id, :id]], as: "PRS", ready_date: "1970-01-01" do |stack|
        {
          prefix: :prs,
          repo_id: stack.repository_id,
          id: stack.id,
        }
      end

      minimum_accepted_scopes ["repo"]

      sig do
        params(
          permission: Platform::Authorization::Permission,
          stack: ::PullRequests::Stack,
        ).returns(Promise[T::Boolean])
      end
      def self.async_api_can_access?(permission, stack)
        permission.async_repo_and_org_owner(stack).then do |repo, org|
          next false unless ::PullRequests::Stacks.enabled?(repo)
          permission.access_allowed?(
            :get_pull_request_stack,
            resource: repo,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      sig do
        params(
          permission: Platform::Authorization::Permission,
          stack: ::PullRequests::Stack,
        ).returns(Promise[T::Boolean])
      end
      def self.async_viewer_can_see?(permission, stack)
        stack.async_repository.then do |repo|
          if ::PullRequests::Stacks.enabled?(repo)
            permission.belongs_to_repository(stack)
          else
            false
          end
        end
      end

      field :number, Integer, description: "A number uniquely identifying the stack within its repository", null: false

      field :base_ref_name, String, description: "The branch that the stack's pull requests target", null: false
      def base_ref_name = @object.base_ref

      field :size, Integer, description: "The total number of pull requests in the stack", null: false
      def size = @object.entry_count

      field :entries, Connections::PullRequestStackEntry, description: "The entries in the stack",
        null: false, connection: true
      def entries = @object.async_entries
    end
  end
end
