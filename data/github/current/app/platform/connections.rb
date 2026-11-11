# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    def self.define(type, **options)
      connection_name = if options[:name]
        options[:name]
      elsif type.respond_to?(:graphql_name)
        type.graphql_name
      elsif type.is_a?(Class) && type < GraphQL::Schema::Member
        type.graphql_name
      else
        raise ArgumentError, "Invalid Connection type: #{type} (#{type.ancestors})" # rubocop:disable GitHub/UsePlatformErrors
      end

      existing_const =
        if const_defined?(connection_name, false)
          const_get(connection_name, false)
        end

      unless existing_const.nil? ||
          (existing_const.is_a?(Class) && existing_const < GraphQL::Schema::Member)
        raise TypeError, "Expected #{existing_const.inspect} to be a subclass of GraphQL::Schema::Member" # rubocop:disable GitHub/UsePlatformErrors
      end

      if existing_const
        existing_const
      else
        connection = Class.new(Platform::Connections::Base) do
          edge_type(options[:edge_type] || type.edge_type, node_type: type)
          graphql_name("#{connection_name}Connection")
          total_count_field
          if options[:visibility]
            visibility(options[:visibility])
          elsif type.environment_visibilities
            type.environment_visibilities.each do |env, visibilities|
              visibility(visibilities, environments: [env])
            end
          end
        end
        const_set(connection_name, connection)
      end
    end
  end
end
