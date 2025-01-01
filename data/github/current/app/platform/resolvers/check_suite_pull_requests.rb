# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class CheckSuitePullRequests < Resolvers::PullRequests
      argument :api_serializer_request, Boolean, "Whether or not this request is coming from the REST API", visibility: :internal, required: false

      def fetch_pull_requests(check_suite, arguments, _)
        check_suite.async_repository.then do |repository|
          repository.async_network.then do
            scope = check_suite.matching_pull_requests(context[:viewer])

            scope_promise = if arguments[:api_serializer_request]
              # In the normal world, an App with just `checks` permissions shouldn't see pull requests;
              # but the API serializer is allowed to bypass this
              Promise.resolve(scope)
            else
              context[:permission].async_can_list_pull_requests?(repository).then do |can_list_pull_requests|
                filter_scope_by_visibility(scope, repository, can_list_pull_requests)
              end
            end

            scope_promise.then { scope }

          end
        end
      end
    end
  end
end
