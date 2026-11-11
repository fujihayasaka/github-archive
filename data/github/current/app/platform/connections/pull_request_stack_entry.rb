# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class PullRequestStackEntry < Connections::Base
      description "Entries in a pull request stack"
      total_count_field

      def self.async_api_can_access?(permission, connection)
        stack = connection.parent
        permission.async_repo_and_org_owner(stack).then do |repo, org|
          next false unless ::PullRequests::Stacks.enabled?(repo)
          permission.access_allowed?(
            :list_pull_request_stack_entries,
            resource: stack,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end
    end
  end
end
