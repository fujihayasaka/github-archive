# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class UserPullRequests < Resolvers::PullRequests
      def fetch_pull_requests(user, _, _)
        scope = user.pull_requests
        scope = context[:permission].filter_permissible_repository_resources(user, scope, resource: "pull_requests")
      end

      def wrap_connection(relation, args)
        current_actor = GH.context.identity_context.domain_actor || User.ghost
        if relation.where_clause.extract_attributes.filter { _1.name == "state" && _1.relation.name == "issues" }.any?

          relation.optimizer_hints("INDEX(issues repository_id_and_state_and_pull_request_id_and_user)")
        else
          relation
        end
      end
    end
  end
end
