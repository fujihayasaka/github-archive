# typed: true
# frozen_string_literal: true

module Issues
  module RepositoryClusterDependency
    extend T::Helpers
    extend T::Sig

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
  end
end
