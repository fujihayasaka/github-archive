# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class InvalidEnumMemberError < OpenApi::Validation::SchemaError
      code :invalid_enum_member

      def public_message
        "`#{data}` is not a possible value. Must be one of the following: #{object.enum.join(', ')}."
      end

      def developer_message
        <<~ERR
        The request failed because an invalid enum value was specified.

        #{ public_message }

        To fix this:
        - Change the enum type to include the value found here
        - Update the code so that it uses a value that the enum contains
        ERR
      end
    end
  end
end
