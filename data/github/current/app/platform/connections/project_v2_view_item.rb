# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class ProjectV2ViewItem < Connections::Base

      total_count_field

      required_capabilities [:mobile_only_schema_mask]

      def nodes
        object.edge_nodes
      end
    end
  end
end
