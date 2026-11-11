# typed: true
# frozen_string_literal: true

class Hook::Event
  module ClusterWaitDependency
    extend ActiveSupport::Concern

    class_methods do

      sig { params(clusters: T.class_of(ApplicationRecord::Base)).returns(T::Array[Symbol]) }
      def wait_on_clusters(*clusters)
        @wait_cluster_names = clusters
          .filter { |c| c.is_a?(Class) && c < ApplicationRecord::Base } # ApplicationRecord as ancestor
          .map(&:cluster_name)
      end

      sig { returns(T::Boolean) }
      def filter_wait_clusters?
        wait_cluster_names.any?
      end

      sig { returns(T::Array[Symbol]) }
      def wait_cluster_names
        @wait_cluster_names || []
      end

      sig { params(last_writes: T.untyped).returns(T.untyped) }
      def filter_last_writes(last_writes)
        return last_writes unless filter_wait_clusters?
        last_writes.slice(*wait_cluster_names)
      end
    end
  end
end
