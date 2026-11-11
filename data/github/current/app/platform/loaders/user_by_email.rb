# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class UserByEmail < Platform::Loader
      def self.load(email, business: nil)
        if email =~ UserEmail::GENERIC_DOMAIN_REGEXP || email.blank?
          return Promise.resolve(nil)
        end

        self.for(business).load(email)
      end

      def self.load_all(emails, business: nil)
        Promise.all(
          emails.map { |email| load(email, business: business) },
        )
      end

      def initialize(business)
        @business = business
      end

      def fetch(emails)
        emails_to_users = User.find_by_emails(emails, business: @business)

        emails.map do |email|
          [email, emails_to_users[email] || emails_to_users[email.downcase]]
        end.to_h
      end
    end
  end
end
