# typed: true
# frozen_string_literal: true

module GitHub
  class Mailchimp
    class BatchError < MailchimpError

      def initialize(options)
        @options = options
        instrument_failure_count
      end

      def instrument_failure_count
        errors_count = @options["errored_operations"]
        GitHub.dogstats.count "mailchimp.batched_jobs.failures", errors_count
      end

      def failbot_context
        selected_attributes =
          %w(
            id
            total_operations
            finish_operations
            errored_operations
            response_body_url
          )
        context = @options.slice(*selected_attributes)
        context.merge super
      end

    end
  end
end
