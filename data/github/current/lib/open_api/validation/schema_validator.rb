# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class SchemaValidator
      attr_accessor :errors

      # @param schema [OpenApi::Description::Schema]
      def initialize(
        schema,
        description_path,
        coerce_values: false,
        allow_skipping_validation: false,
        disable_additional_properties: false,
        parent_type: nil
      )
        @schema = schema
        @description_path = description_path
        @coerce_values = coerce_values
        @allow_skipping_validation = allow_skipping_validation
        @disable_additional_properties = disable_additional_properties
        @parent_type = parent_type
      end

      # Validates data against the schema and return a list of validation errors.
      # @param data [Object]
      # @returns [OpenApi::Validation::ValidationResult]
      def validate(data, data_path: [])
        timer = Timer.start

        errors = []
        validate_data(@schema, data, errors, description_path: @description_path.dup, data_path: data_path)
        result = OpenApi::Validation::ValidationResult.new(errors)

        timer.stop

        GitHub.dogstats.distribution("openapi.validation.validate_schema", timer.elapsed_ms, tags: ["skip_validation:#{@schema.skip_validation?}"])

        result
      end

      private

      # Validates user data against an OpenAPI schema
      #
      # @param schema [OpenApi::Description::Schema] the schema we're validating against
      # @param data [any] the data to validate
      # @param errors [Array<OpenApi::Description::OpenApi::Validation::SchemaError>] the validation errors we've accumulated
      # @param description_path [Array<String>] A JSON Path to the current OpenAPI document location
      # @returns [void]
      def validate_data(schema, data, errors, description_path:, data_path:)
        return if schema.skip_validation? && @allow_skipping_validation

        # General Validation
        if data.nil?
          # In theory, we wouldnt want to return right away as the validation could still fail against
          # sub schemas. However we currently use nullable in a bit of a different way.
          # See https://github.com/OAI/OpenAPI-Specification/issues/1368 for more details.
          validate_nullable(schema, data, errors, description_path: description_path, data_path: data_path)
          return
        end

        # General Validations
        validate_type(schema, data, errors, description_path: description_path, data_path: data_path)
        validate_one_of(schema, data, errors, description_path: description_path, data_path: data_path)
        validate_any_of(schema, data, errors, description_path: description_path, data_path: data_path)
        validate_all_of(schema, data, errors, description_path: description_path, data_path: data_path)
        validate_not(schema, data, errors, description_path: description_path, data_path: data_path)

        # Object Validations
        if data.is_a?(Hash)
          validate_properties(schema, data, errors, description_path: description_path, data_path: data_path)
          validate_required(schema, data, errors, description_path: description_path, data_path: data_path)
          validate_max_properties(schema, data, errors, description_path: description_path, data_path: data_path)
          validate_additional_properties(schema, data, errors, description_path: description_path, data_path: data_path)
        end

        # Array Validations
        if data.is_a?(Array)
          validate_items(schema, data, errors, description_path: description_path, data_path: data_path)
        end

        # validation: string
        if data.is_a?(String)
          validate_max_length(schema, data, errors, description_path: description_path, data_path: data_path)
          validate_min_length(schema, data, errors, description_path: description_path, data_path: data_path)
          validate_pattern(schema, data, errors, description_path: description_path, data_path: data_path)
          validate_format(schema, data, errors, description_path: description_path, data_path: data_path)
          validate_enum(schema, data, errors, description_path: description_path, data_path: data_path)
        end

        if data.is_a?(Integer)
          validate_min_max(schema, data, errors, description_path: description_path, data_path: data_path)
        end
      end

      def validate_format(schema, data, errors, description_path:, data_path:)
        case schema.format
        when nil
          # do nothing
        when "date-time"
          begin
            Time.iso8601(data)
          rescue ArgumentError
            message = "#{data.inspect} is not a valid date-time"
            errors << OpenApi::Validation::InvalidFormatError.new(schema, data, description_path: description_path, data_path: data_path)
          end
        when "date"
          begin
            Date.iso8601(data)
          rescue ArgumentError
            message = "#{data.inspect} is not a valid date"
            errors << OpenApi::Validation::InvalidFormatError.new(schema, data, description_path: description_path, data_path: data_path)
          end
        when "uri"
          begin
            URI.parse(data)
          rescue URI::InvalidURIError
            message = "#{data.inspect} is not a valid uri"
            errors << OpenApi::Validation::InvalidFormatError.new(schema, data, description_path: description_path, data_path: data_path)
          end
        when "uri-template"
          begin
            Addressable::URI.parse(data)
          rescue Addressable::URI::InvalidURIError
            message = "#{data.inspect} is not a valid uri template"
            errors << OpenApi::Validation::InvalidFormatError.new(schema, data, description_path: description_path, data_path: data_path)
          end
        when "int32"
          if data.to_i.bit_length > 31 # signed 32-bit integer
            message = "#{data.inspect} has a value that is too large for a 32-bit signed integer"
            errors << OpenApi::Validation::InvalidFormatError.new(schema, data, description_path: description_path, data_path: data_path)
          end
        when "int64"
          if data.to_i.bit_length > 63 # signed 64-bit integer
            message = "#{data.inspect} has a value that is too large for a 64-bit signed integer"
            errors << OpenApi::Validation::InvalidFormatError.new(schema, data, description_path: description_path, data_path: data_path)
          end
        when "email"
          # pass: emails are too hard to validate.
        else
          raise "`format: #{schema.format.inspect}` isn't implemented yet; either remove it or implement it in #{self.class}##{__method__}"
        end
      end

      def validate_nullable(schema, data, errors, description_path:, data_path:)
        return if !data.nil?

        if !schema.nullable?
          errors << OpenApi::Validation::InvalidNullableError.new(
            schema,
            data,
            description_path: description_path,
            data_path: data_path
          )
        end
      end

      def validate_type(schema, data, errors, description_path:, data_path:)
        return if schema.type.nil?

        if @coerce_values
          data = coerce_integer(data) if schema.type == "integer"
          data = coerce_boolean(data) if schema.type == "boolean"
        end

        if schema.ruby_types.none? { |t| data.is_a?(t) }
          errors << OpenApi::Validation::InvalidTypeError.new(schema, data, description_path: description_path, data_path: data_path)
        end
      end

      def validate_one_of(schema, data, errors, description_path:, data_path:)
        return if schema.one_of.nil?

        results = schema.one_of.map do |sub_schema|
          validator = self.class.new(sub_schema, description_path, disable_additional_properties: @disable_additional_properties)
          validator.validate(data, data_path: data_path)
        end

        valid = results.count(&:valid?)

        return if valid == 1

        errors << OpenApi::Validation::InvalidOneOfError.new(
          schema,
          data,
          results: results,
          sub_errors: results.flat_map(&:errors),
          description_path: description_path,
          data_path: data_path,
        )
      end

      def validate_any_of(schema, data, errors, description_path:, data_path:)
        return if schema.any_of.nil?

        results = schema.any_of.map do |sub_schema|
          validator = self.class.new(sub_schema, description_path, disable_additional_properties: @disable_additional_properties)
          validator.validate(data, data_path: data_path)
        end

        if results.none?(&:valid?)
          sub_errors = results.flat_map(&:errors)
          errors << OpenApi::Validation::InvalidAnyOfError.new(
            schema,
            data,
            results: results,
            sub_errors: sub_errors,
            description_path: description_path,
            data_path: data_path,

          )
        end
      end

      def validate_all_of(schema, data, errors, description_path:, data_path:)
        return if schema.all_of.nil?

        results = schema.all_of.map do |sub_schema|
          validator = self.class.new(
            sub_schema,
            description_path,
            parent_type: :all_of,
            disable_additional_properties: @disable_additional_properties
          )
          validator.validate(data, data_path: data_path)
        end

        if !results.all?(&:valid?)
          sub_errors = results.flat_map(&:errors)
          errors << OpenApi::Validation::InvalidAllOfError.new(
            schema,
            data,
            results: results,
            sub_errors: sub_errors,
            description_path: description_path,
            data_path: data_path,
          )
        end
      end

      def validate_not(schema, _, _, _)
        return if schema.not.nil?

        raise NotImplementedError, "The not attribute is not supported by our validator yet."
      end

      def validate_properties(schema, data, errors, description_path:, data_path:)
        return if schema.properties.empty?

        schema.properties.each do |key, subschema|
          # We'll validate these in validate_required
          next if !data.key?(key)

          validate_data(subschema, data[key], errors, description_path: description_path + [key], data_path: data_path + [key])
        end
      end

      def validate_required(schema, data, errors, description_path:, data_path:)
        return if schema.required.empty?

        missing = schema.required - data.keys

        if missing.any?
          errors << MissingRequiredKeysError.new(
            schema,
            data,
            keys: missing,
            description_path: description_path,
            data_path: data_path,
          )
        end
      end

      def validate_max_properties(schema, data, errors, description_path:, data_path:)
        return true unless schema.max_properties

        if data.keys.size > schema.max_properties
          errors << OpenApi::Validation::TooManyPropertiesError.new(schema, data, description_path: description_path, data_path: data_path)
        end
      end

      def validate_additional_properties(schema, data, errors, description_path:, data_path:)
        return if schema.additional_properties == true && !override_additional_properties?(schema)

        if schema.additional_properties.is_a?(OpenApi::Description::Schema)
          extra = data.keys - schema.properties.keys

          extra.each do |key|
            validator = self.class.new(
              schema.additional_properties,
              description_path + [key],
              disable_additional_properties: @disable_additional_properties
            )
            res = validator.validate(data[key], data_path: data_path + [key])
            errors.push(*res.errors)
          end
        else
          extra = data.keys - schema.properties.keys

          if !extra.empty?
            errors << OpenApi::Validation::InvalidAdditionalPropertiesError.new(
              schema,
              data,
              description_path: description_path,
              data_path: data_path,
              additional_properties: extra.sort
            )
          end
        end
      end

      def override_additional_properties?(schema)
        # We only validate additional properties if
        # 1. no additionalProperties has been explicitely set
        # 2. The current schema isn't allOf, anyOf and friends
        # 3. The parent schema isn't an allOf
        # 4. The validator is running with disable_additional_properties: true
        schema.raw_additional_properties.nil? &&
          !schema.has_sub_schema? &&
          @parent_type != :all_of &&
          @disable_additional_properties
      end

      def validate_enum(schema, data, errors, description_path:, data_path:)
        return unless schema.enum

        # In some cases, we don't want to enforce an enum value, and instead want to gracefully return.
        # In such cases, the enum really is beneficial for documentation purposes.  Many of our search endpoints, for example,
        # will return 200 even when provided with a value not included in a the enum schema for a query parameter.
        return if schema.graceful_enum?

        valid = if schema.case_insensitive_enum?
          schema.enum.map(&:downcase).include?(data.downcase)
        else
          schema.enum.include?(data)
        end

        if !valid
          errors << OpenApi::Validation::InvalidEnumMemberError.new(
            schema,
            data,
            description_path: description_path,
            data_path: data_path
          )
        end
      end

      def validate_items(schema, data, errors, description_path:, data_path:)
        if schema.items
          data.each_with_index do |value, i|
            validator = self.class.new(
              schema.items,
              description_path + ["items"],
              disable_additional_properties: @disable_additional_properties
            )
            result = validator.validate(value, data_path: data_path + [i])
            errors.push(*result.errors)
          end
        end

        if schema.max_items && data.size > schema.max_items
          errors << OpenApi::Validation::MaxItemsError.new(schema, data, description_path: description_path, data_path: data_path)
        end

        if schema.min_items && data.size < schema.min_items
          errors << OpenApi::Validation::MinItemsError.new(schema, data, description_path: description_path, data_path: data_path)
        end
      end

      def validate_min_max(schema, data, errors, description_path:, data_path:)
        if schema.minimum && data < schema.minimum
          errors << OpenApi::Validation::MinNumberError.new(schema, data, description_path: description_path, data_path: data_path)
        end

        if schema.maximum && data > schema.maximum
          errors << OpenApi::Validation::MaxNumberError.new(schema, data, description_path: description_path, data_path: data_path)
        end
      end

      def validate_max_length(schema, data, errors, description_path:, data_path:)
        return unless schema.max_length

        if data.length > schema.max_length
          errors << OpenApi::Validation::MaxStringLengthError.new(schema, data, description_path: description_path, data_path: data_path)
        end
      end

      def validate_min_length(schema, data, errors, description_path:, data_path:)
        return unless schema.min_length

        if data.length < schema.min_length
          errors << OpenApi::Validation::MinStringLengthError.new(schema, data, description_path: description_path, data_path: data_path)
        end
      end

      def validate_pattern(schema, data, errors, description_path:, data_path:)
        return unless schema.pattern

        if data !~ schema.pattern
          errors << OpenApi::Validation::InvalidPatternError.new(schema, data, description_path: description_path, data_path: data_path)
        end
      end

      def coerce_boolean(data)
        coerced = ActiveRecord::Type::Boolean.new.deserialize(data)

        if coerced == true || coerced == false
          coerced
        else
          data
        end
      end

      def coerce_integer(data)
        return data if data.kind_of?(Integer)

        begin
          Integer(data)
        rescue ArgumentError => e
          data
        end
      end
    end
  end
end
