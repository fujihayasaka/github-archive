# typed: false
# frozen_string_literal: true

module Platform
  module UserErrors
    module VerifyPath
      module_function

      def verify_user_errors_and_scrub_invalid(result, mutation, ctx)
        ctx[:invalid_user_errors] ||= Set.new
        field_name = mutation.graphql_name.camelize(:lower)
        arguments = mutation.real_arguments

        result.fetch(:errors).map do |client_error|
          path = if client_error.respond_to?(:path)
            client_error.path
          else
            client_error[:path]
          end
          if !valid_client_error_path?(path, arguments)
            # rubocop:disable GitHub/UsePlatformErrors
            raise Platform::UserErrors::InvalidPathError.new(field_name, client_error) if raise_on_invalid_path?
            # rubocop:enable GitHub/UsePlatformErrors
            ctx[:invalid_user_errors].add("`#{field_name}` returned an invalid error path `#{client_error[:path].join('.')}`.")
            client_error[:path] = nil
          end

          client_error
        end

        result
      rescue KeyError
        raise Platform::Errors::Internal, "Mutation.#{field_name}'s return hash must include `:errors`, but it only included: #{result.keys}"
      end

      def valid_client_error_path?(client_error_path, argument_definitions)
        return true if client_error_path.nil? || client_error_path.length == 0

        current_path = client_error_path.first
        remaining_path = client_error_path[1..-1]

        case argument_definitions
        when Hash
          return false unless argument_definitions.key?(current_path)
          valid_client_error_path?(remaining_path, argument_definitions[current_path].type)
        when Class
          if argument_definitions < GraphQL::Schema::InputObject
            valid_client_error_path?(client_error_path, argument_definitions.arguments)
          end
        when GraphQL::Schema::NonNull
          valid_client_error_path?(client_error_path, argument_definitions.of_type)
        when GraphQL::Schema::List
          # if you hit this line, you need to remember to provide a specific index in the `path`
          return false if (current_path =~ /\A\d+\Z/).nil?
          return true if remaining_path.length == 0 && argument_definitions.unwrap.kind.scalar?
          return false if remaining_path.length == 0
          valid_client_error_path?(remaining_path, argument_definitions.of_type)
        end
      end

      # Crash in test/dev so that we can fix the code to return the right error path
      def raise_on_invalid_path?
        Rails.env.test? || Rails.env.development?
      end
    end
  end
end
