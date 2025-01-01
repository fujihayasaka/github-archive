# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class UserPullRequests < Resolvers::PullRequests
      include Scientist

      def fetch_pull_requests(user, _, _)
        scope = user.pull_requests
        scope = context[:permission].filter_permissible_repository_resources(user, scope, resource: "pull_requests")
      end
    end
  end
end
