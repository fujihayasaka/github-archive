# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class RefPullRequests < Resolvers::PullRequests
      private

      def fetch_pull_requests(ref, _, _)
        scope = ::PullRequest.for_ref(ref)
        repository = ref.repository

        unfiltered_repository_ids = scope.pluck(:repository_id)
        # filter out PRs where the base repository has been deleted but
        # the head repository the ref is in is still active
        repository_scope = ::Repository.active.where(id: unfiltered_repository_ids)

        scope_promise = if context[:viewer]&.can_have_granular_permissions? && Ability.can_at_least?(:read, context[:viewer].installation.permissions["pull_requests"])
          # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          repository_ids = T.let(repository_scope.public_scope.or(repository_scope.where(id: context[:viewer].associated_repository_ids)).pluck(:id), Array)
          # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
          scope = scope.where(repository_id: repository_ids)
          Promise.resolve(scope)
        else
          context[:permission].async_can_list_pull_requests?(repository).then do |can_list_pull_requests|
            repository_ids = repository_scope.pluck(:id)
            scope = scope.where(repository_id: repository_ids)

            filter_scope_by_visibility(scope, repository, can_list_pull_requests)
          end
        end

        scope_promise.then { scope }
      end
    end
  end
end
