# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    module ReadFromSelectedReplicas
      extend T::Helpers
      extend ActiveSupport::Concern

      requires_ancestor { Platform::Mutations::Base }

      included do

        sig do
          type_parameters(:T)
            .params(clusters: T::Array[T.class_of(ApplicationRecord::Base)], block: T.proc.returns(T.type_parameter(:T)))
            .returns(T.type_parameter(:T))
        end
        def read_from_selected_replicas(clusters, &block)
          return block.call if ActiveRecord::Base.single_database_cluster?

          if clusters.any? && can_read_from_replicas?
            ActiveRecord::Base.connected_to_many(clusters, role: :reading, &block)
          else
            block.call
          end
        end

        sig { returns(T::Boolean) }
        def can_read_from_replicas?
          context[:viewer]&.feature_enabled?(:gql_read_from_replicas) &&
          Platform::MutationActor.new(self.class).feature_enabled?(:gql_read_from_replicas) || false
        end
        private :can_read_from_replicas?
      end
    end
  end
end
