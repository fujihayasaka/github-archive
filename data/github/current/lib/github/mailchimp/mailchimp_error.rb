# typed: true
# frozen_string_literal: true

module GitHub
  class Mailchimp
    class MailchimpError < StandardError
      def failbot_context
        { app: "github-external-request" }
      end
    end
  end
end
