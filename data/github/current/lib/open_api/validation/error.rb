# typed: false
# frozen_string_literal: true

module OpenApi
  module Validation
    class Error
      attr_reader :object, :description_path

      # @param object [Object] the OpenAPI object data was validated against
      # @param description_path [Array<String>] a JSON pointer to the OpenAPI object
      def initialize(object, description_path)
        @object = object
        @description_path = description_path
      end

      # JSON Pointer to the OpenAPI object that returned this error
      def description_pointer
        "/#{@description_path.join("/")}"
      end

      def public_error
        public_message
      end

      def developer_error
        "OpenAPI contract error at location #{description_pointer}\n\n#{developer_message}"
      end

      def code
        self.class.code
      end

      def unique_key
        self.class.name + @description_path.to_s
      end

      # Call this configuration method in subclasses to set `@code` in all instances of the class
      # @param new_code [Symbol]
      # @return [Symbol]
      def self.code(new_code = nil)
        if new_code
          @code = new_code
        end
        @code || raise("#{self} must configure `code ...` (Symbol) to identify this error")
      end

      protected

      def public_message
        raise(NotImplementedError, "#{self.class}##{__method__} should return an integrator-friendly message about why the request was invalid and how it can be corrected")
      end

      def developer_message
        raise(NotImplementedError, "#{self.class}##{__method__} should return a Hubber-friendly message about what went wrong and how to fix it")
      end
    end

    class SchemaError < Error
      attr_reader :data, :sub_errors

      def inspect
        "#<#{self.class} @ #{@data_path.join("/")} #{public_message.inspect}>"
      end

      # @param object [Object] the OpenAPI object data was validated against
      # @param data [Object] the data we validated
      # @param description_path [Array<String>] a JSON pointer to the OpenAPI object
      # @param data_path [Array<String>] a JSON pointer to the data that failed validation
      # @param sub_errors [Array<ValidationErrors>] more precise errors in the case of sub schema validation.
      def initialize(object, data, description_path: [], data_path: [], sub_errors: [])
        @sub_errors = sub_errors
        @data = data
        @data_path = data_path
        super(object, description_path)
      end

      def data_pointer
        "/#{@data_path.join("/")}"
      end

      def public_error
        if @data_path.size > 0
          "Invalid property #{data_pointer}: #{public_message}"
        else
          "Invalid input: #{public_message}"
        end
      end

      private

      # @param results [Array<ValidationResult>]
      # @return [String]
      def render_sub_errors(results)
        errors_string = "".dup

        results.each_with_index do |result, idx|
          errors_string << "\nOption #{idx + 1} errors:"
          if result.errors.empty?
            errors_string << "(no errors -- valid)"
          else
            result.errors.each do |err|
              errors_string << "\n" + err.developer_message.indent(4).sub("    ", "  - ")
            end
          end
        end

        errors_string
      end
    end
  end
end
