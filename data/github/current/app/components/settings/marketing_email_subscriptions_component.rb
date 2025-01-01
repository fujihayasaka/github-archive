# typed: true
# frozen_string_literal: true

module Settings
  class MarketingEmailSubscriptionsComponent < ApplicationComponent
    include GitHub::Memoizer
    include ApplicationComponent::Rescuable

    rescue_from Timeout::Error, with: :nothing

    def initialize(user:)
      @user = user
    end

    sig { returns(T::Boolean) }
    def render?
      verified_emails.any?
    end

    private

    def verified_emails
      return @user.emails.verified.pluck(:email) unless @user.is_enterprise_managed?

      @user.emails.verified.pluck(:email).map do |email|
        @user.remove_shortcode(email)
      end
    end
  end
end
