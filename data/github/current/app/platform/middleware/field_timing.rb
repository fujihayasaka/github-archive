# typed: true
# frozen_string_literal: true

module Platform
  module Middleware
    class FieldTiming
      def self.call(parent_type, parent_object, field_definition, field_args, query_context)
        performance_data = query_context[:performance_data]

        previous_type = performance_data[:current_type]
        previous_field = performance_data[:current_field]
        previous_field_tag = performance_data[:current_field_tag]
        previous_field_key = performance_data[:current_field_key]

        # Profiling extension key
        field_key = "#{parent_type}:#{field_definition.name}"
        # Datadog tag
        field_tag = "field:#{field_key.downcase}"

        performance_data[:current_type] = parent_type
        performance_data[:current_field] = field_definition
        performance_data[:current_field_tag] = field_tag
        performance_data[:current_field_key] = field_key
        yield
      ensure
        performance_data[:current_type] = previous_type
        performance_data[:current_field] = previous_field
        performance_data[:current_field_tag] = previous_field_tag
        performance_data[:current_field_key] = previous_field_key
      end
    end
  end
end
