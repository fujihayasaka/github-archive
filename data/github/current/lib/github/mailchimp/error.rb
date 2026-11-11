# typed: true
# frozen_string_literal: true

module GitHub
  class Mailchimp
    class Error < MailchimpError
      # Explicitly specify which method is raising
      # this exception in order to log metrics.
      attr_reader :method_called

      # These attributes are available on Gibbon::MailChimpError
      # and we want to pass them through to the caller.
      attr_reader :title, :detail, :body, :status_code

      def initialize(error, method_called)
        if error.is_a?(Gibbon::MailChimpError)
          @title         = error.title
          @detail        = error.detail
          @body          = error.body
          @status_code   = error.status_code
          @method_called = method_called
        else
          raise ArgumentError, "error must be a Gibbon::MailChimpError"
        end

        instrument_status_code

        super error.message.present? ? error.message : title
      end

      def failbot_context
        {
          mailchimp_response_code: status_code,
          mailchimp_response_title: title,
          mailchimp_response_detail: detail,
          mailchimp_response_body: body,
        }.merge super
      end

      private

      def instrument_status_code
        tags = ["action:#{method_called}"]
        tags << "error:#{status_code}" if status_code

        GitHub.dogstats.increment "mailchimp.error", tags: tags
      end
    end
  end
end
