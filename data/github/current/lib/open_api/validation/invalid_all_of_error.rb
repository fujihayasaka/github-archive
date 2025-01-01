# typed: false
# frozen_string_literal: true

module OpenApi
  module Validation
    class InvalidAllOfError < OpenApi::Validation::SchemaError
      code :invalid_all_of

      def initialize(*args, results:, **kwargs)
        super(*args, **kwargs)
        @results = results
      end

      def public_message
        @sub_errors.map { |e| e.public_message }.join(" ")
      end

      def developer_message
        valid_count = @results.count(&:valid?)
        errors_string = render_sub_errors(@results)

        <<~ERR
        `#{description_pointer}` expected all of the `allOf:` options to match, but only #{valid_count} option#{valid_count == 1 ? "" : "s"} matched. To fix this, either:

        - Update the data so that exactly all of the schemas are valid (see errors below)
        - In the schema, switch `allOf:` for `anyOf:` (if one or more should match) or `oneOf:` (if exactly one should match)

        Data:

        #{data.inspect}

        Errors:
        #{errors_string}
        ERR
      end
    end
  end
end
