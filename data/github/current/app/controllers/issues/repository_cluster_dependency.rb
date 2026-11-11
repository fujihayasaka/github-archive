# typed: true
# frozen_string_literal: true

module Issues
  module RepositoryClusterDependency
    extend T::Helpers

    # Minimum remaining request time budget (in milliseconds) before we skip
    # repository-dependent work entirely and let the request fail fast.
    #
    # See: https://github.com/github/issues-platform/issues/1114
    REPOSITORY_QUERY_TIME_BUFFER_MS = T.let(5_000, Integer)

    sig do
      type_parameters(:T)
        .params(block: T.proc.returns(T.type_parameter(:T)))
        .returns(T.type_parameter(:T))
    end
    def with_replica_repository_cluster(&block)
      return block.call if ActiveRecord::Base.single_database_cluster?

      ActiveRecord::Base.connected_to_many([ApplicationRecord::Repositories], role: :reading, &block)
    end

    sig do
      type_parameters(:T)
        .params(block: T.proc.returns(T.type_parameter(:T)))
        .returns(T.type_parameter(:T))
    end
    def with_primary_repository_cluster(&block)
      return block.call if ActiveRecord::Base.single_database_cluster?

      ActiveRecord::Base.connected_to_many([ApplicationRecord::Repositories], role: :writing, &block)
    end

    # Around action guard: checks remaining request time budget before
    # proceeding. If the request has already consumed most of its budget
    # (likely due to slow repository cluster queries), raises
    # TimeBudgetIsOverError to fail fast rather than tying up the unicorn
    # worker.
    #
    # See: https://github.com/github/issues-platform/issues/1114
    def with_repository_time_budget_guard
      GitHub::RequestDurationManager.raise_if_time_budget_is_over(
        time_buffer_ms: REPOSITORY_QUERY_TIME_BUFFER_MS,
      ) { |_remaining| yield }
    end
  end
end
