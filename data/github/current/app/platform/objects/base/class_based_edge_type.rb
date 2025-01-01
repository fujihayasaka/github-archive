# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module ClassBasedEdgeType
        # Create a class-based type suitable for using as an edge in a connection.
        def edge_type
          @edge_type ||= begin
            wrapped_type = self
            Class.new(Platform::Edges::Base) do
              node_type(wrapped_type)
            end
          end
        end
      end
    end
  end
end
