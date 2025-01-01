# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module ReadMutationFieldsFromReplicas

        sig { params(clusters: T.class_of(ApplicationRecord::Base)).returns(T::Array[T.class_of(ApplicationRecord::Base)]) }
        def read_mutation_fields_from_replicas!(*clusters)
          @replica_clusters_for_read_mutation_fields = clusters
        end

        sig { returns(T::Array[T.class_of(ApplicationRecord::Base)]) }
        def replica_clusters_for_read_mutation_fields_clusters
          return [] unless GitHub.flipper[:gql_read_mutation_fields_from_replicas].enabled?(Platform::MutationActor.new(self))

          @replica_clusters_for_read_mutation_fields || []
        end
      end
    end
  end
end
