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
          # If the feature flag is enabled for the mutation actor or globally, return all replica clusters
          return @replica_clusters_for_read_mutation_fields || [] if ::FeatureFlag.vexi.enabled?(:gql_read_mutation_fields_from_replicas, Platform::MutationActor.new(self), default: false)

          # Otherwise iterate over clusters and check the (mutation, cluster) actor
          (@replica_clusters_for_read_mutation_fields || []).select do |cluster_class|
            ::FeatureFlag.vexi.enabled?(:gql_read_mutation_fields_from_replicas, Platform::MutationAndClusterActor.new(self, cluster_class), default: false)
          end
        end
      end
    end
  end
end
