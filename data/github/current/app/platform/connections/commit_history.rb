# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class CommitHistory < Connections::Base
      edge_type(Objects::Commit.edge_type)
      # Override this to use the `edges` method instead of `edge_node`,
      # since the connection wrapper customized those objects
      def edges
        object.edges
      end

      total_count_field
    end
  end
end
