# typed: strict
# frozen_string_literal: true

module AdvisoryDB
  module Ecosystems
    # A representation of an ecosystem supported by the advisory database
    class Ecosystem

      VALID_NAME_REGEX = T.let(/\A[a-zA-Z][_a-zA-Z0-9]{1,19}\z/.freeze, Regexp)

      sig { returns(String) }
      attr_reader :name

      sig { returns(String) }
      attr_reader :description

      sig { returns(String) }
      attr_reader :label

      sig { returns(String) }
      attr_reader :purl_type

      # Instantiate a new supported ecosystem
      #
      # @param name [String] The ecosystem name as it is persisted in the database. Required.
      # @param description [String] A user-facing description of the field used in our API documentation. Required.
      # @param label [String] A human-readable label for the ecosystem, if different from `name`. Optional.
      # @param is_public [Boolean] Is this ecosystem available via our API? Defaults to `true`.
      # @param purl_type [String] The ecosystem PURL type as defined by the PURL specification, if different from `name`. Optional. See https://github.com/package-url/purl-spec/blob/master/PURL-TYPES.rst
      sig do
        params(
          name: String,
          description: String,
          label: T.nilable(String),
          purl_type: T.nilable(String),
          is_public: T::Boolean,
        ).void
      end
      def initialize(name:, description:, label: nil, purl_type: nil, is_public: true)
        validate_name!(name)

        @name = name
        @description = description
        @label = T.let(label || name, String)
        @purl_type = T.let(purl_type || name, String)
        @is_public = is_public
      end

      sig { returns(T::Boolean) }
      def public?
        @is_public
      end

      private

      # Name requirements:
      # - max length of an ecosystem name is 20 characters due to database
      #   field length restrictions
      # - min length of an ecosystem name is 2 characters (arbitrarily chosen)
      # - characters restricted to alphanumeric and underscore due to GraphQL
      #   name validation
      # - must start with a letter
      sig { params(name: String).void }
      def validate_name!(name)
        error = T.let(if name.length < 2 || name.length > 20
                        "must be 2 - 20 characters in length"
                      elsif !(name =~ VALID_NAME_REGEX)
                        "must match format #{VALID_NAME_REGEX}"
                      end, T.nilable(String))

        return if error.nil?

        raise ArgumentError, "Ecosystem name #{error}"
      end
    end
  end
end
