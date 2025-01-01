# typed: true
# frozen_string_literal: true

module Settings
  class EmailPreferencesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :user

    def wants_marketing_email?
      NewsletterPreference.marketing?(user: user)
    end

    def wants_transactional_email?
      !wants_marketing_email?
    end

    def unsubscribed_list
      user.newsletter_subscriptions.allowlisted.unsubscribed
    end

    def subscription_list
      user.newsletter_subscriptions.allowlisted.active
    end
  end
end
