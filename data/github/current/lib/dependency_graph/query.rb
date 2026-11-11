# typed: true
# frozen_string_literal: true

module DependencyGraph
  class Query
    extend T::Helpers
    abstract!

    def self.default_backend(**args)
      @default_backend ||= ::DependencyGraph::Client.new(query_type: T.must(name).demodulize, **args)
    end

    def initialize(backend: nil)
      @backend = backend || default_backend
    end

    private

    attr_reader :backend

    def default_backend(**args)
      self.class.default_backend(**args)
    end

    def execute_query(graphql_query = query)
      backend.post operation(:query, {
        selections: Array(graphql_query),
      }).to_query_string
    end

    def map_arguments(mapping, arguments)
      arguments.map do |key, value|
        config = mapping.fetch(key)
        argument(config[:arg], casted_value(config[:type], value))
      end
    end

    def casted_value(type, value)
      case type
      when :array
        Array(value)
      when :enum
        enum(value.upcase) if value
      when :enum_array
        value.map { |enum_value| casted_value(:enum, enum_value) }
      else
        value
      end
    end

    def enum(name, options = {})
      GraphQL::Language::Nodes::Enum.new(**{
        name: name.to_s,
      }.merge(options))
    end

    def field(name, options = {})
      if options[:field_alias]
        options[:field_alias] = options[:field_alias].to_s
      end

      GraphQL::Language::Nodes::Field.new(**{
        name: name.to_s,
      }.merge(options))
    end

    def argument(name, value, options = {})
      GraphQL::Language::Nodes::Argument.new(**{
        name: name.to_s,
        value: value,
      }.merge(options))
    end

    def operation(operation_type, options)
      GraphQL::Language::Nodes::OperationDefinition.new(**{
        variables: [],
        operation_type: operation_type.to_s,
      }.merge(options))
    end

    def type_name(name)
      GraphQL::Language::Nodes::TypeName.new(name: name.to_s)
    end

    def inline_fragment(type, options = {})
      GraphQL::Language::Nodes::InlineFragment.new(**{
        type: type,
      }.merge(options))
    end

    sig { abstract.params(options: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
    def query(options = {}); end
  end
end
