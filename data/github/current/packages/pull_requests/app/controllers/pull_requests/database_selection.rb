# typed: true
# frozen_string_literal: true

module PullRequests
  module DatabaseSelection
    extend T::Helpers

    requires_ancestor { ApplicationController }

    # directs reads to the specified clusters' replicas
    # can be invoked via a controller around_action or prepend_around_action
    # see suggested controller implementations in test/integration/pull_requests/database_selection_test.rb
    sig do
      type_parameters(:T)
        .params(
          clusters: T.nilable(T::Array[T.class_of(ApplicationRecord::Base)]),
          block: T.proc.returns(T.type_parameter(:T))
        )
      .returns(T.untyped)
    end
    def use_replica_clusters(clusters, &block)
      if ActiveRecord::Base.single_database_cluster?
        block.call
      else
        ActiveRecord::Base.connected_to_many(clusters, role: :reading, &block) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end
end
