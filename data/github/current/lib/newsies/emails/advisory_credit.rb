# typed: false
# frozen_string_literal: true

module Newsies
  module Emails
    class AdvisoryCredit < Newsies::Emails::Message
      def self.matches?(comment)
        comment.is_a?(::AdvisoryCredit)
      end

      alias_method :advisory_credit, :comment

      def subject
        advisory_credit.notification_summary_title
      end

      def body
        :advisory_credit
      end

      def body_html
        :advisory_credit_html
      end

      # The Newsies::Emails::Message base class checks if there's a body_html
      # implementation in the model. Instead of adding this to model, we are
      # overriding this method.
      def body_html?
        true
      end

      # Can't reply to an advisory credit email
      def tokenized_list_address
        GitHub.urls.noreply_address
      end

      # Can't unsubscribe from an advisory credit email
      def tokenized_unsubscribe_address
        nil
      end

      def permalink
        advisory_credit.permalink
      end

      def sender
        advisory_credit.creator || User.ghost
      end
    end
  end
end
