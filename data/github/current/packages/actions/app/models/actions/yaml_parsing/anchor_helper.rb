# typed: true
# frozen_string_literal: true

require "yaml"
require_relative "./user_error"

module Actions
  module YamlParsing
    # Helper class for storing YAML anchors and resolving YAML aliases
    class AnchorHelper
      def initialize
        @anchors = {}
      end

      # Resolve alias to anchor or return the node if it's not an alias
      # @param node [Psych::Nodes::Node] A YAML node
      # @return [Psych::Nodes::Node] The resolved node
      def resolve(node)
        # Alias?
        if node.is_a?(Psych::Nodes::Alias)
          result = @anchors[node.anchor]
          if result.nil?
            raise UserError, "Unresolved alias: #{node.anchor}"
          end

          result
        else
          # Anchor?
          if node.anchor != nil
            @anchors[node.anchor] = node
          end

          # Not anchor or alias.
          # Return the node.
          node
        end
      end
    end
  end
end
