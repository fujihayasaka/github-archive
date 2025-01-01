# typed: false
# frozen_string_literal: true

module OpenApi
  module Validation
    class InvalidAnyOfError < OpenApi::Validation::SchemaError
      code :invalid_any_of

      def initialize(*args, results:, **kwargs)
        super(*args, **kwargs)
        @results = results
      end

      def public_message
        if data_matches_no_types?
          # Here we try to return a friendly error message given a complex oneOf schema error
          # When all the possible schemas are of different types, and the data matches none of them
          # We can instruct the user to send one of the valid types of data.
          "data type must be one of: #{@results.map { |r| r.errors.first.object.type }.join(', ')}."
        elsif matching_type_errors.size == 1
          # When the data only matches one of the potential schema types, we can guess that the user
          # is trying to provide valid data for that particular schema, so we return these sub errors.
          matching_type_errors.first.errors.map(&:public_message).join('\n')
        else
          "data matches no possible input. See `documentation_url`."
        end
      end

      def developer_message
        errors_string = render_sub_errors(@results)

        <<~ERR
        The schema expected _one or more_ of the `anyOf:` options to match, but none did. To fix this, either:

        - Update the data so that at least one of the schemas is valid (see errors below)
        - Update the schemas so that one or more matches the given data

        Data:

        #{data.inspect}

        Errors:
        #{errors_string}
        ERR
      end

      private

      def data_matches_no_types?
        @results.all? { |r| r.errors.size == 1 && r.errors.first.is_a?(InvalidTypeError) }
      end

      def matching_type_errors
        @results.reject { |r| r.errors.size == 1 && r.errors.first.is_a?(InvalidTypeError) }
      end
    end
  end
end
