# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Query
      extend T::Helpers

      module ClassMethods
        extend T::Helpers
        abstract!

        include Kernel

        sig { abstract.returns(String) }
        def content_type; end

        sig { abstract.params(query_params: T::Hash[Symbol, T.untyped]).returns(T.nilable(::Contentful::Array)) }
        def contentful_request(query_params); end

        # Valid values for fields passed in to query.
        FieldValue = T.type_alias do
          T.any(
            String, # For matching a specific value, e.g. fields: { slug: "/some/slug" }
            T::Boolean, # Same as above, just for booleans, e.g. fields: { published: true }
            T::Array[String], # Match against mulitiple options. Same as using `in` below. e.g. fields: { title: ["title", "another title"] }
            T::Hash[Symbol, T.any( # used for query operators
              T.untyped, # Use an operator from the Contentful API, e.g. fields: { published_at: { gte: Date.today } }
              T::Array[String], # For operators that take multiple options, e.g. fields: { type: { in: ["event", "other event"] } } (same as just passing the array value)
            )]
          )
        end
        SelectOptions = T.type_alias { T.any(String, Symbol, T::Array[Symbol]) }

        sig do
          params(
            fields: T::Hash[Symbol, FieldValue],
            select: T.nilable(SelectOptions),
            camelize_fields: T::Boolean,
            params: T.nilable(T.anything)
          ).returns(T.any(::Contentful::Array, []))
        end
        def query(fields: {}, select: nil, camelize_fields: true, **params)
          query_params = {
            content_type: content_type,
            select: build_select_clause(select, camelize_fields),
            **build_fields_query(fields, camelize_fields),
            **params,
          }.compact

          contentful_request(query_params) || []
        end

        private

        sig { params(select_parameters: T.nilable(SelectOptions), camelize_fields: T::Boolean).returns(T.nilable(String)) }
        def build_select_clause(select_parameters, camelize_fields)
          return if select_parameters.nil?

          case select_parameters
          when Array, Symbol
            Array(select_parameters).map do |field|
              field = field.to_s == "fields" ? field.to_s : "fields.#{field}"
              field = field.to_s.camelize(:lower) if camelize_fields
              field
            end.join(",")
          when String then select_parameters
          end
        end

        sig { params(fields: T::Hash[Symbol, FieldValue], camelize_fields: T::Boolean).returns(T::Hash[String, T.untyped]) }
        def build_fields_query(fields, camelize_fields)
          fields_query = fields.inject({}) do |query_params, (field, value)|
            query_params.merge(field_query_param(field, value))
          end

          fields_query.transform_keys! { |key| key.camelize(:lower) } if camelize_fields
          fields_query
        end

        sig { params(field: Symbol, value: FieldValue).returns(T::Hash[String, T.untyped]) }
        def field_query_param(field, value)
          case value
          when Array then { "fields.#{field}[in]" => value.join(",") }
          when Hash
            value.map do |operator, value|
              ["fields.#{field}[#{operator}]", Array(value).join(",")]
            end.to_h
          else { "fields.#{field}" => value }
          end
        end
      end

      mixes_in_class_methods(ClassMethods)
    end
  end
end
