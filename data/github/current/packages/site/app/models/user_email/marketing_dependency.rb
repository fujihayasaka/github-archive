# typed: strict
# frozen_string_literal: true

module UserEmail::MarketingDependency
  extend T::Helpers

  requires_ancestor { UserEmail }

  PERSONAL_DOMAINS = T.let(%w[
    gmail
    yahoo
    hotmail
    aol
    msn
    orange
    comcast
    live
    outlook
    yandex
    me
    icloud
    verizon
    fastmail
  ].freeze, T::Array[String])

  TOP_LEVEL_DOMAINS = T.let(%w[
    com
    co.uk
    fr
    net
    fm
    ru
  ].freeze, T::Array[String])

  EMAIL_REGEX = /\A[^\s]+@[^\s]+[.][^\s]+\z/
  EMAIL_PATTERN_JS = "^[^\\s]+@[^\\s]+[.][^\\s]+$"
  # This is temporary, as we will be redesigning the enterprise/contact page
  EMAIL_PERSONAL_DOMAIN_REGEX = T.let(Regexp.new("\\A(?!.*@(#{PERSONAL_DOMAINS.join('|')})\\.(#{TOP_LEVEL_DOMAINS.join('|')})\\z)[^\\s]+@[^\\s]+[.][^\\s]+\\z"), Regexp)

  # Public: Should the email be added to MailChimp?
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def should_be_subscribed_in_mailchimp?
    T.cast(
      primary? &&
        verified? &&
        marketing_preference? &&
        valid_mailchimp_email?,
      T::Boolean)
  end

  private

  # Private: Is the email viewed as valid by MailChimp?
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def valid_mailchimp_email?
    GitHub::Mailchimp.new(self).valid_email?
  end

  # Private: Does the user accept email marketing communication?
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def marketing_preference?
    NewsletterPreference.marketing?(user: user)
  end
end
