# typed: true
# frozen_string_literal: true

module Platform
  module UserErrors
    MUTATION_PAYLOAD_DEPRECATION_MESSAGE = "In preparation for an upcoming change to the way we report mutation errors, non-nullable payload fields are becoming nullable."

    def self.append_legacy_mutation_model_errors_to_context(model, execution_errors)
      message = model.errors.full_messages.join(", ")

      append_legacy_mutation_error_messages_to_context([message], execution_errors)
    end

    def self.append_legacy_mutation_error_messages_to_context(messages, execution_errors)
      return unless Platform::GlobalScope.origin_api?

      messages.each do |message|
        exception = Platform::Errors::Unprocessable.new(message)
        execution_errors.add(exception)
      end

      nil
    end

    def self.mutation_errors_for_model(model, path_prefix: ["input"], translate: {})
      error_names = model.errors.attribute_names

      client_errors = error_names.map do |attribute|
        model.errors[attribute].map do |error_message|
          path_suffix = if attribute == :base
            []
          elsif translate.key?(attribute)
            Array(translate[attribute]).map { |t| t.to_s.camelize(:lower) }
          else
            [attribute.to_s.camelize(:lower)]
          end

          {
            path: (path_prefix + path_suffix).presence,
            message: model.errors.full_message(attribute, error_message),
            short_message: error_message,
            attribute: attribute.to_s,
          }
        end
      end

      client_errors.flatten
    end

    def self.mutation_errors_for_models(models, path_prefix: ["input"], translate: {})
      client_errors = models.map.with_index do |model, index|
        mutation_errors_for_model(model, path_prefix: path_prefix + [index.to_s], translate: translate)
      end

      client_errors.flatten
    end
  end
end
