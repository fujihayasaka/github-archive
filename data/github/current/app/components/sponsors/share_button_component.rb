# typed: strict
# frozen_string_literal: true

class Sponsors::ShareButtonComponent < ApplicationComponent
  delegate :social_account_icon, to: :helpers

  SHARE_URL_BY_SOCIAL = T.let({
    "twitter" => SocialAccounts::Twitter.share_url,
    "facebook" => SocialAccounts::Facebook.share_url,
    "mastodon" => SocialAccounts::Mastodon.share_url,
    "reddit" => SocialAccounts::Reddit.share_url,
    "linkedin" => SocialAccounts::LinkedIn.share_url,
  }.freeze, T::Hash[String, String])

  SOURCE_BY_SOCIAL = T.let({
    "twitter" => Sponsors::TrackingParameters::TWITTER_SOURCE,
    "facebook" => Sponsors::TrackingParameters::FACEBOOK_SOURCE,
    "mastodon" => Sponsors::TrackingParameters::MASTODON_SOURCE,
    "reddit" => Sponsors::TrackingParameters::REDDIT_SOURCE,
    "linkedin" => Sponsors::TrackingParameters::LINKEDIN_SOURCE,
  }.freeze, T::Hash[String, String])

  sig do
    params(
      sponsorable_login: String,
      user: T.nilable(User),
      text: String,
      data: T::Hash[String, T.untyped],
      url_params: T::Hash[String, T.untyped],
      render_textarea: T::Boolean,
      autofocus: T::Boolean
    ).void
  end
  def initialize(
    sponsorable_login:,
    user:,
    text: "",
    data: {},
    url_params: {},
    render_textarea: false,
    autofocus: false
  )
    @sponsorable_login = sponsorable_login
    @user = user
    @text = text
    @data = data
    @url_params = url_params
    @render_textarea = render_textarea
    @autofocus = autofocus
  end

  private

  sig { returns(T.nilable(User)) }
  attr_reader :user

  sig { returns(String) }
  attr_reader :text, :sponsorable_login

  sig { returns(T::Hash[String, T.untyped]) }
  attr_reader :url_params

  sig { returns(T::Boolean) }
  attr_reader :render_textarea

  sig { returns T::Array[SocialAccount] }
  def shareable_social_accounts
    social_accounts = user&.profile_social_accounts
    return [] if !social_accounts.present?
    social_accounts.select do |social_account|
      share_url_by_social_account(social_account).present?
    end
  end

  sig { params(social_account: SocialAccount).returns(T.nilable(String)) }
  def share_url_by_social_account(social_account)
    SHARE_URL_BY_SOCIAL.fetch(social_account.key, nil)
  end

  sig { params(social_account: SocialAccount).returns(String) }
  def sponsors_profile_url_by_social_account(social_account)
    query_params = @url_params.merge(
      Sponsors::TrackingParameters.new(
        source: SOURCE_BY_SOCIAL.fetch(social_account.key),
      ).to_h
    ).to_query

    "https://github.com/sponsors/#{@sponsorable_login}?#{query_params}"
  end
end
