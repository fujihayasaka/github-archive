# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class ProjectV2ViewItem < Connections::Base

      total_count_field

      mobile_only true

      def nodes
        object.edge_nodes
      end
    end
  end
end
