# typed: true
# frozen_string_literal: true


module Platform
  module RuntimeErrors
    def self.included(base)
      # ORDER MATTERS! The first rescue_from block that matches the error will be used.
      # GraphQL::ExecutionError is the base class for all errors that occur during query execution and are returned to the client.
      # Because we are expecting these errors do noot report them via telemetry.
      base.rescue_from(Errors::Execution) do |exception, _object, _args, _context, _field|
        raise exception  # rubocop:disable GitHub/UsePlatformErrors
      end

      # This is a catch-all for any exceptions that occur during graphql query field resolution.
      # It allows us to report the error with information about which field is currently failing and
      # continue to raise the exception so that the query fails.
      # In the future, we may want to consider a more fine-grained approach to error handling.
      # This catch-all is necessary because graphql-ruby 2.0 removes the current field from the context
      # which are required to correctly report the error.
      base.rescue_from(Exception) do |exception, _object, _args, context, _field|
        Platform.instrument_internal_errors(
          query: context.query,
          query_name: context[:query_name],
        )
        is_development = Rails.env && Rails.env.development?
        Platform.report_internal_errors!(
          exception:,
          report_exceptions_to_failbot: !is_development && !context[:raise_exceptions],
          query: context.query,
          query_name: context[:query_name]
        )
        context[:error_reported] = true
        # always re-raise the exception so that the query fails
        raise exception  # rubocop:disable GitHub/UsePlatformErrors
      end
    end
  end
end
