# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      class GraphQlGracefulDegradationExtension < GraphQL::Schema::FieldExtension
        include GitHub::ResilienceMixin

        def resolve(arguments:, object:, context:)
          result = yield(object, arguments)

          return result unless should_handle_async_error?(result, context[:viewer])

          with_async_database_error_fallback(result, fallback: -> {
            raise Errors::Execution.new("SERVER_ERROR", "An unexpected error has occurred.")
          })
        end

        private

        def should_handle_async_error?(result, viewer)
          return false unless result.is_a?(Promise)
          return false unless viewer.present?

          if viewer.respond_to?(:feature_enabled?)
            viewer.feature_enabled?(:graphql_graceful_degredation)
          else
            GitHub.flipper[:graphql_graceful_degredation].enabled?(viewer)
          end
        end
      end
    end
  end
end
