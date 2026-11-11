# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class ProjectV2Item < Connections::Base

      total_count_field

      def nodes
        object.edge_nodes
      end
    end
  end
end
