# typed: false
# frozen_string_literal: true

module OpenApi
  module Validation
    class InvalidOneOfError < OpenApi::Validation::SchemaError
      code :invalid_one_of

      def initialize(*args, results:, **kwargs)
        super(*args, **kwargs)
        @results = results
        @valid_count = @results.count(&:valid?)
      end

      def public_message
        if data_matches_no_types?
          # Here we try to return a friendly error message given a complex oneOf schema error
          # When all the possible schemas are of different types, and the data matches none of them
          # We can instruct the user to send one of the valid types of data.
          "Data type must be one of: #{@results.map { |r| r.errors.first.object.type }.join(', ')}."
        elsif matching_type_errors.size == 1
          # When the data only matches one of the potential schema types, we can guess that the user
          # is trying to provide valid data for that particular schema, so we return these sub errors.
          matching_type_errors.first.errors.map(&:public_message).join('\n')
        else
          if @valid_count == 0
            "data matches no possible input. See `documentation_url`."
          else
            # Complex oneOfs should be avoided. Crafting a helpful error message
            # is incredibly hard here.
            "data matches more than one possible input. See `documentation_url`."
          end
        end
      end

      def developer_message
        errors_string = render_sub_errors(@results)

        <<~ERR
        `#{description_pointer}` expected _exactly one_ of the `oneOf:` options to match, but #{@valid_count} options matched. To fix this, either:

        - Update the data so that exactly one of the schemas is valid (see errors below)
        - Update the schemas so that exactly one matches the given data
        - In the schema, switch `oneOf:` for `allOf:` (if all should match) or `anyOf:` (if one or more should match)

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
