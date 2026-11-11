# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module Errors
    # Public: Error raised when the namespace is not supported
    class InvalidNamespace < StandardError; end

    # Public: Error raised when definition creation limit is reached
    class DefinitionLimitReachedError < StandardError; end

    # Public: Error raised when user attempts to delete an allow value in use
    class DefinitionDeletionAllowValueInUseError < StandardError; end

    # Public: Error raised when the definition is invalid
    class InvalidDefinition < StandardError; end

    # Public: Error raised when the property is not editable by the current actor
    class EditPropertyPermissionError < StandardError; end

    # Public: Error returned when property does not match the schema
    class SchemaValidationError < StandardError
      sig { returns(String) }
      attr_reader :property_name, :error_message

      sig { params(property_name: String, error_message: String).void }
      def initialize(property_name, error_message)
        @property_name = T.let(property_name, String)
        @error_message = T.let(error_message, String)

        super(error_message)
      end
    end

    # Public: Error raised when the condition syntax is invalid
    class ParserError < StandardError; end

    class PropertyValidationError < StandardError
      sig { returns(T::Array[SchemaValidationError]) }
      attr_reader :validation_errors

      sig { params(validation_errors: T::Array[SchemaValidationError]).void }
      def initialize(validation_errors)
        @validation_errors = T.let(validation_errors, T::Array[SchemaValidationError])
        super(validation_errors.map(&:error_message).join("\n"))
      end
    end

    # Public: Represents a single validation failure for a definition attribute.
    # Used as the return value of CustomPropertiesValidator#validate_definition_* methods.
    #
    # field   - the Symbol name of the invalid attribute (e.g. :regex, :allowed_values)
    # message - a predicate string describing the failure (e.g. "must be a valid regex pattern")
    class DefinitionValidationError < StandardError
      sig { returns(Symbol) }
      attr_reader :field

      sig { params(field: Symbol, message: String).void }
      def initialize(field, message)
        @field = T.let(field, Symbol)
        super(message)
      end
    end
  end
end
