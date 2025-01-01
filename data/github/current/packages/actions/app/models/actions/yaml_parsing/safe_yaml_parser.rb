# typed: true
# frozen_string_literal: true

require "yaml"
require_relative "./anchor_helper"
require_relative "./memory_helper"
require_relative "./user_error"

module Actions
  module YamlParsing
    # Memory-safe YAML parser with support for anchors and aliases
    class SafeYamlParser
      DEFAULT_MAX_BYTES = 10 * 1024 * 1024 # 10 MiB
      DEFAULT_MAX_DEPTH = 50
      DEFAULT_MAX_NODES_TRAVERSED = 50000 # Helps prevent excessive nodes traversed from YAML anchors

      # Parse YAML content safely with memory constraints
      # @param content [String] YAML content to parse
      # @param max_bytes [Integer] Maximum memory usage allowed in bytes
      # @param max_depth [Integer] Maximum depth of the YAML structure
      # @param max_nodes_traversed [Integer] Maximum number of nodes traversed
      # @return [Hash, Array, nil] Parsed YAML content
      # @raise [YamlParsingError] If the YAML cannot be parsed
      def self.safe_load(content, max_bytes: DEFAULT_MAX_BYTES, max_depth: DEFAULT_MAX_DEPTH, max_nodes_traversed: DEFAULT_MAX_NODES_TRAVERSED)
        # Validate max_bytes
        if max_bytes.nil? || max_bytes <= 0
          raise ArgumentError, "max_bytes must be a positive integer"
        end

        # Validate max_depth
        if max_depth.nil? || max_depth <= 0
          raise ArgumentError, "max_depth must be a positive integer"
        end

        # Validate max_nodes_traversed
        if max_nodes_traversed.nil? || max_nodes_traversed <= 0
          raise ArgumentError, "max_nodes_traversed must be a positive integer"
        end

        # Validate input
        raise ArgumentError, "Content must be a String" unless content.is_a?(String)

        # Initialize memory helper
        memory_helper = MemoryHelper.new(max_bytes)

        begin
          parse_yaml(content, memory_helper, max_depth, max_nodes_traversed)
        rescue Psych::Exception => e
          raise UserError.new e.message
        end
      end

      # Append position information to error messages when available
      # @param node [Psych::Nodes::Node] The YAML node
      # @param message [String] The error message
      # @return [String] The message with position information
      private_class_method def self.append_position(node, message)
        if node && node.instance_variable_defined?("@start_line") && node.instance_variable_defined?("@start_column")
          "#{message} at line #{node.start_line + 1} column #{node.start_column + 1}"
        else
          message
        end
      end

      # Parse YAML string into Ruby objects with memory and recursion limits
      # @param yaml_string [String] The YAML content to parse
      # @param memory [MemoryHelper] The memory helper instance for tracking memory usage
      # @param max_depth [Integer] Maximum depth of the YAML structure
      # @param max_nodes_traversed [Integer] Maximum number of nodes traversed
      # @return [Hash, Array, nil] The parsed YAML content
      private_class_method def self.parse_yaml(yaml_string, memory, max_depth, max_nodes_traversed)
        # Parse
        document = YAML.parse(yaml_string)

        # Validate document
        if !document.is_a?(Psych::Nodes::Document)
          # All lines empty or a comment?
          if yaml_string.lines.all? { |line| line.strip.empty? || line.strip.start_with?("#") }
            return nil
          end

          raise UserError.new "Not a valid YAML document"
        elsif document.children.length > 1
          raise "Expected at most one root node"
        end

        # Root node
        if document.children.empty?
          return nil
        end

        root = document.children[0]
        memory.add_bytes(root)

        # Scalar?
        if root.is_a?(Psych::Nodes::Scalar)
          root.to_ruby
        else
          # Initialize result
          result = if root.is_a?(Psych::Nodes::Mapping)
            {}
          elsif root.is_a?(Psych::Nodes::Sequence)
            []
          else
            raise append_position(root, "Unexpected root node type #{root.class}")
          end

          # Walk the document
          conv_stack = [result] # Stores the converted value
          node_stack = [root]   # YAML node stack
          index_stack = [0]     # Index stack
          nodes_traversed = 1
          anchor_helper = AnchorHelper.new

          while true
            # Max depth?
            if node_stack.length > max_depth
              raise UserError.new "Max YAML depth exceeded"
            end

            # Peek
            conv = conv_stack.last
            node = node_stack.last
            index = index_stack.last

            # More mapping pairs?
            if index < node.children.length && node.is_a?(Psych::Nodes::Mapping)
              # Max nodes?
              nodes_traversed += 2
              if nodes_traversed > max_nodes_traversed
                raise UserError.new "Excessive number of YAML nodes"
              end

              # Pair
              pre_resolve_key = node.children[index]
              pre_resolve_value = node.children[index + 1]
              key = anchor_helper.resolve(pre_resolve_key)
              value = anchor_helper.resolve(pre_resolve_value)
              memory.add_bytes(key)
              memory.add_bytes(value)

              # Increment index
              index_stack[-1] += 2

              # Non-scalar key?
              if !key.is_a?(Psych::Nodes::Scalar)
                raise UserError.new append_position(pre_resolve_key, "Non-scalar key not supported")
              end

              # Scalar?
              if value.is_a?(Psych::Nodes::Scalar)
                conv[key.to_ruby] = value.to_ruby
              # Mapping?
              elsif value.is_a?(Psych::Nodes::Mapping)
                conv_stack.push({})
                node_stack.push(value)
                index_stack.push(0)
                conv[key.to_ruby] = conv_stack.last
              # Sequence?
              elsif value.is_a?(Psych::Nodes::Sequence)
                conv_stack.push([])
                node_stack.push(value)
                index_stack.push(0)
                conv[key.to_ruby] = conv_stack.last
              # Unexpected
              else
                raise append_position(pre_resolve_key, "Unexpected mapping value node type #{value.class}")
              end
            # More sequence items?
            elsif index < node.children.length
              # Max nodes?
              nodes_traversed += 1
              if nodes_traversed > max_nodes_traversed
                raise UserError.new "Excessive number of YAML nodes"
              end

              # Item
              pre_resolve_item = node.children[index]
              item = anchor_helper.resolve(pre_resolve_item)
              memory.add_bytes(item)

              # Increment index
              index_stack[-1] += 1

              # Ensure we're working with an array for push operations
              unless conv.is_a?(Array)
                raise "Expected array but got #{conv.class} when trying to add sequence item"
              end

              # Scalar?
              if item.is_a?(Psych::Nodes::Scalar)
                conv.push(item.to_ruby)
              # Mapping?
              elsif item.is_a?(Psych::Nodes::Mapping)
                conv_stack.push({})
                node_stack.push(item)
                index_stack.push(0)
                conv.push(conv_stack.last)
              # Sequence?
              elsif item.is_a?(Psych::Nodes::Sequence)
                conv_stack.push([])
                node_stack.push(item)
                index_stack.push(0)
                conv.push(conv_stack.last)
              # Unexpected
              else
                raise append_position(pre_resolve_item, "Unexpected sequence item node type #{item.class}")
              end
            # Move to parent?
            elsif node_stack.length > 1
              conv_stack.pop
              node_stack.pop
              index_stack.pop
            # Done
            else
              return conv
            end
          end
        end
      end
    end
  end
end
