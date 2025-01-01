# typed: false
# frozen_string_literal: true

#
module GitHub
  class Sendgrid
    class Error < StandardError
      attr_reader :method_called, :status_code, :error_message

      def initialize(error, method_called)
        @method_called = method_called
        if error.is_a?(Faraday::Error)
          @status_code = 500
          @error_message = error.status.to_s
        elsif error.is_a?(Faraday::Response)
          @status_code = error.status
          @error_message = error.status.to_s
        else
          raise ArgumentError, "error must be a Faraday error or response"
        end
        instrument_status_code
        super(@error_message)
      end

      def failbot_context
        {
          app: "github-external-request",
          sendgrid_response_code: @status_code,
          sendgrid_error_message: @error_message,
        }
      end

      private

      def instrument_status_code
        GitHub.dogstats.increment "sendgrid.error"
        GitHub.dogstats.increment "sendgrid.#{method_called}.error"
        GitHub.dogstats.increment "sendgrid.#{method_called}.error.#{status_code}"
      end
    end
  end
end
