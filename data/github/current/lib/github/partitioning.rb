# typed: true
# frozen_string_literal: true

module GitHub
  module Partitioning
    autoload :CrossPartitionConnections, "github/partitioning/cross_partition_connections"
    autoload :CrossPartitionQueryBuilder, "github/partitioning/cross_partition_query_builder"
    autoload :Denormalization, "github/partitioning/denormalization"
    autoload :ScatterGatherer, "github/partitioning/scatter_gatherer"
  end
end
