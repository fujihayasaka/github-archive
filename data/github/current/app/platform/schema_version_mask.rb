# typed: false
# frozen_string_literal: true

module Platform
  class SchemaVersionMask
    AUTO_GENERATED_TYPE_PATTERN = /\A([a-zA-Z0-9]+)(?:Connection|Edge|Payload|Input)\z/

    attr_reader :environment, :target, :preview_environment

    def initialize(target, environment: GitHub.runtime.current)
      @target      = target
      @environment = environment.to_sym
      @preview_environment = @environment
    end

    def call(member, context)
      context ||= Hash.new

      if member.is_a?(Class) && AUTO_GENERATED_TYPE_PATTERN.match(member.graphql_name)
        return hidden_auto_generated_type?(member, context)
      end

      hidden?(member, context)
    end

    protected

    def hidden?(member, _context)
      if member.respond_to?(:visibility_for) && (vis = member.visibility_for(environment))
        !vis.include?(target)
      else
        false
      end
    end

    private

    def hidden_auto_generated_type?(type, context)
      # Handle Mutation Payloads and Inputs
      if type.respond_to?(:mutation) && type.mutation
        base_type = type.mutation
      # Handle Connection Types
      elsif type.graphql_name.include?("Connection") && (edge_field = type.get_field("edges"))
        edge_type = edge_field.type.unwrap
        base_type = edge_type.get_field("node").type.unwrap
      # Handle Edge Types
      elsif type.graphql_name.include?("Edge") && (node_field = type.get_field("node"))
        base_type = node_field.type.unwrap
      else
        base_type = type
      end

      hidden?(type, context) || hidden?(base_type, context)
    end
  end
end
