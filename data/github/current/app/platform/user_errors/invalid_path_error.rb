# typed: true
# frozen_string_literal: true

module Platform
  module UserErrors
    class InvalidPathError < ::StandardError
      def initialize(field_name, invalid_user_error)
        @field_name = field_name
        @invalid_user_error = invalid_user_error
      end

      def message
        <<-MESSAGE
        The field `#{@field_name}` would have returned an invalid `path` for the user error.

        Invalid user error: #{@invalid_user_error}.

        The `path` field of each client error must map to a mutation argument.

        For example, if you have a mutation that accepts a `email: String!` argument and there is a validation error
        for that argument, the path would be `["input", "email"]`.

        Typically, you will receive this error when there is a malformed path. In most cases, this is caused
        by mutation input names not aligning with ActiveRecord attribute names.

        To fix this, consider setting the `translate` kwarg in `mutation_errors_for_model` to convert
        the broken path into a fixed one.

        Need more help? Head into #graphql in Slack.
        MESSAGE
      end
    end
  end
end
