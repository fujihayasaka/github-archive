# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class ProjectV2Group < Connections::Base

      total_count_field

      required_capabilities [:mobile_only_schema_mask]

      # Memex Without Limits introduced a new Search API which provides grouping, sorting, filtering, and
      # paging. Use this field to help determine which backend was used to materialize the results.
      # This can help out for things like showing an in-beta banner for users.
      field :fulfilled_via_elasticsearch,
        Boolean,
        description: "True if Elasticsearch was used, false is MySQL was used.",
        null: false,
        method: :fulfilled_via_elasticsearch?

      def nodes
        object.edge_nodes
      end
    end
  end
end
