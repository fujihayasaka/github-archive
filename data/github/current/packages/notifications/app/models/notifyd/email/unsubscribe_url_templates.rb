# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class UnsubscribeUrlTemplates

      sig { returns(Notifyd::Proto::Layouts::Email::UnsubscribeUrlTemplates) }
      def serialize
        Notifyd::Proto::Layouts::Email::UnsubscribeUrlTemplates.new(
          # Url for the link in the email footer
          footer: "#{GitHub.url}/notifications/unsubscribe-auth/{token}",
          # Url for List-Unsubscribe header
          header: "#{GitHub.url}/notifications/unsubscribe/one-click/{token}",
        )
      end

      sig { returns(T::Hash[Symbol, String]) }
      def to_h
        {
          # Url for the link in the email footer
          footer: "#{GitHub.url}/notifications/unsubscribe-auth/{token}",
          # Url for List-Unsubscribe header
          header: "#{GitHub.url}/notifications/unsubscribe/one-click/{token}",
        }
      end
    end
  end
end
