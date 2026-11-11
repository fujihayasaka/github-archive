# typed: false
# frozen_string_literal: true

module Platform
  module Loaders
    class UserEmails < Platform::Loader
      def self.load(user_id, business: nil)
        self.for(business).load(user_id)
      end

      def self.load_all(user_ids, business: nil)
        Promise.all(
          user_ids.map { |id| load(id, business: business) },
        )
      end

      def initialize(business)
        @business = business
      end

      # Returns a list of emails by user ID. If user has no emails, empty list is returned.
      def fetch(user_ids)
        emails_by_user_id = UserEmail.where(user_id: user_ids).group_by(&:user_id)

        user_ids.each do |id|
          emails_by_user_id[id] ||= []
          emails_by_user_id[id] = emails_by_user_id[id].map { |user_email| remove_shortcode(user_email.email) }
        end

        # EMU user do not have stealth emails, skip adding them
        User.where(id: user_ids).each do |user|
          stealth_email = StealthEmail.new(user)
          emails_by_user_id[user.id] << stealth_email.legacy_email
          emails_by_user_id[user.id] << stealth_email.email
        end unless @business && @business.enterprise_managed_user_enabled? || GitHub.proxima_emu_test_mode?

        emails_by_user_id
      end

      def remove_shortcode(email)
        if @business
          @business.remove_shortcode(email)
        else
          email
        end
      end
    end
  end
end
