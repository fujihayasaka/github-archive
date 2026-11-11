# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class BotByEmail < Platform::Loader
      def self.load(email)
        if email.blank? || !email.ends_with?("#{Bot::LOGIN_SUFFIX}@#{GitHub.stealth_email_host_name}")
          return Promise.resolve(nil)
        end

        self.for.load(email)
      end

      def fetch(emails)
        emails_to_bots = Bot.find_by_emails(emails)

        emails.map do |email|
          [email, emails_to_bots[email] || emails_to_bots[email.downcase]]
        end.to_h
      end
    end
  end
end
