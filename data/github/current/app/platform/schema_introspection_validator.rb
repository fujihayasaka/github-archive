# typed: true
# frozen_string_literal: true

module Platform
  # Run some correctness checks on an introspection response.
  # Some of this is built in to GraphQL-Ruby, but since we do a lot of dynamic filtering,
  # It's good to have a reality check on our API responses.
  class SchemaIntrospectionValidator
    # Inspect the JSON from a GraphQL schema and raise `Platform::Errors::Internal` if anything seems wrong.
    def self.validate!(introspection_json, internal:)
      self.new(introspection_json, internal: internal).validate!
      true
    end

    def initialize(introspection_json, internal:)
      @introspection_json = introspection_json
      @internal = internal
    end

    def validate!
      types = @introspection_json["__schema"]["types"]
      types_by_name = Hash.new { |h, k| h[k] = types.find { |t| t["name"] == k } }
      types.each do |type_json|
        name = type_json["name"]
        if name.blank?
          raise Platform::Errors::Internal, "Unnamed type: #{type_json}"
        end

        case type_json["kind"]
        when "INTERFACE"
          if type_json["fields"].empty?
            raise Platform::Errors::Internal, "Interface #{name} must have fields, but it doesn't have any.#{public_schema_message("Maybe they're all internal or under_development, in which case, the interface should have the same visibility.")} (#{type_json.inspect})"
          end
        when "OBJECT"
          if type_json["fields"].empty?
            raise Platform::Errors::Internal, "Object #{name} must have fields, but it doesn't have any.#{public_schema_message("Maybe they're all internal or under_development, in which case the type should be hidden in the same way.")} (#{type_json.inspect})"
          end

          type_json["interfaces"].each do |interface_impl|
            interface_name = interface_impl["name"]
            interface_json = types_by_name[interface_name]
            if interface_json.blank?
              raise Platform::Errors::Internal, "Object #{name} implements #{interface_name}, but that interface wasn't found in `__schema { types }`.#{public_schema_message("Maybe it's an internal interface?")}"
            end

            interface_json["fields"].each do |interface_field_json|
              implementation_field = type_json["fields"].find { |f| f["name"] == interface_field_json["name"] }
              if implementation_field.blank?
                raise Platform::Errors::Internal, "Object #{name}'s impementation of #{interface_name}.#{interface_field_json["name"]} wasn't found, does it implement that field?#{public_schema_message("Or is its implementation internal-only?")}"
              end

              if !compatible_return_type?(interface_field_json["type"], implementation_field["type"])
                raise Platform::Errors::Internal, "Object #{name}'s implementation of #{interface_name}.#{interface_field_json["name"]} has an invalid return type (interface: #{interface_field_json["type"]}, object: #{implementation_field["type"]})"
              end
            end
          end
        when "UNION"
          if type_json["possibleTypes"].empty?
            raise Platform::Errors::Internal, "Union #{name} must have possible types, but it doesn't have any#{public_schema_message("or maybe they're all internal?")} (#{type_json.inspect})"
          end
        when "ENUM"
          if type_json["enumValues"].empty?
            raise Platform::Errors::Internal, "Enum #{name} must have values, but it doesn't have any#{public_schema_message("or maybe they're all internal?")}. (#{type_json.inspect})"
          end
        when "INPUT_OBJECT"
          if type_json["inputFields"].empty?
            raise Platform::Errors::Internal, "Input Object #{name} must have arguments, but it doesn't have any#{public_schema_message("or maybe they're all internal?")} (#{type_json.inspect})"
          end
        when "SCALAR"
          # No checks
        else
          raise Platform::Errors::Internal, "Unknown GraphQL type kind: #{type_json["kind"]} (in: #{type_json.inspect})"
        end
      end
    end

    private

    # Check if the return type of a object's field is a valid implementation
    # of the interface's return type.
    #
    # It's tricky because `something: String!` is a valid implementation of `something: String`
    # (it's ok to have a non-null field when the interface is nullable),
    # but the opposite is not true.
    # That is, `s: String` is _not_ a valid implementation of `s: String!`.
    def compatible_return_type?(interface_field_type, object_field_type)
      if interface_field_type == object_field_type
        true
      elsif object_field_type["kind"] == "NON_NULL"
        compatible_return_type?(interface_field_type, object_field_type["ofType"])
      elsif interface_field_type["kind"] == "LIST" && object_field_type["kind"] == "LIST"
        compatible_return_type?(interface_field_type["ofType"], object_field_type["ofType"])
      else
        false
      end
    end

    def public_schema_message(message)
      if @internal
        # Don't show the message, it doesn't apply here
        ""
      else
        " (#{message})"
      end
    end
  end
end
