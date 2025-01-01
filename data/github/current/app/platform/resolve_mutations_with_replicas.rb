# typed: true
# frozen_string_literal: true

module Platform
  # This resolver wrapper is used to read mutation fields from replicas.
  module ResolveMutationsWithReplicas
    module ResolveWrapper
      def resolve(obj, args, ctx)
        # we should be able to call .mutation on self after checking if it responds to it but
        # sorbet doesn't support it yet: https://github.com/sorbet/sorbet/issues/3469
        unsafe_self = T.unsafe(self)

        if unsafe_self.respond_to?(:mutation) && unsafe_self.mutation && unsafe_self.mutation.respond_to?(:replica_clusters_for_read_mutation_fields_clusters)
          ctx[:replica_clusters_for_read_mutation_fields] = unsafe_self.mutation.replica_clusters_for_read_mutation_fields_clusters
        end

        return super if ctx[:replica_clusters_for_read_mutation_fields].blank? || ActiveRecord::Base.single_database_cluster?

        # set the replica_clusters_for_read_mutation_fields in the global scope because most of the
        # records are resolved in async loaders that run outside of the resolver context
        Platform::GlobalScope.resolve_loaders_with_replicas = ctx[:replica_clusters_for_read_mutation_fields]

        ActiveRecord::Base.connected_to_many(ctx[:replica_clusters_for_read_mutation_fields], role: :reading) do
          super
        end
      end
    end
  end
end
