# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Localization
  module AzureTranslations
    class TranslationService
      class HttpError < Error
        attr_reader :http_status
        attr_reader :original_error

        def initialize(error)
          @original_error = error
          @http_status = 400
          set_backtrace(error.backtrace)

          message = error.message

          if error.respond_to?(:response)
            if error.response.is_a?(Hash)
              @http_status = error.response[:status] || @http_status
            end

            if error.response.respond_to?(:body)
              @http_status = error.response.status
              parsed_error = JSON.parse(error.response.body, symbolize_names: true)
              message = parsed_error.dig(:error, :message) || message
            end
          end

          super(message)
        end
      end
    end
  end
end
