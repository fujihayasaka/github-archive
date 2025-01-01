# typed: true
# frozen_string_literal: true

class Sponsors::TrackingParameters
  QUERY_PARAM_KEYS_BY_ATTRIBUTE = {
    source: "sc",
    origin: "o",
    referring_account_login: "sp",
  }.freeze

  SOURCES = [
    TWITTER_SOURCE = "TWITTER",
    FACEBOOK_SOURCE = "FACEBOOK",
    MASTODON_SOURCE = "MASTODON",
    REDDIT_SOURCE = "REDDIT",
    LINKEDIN_SOURCE = "LINKEDIN",
  ].freeze

  QUERY_PARAM_VALUES_BY_SOURCE = {
    TWITTER_SOURCE => "t",
    FACEBOOK_SOURCE => "fb",
    MASTODON_SOURCE => "m",
    REDDIT_SOURCE => "r",
    LINKEDIN_SOURCE => "li",
  }.freeze

  ORIGINS = [
    SPONSORS_DASHBOARD_ORIGIN = "SPONSORS_DASHBOARD",
    EMBEDDED_SPONSOR_BUTTON_ORIGIN = "EMBEDDED_SPONSOR_BUTTON",
    EMBEDDED_SPONSOR_CARD_ORIGIN = "EMBEDDED_SPONSOR_CARD",
    SPONSORS_YOUR_GOALS_ORIGIN = "SPONSORS_YOUR_GOALS",
    SPONSORS_PROFILE_ORIGIN = "SPONSORS_PROFILE",
    NEW_SPONSOR_MAIL_ORIGIN = "NEW_SPONSOR_MAIL",
    NOW_SPONSORING_MAIL_ORIGIN = "NOW_SPONSORING_MAIL",
  ].freeze

  QUERY_PARAM_VALUES_BY_ORIGIN = {
    SPONSORS_DASHBOARD_ORIGIN => "sd",
    EMBEDDED_SPONSOR_BUTTON_ORIGIN => "esb",
    EMBEDDED_SPONSOR_CARD_ORIGIN => "esc",
    SPONSORS_YOUR_GOALS_ORIGIN => "syg",
    SPONSORS_PROFILE_ORIGIN => "sp",
    NEW_SPONSOR_MAIL_ORIGIN => "nsm",
    NOW_SPONSORING_MAIL_ORIGIN => "ns",
  }.freeze

  attr_reader :source, :origin, :referring_account_login

  def initialize(source: nil, origin: nil, referring_account_login: nil)
    @source = source
    @origin = origin
    @referring_account_login = referring_account_login
  end

  def self.from_params(params)
    source_param_value = params[QUERY_PARAM_KEYS_BY_ATTRIBUTE.fetch(:source)]
    source = QUERY_PARAM_VALUES_BY_SOURCE.key(source_param_value) if source_param_value

    origin_param_value = params[QUERY_PARAM_KEYS_BY_ATTRIBUTE.fetch(:origin)]
    origin = QUERY_PARAM_VALUES_BY_ORIGIN.key(origin_param_value) if origin_param_value

    referring_account_login_param_value = params[QUERY_PARAM_KEYS_BY_ATTRIBUTE.fetch(:referring_account_login)]

    new(source: source, origin: origin, referring_account_login: referring_account_login_param_value)
  end

  def to_h
    {
      QUERY_PARAM_KEYS_BY_ATTRIBUTE.fetch(:source).to_sym => source_param_value,
      QUERY_PARAM_KEYS_BY_ATTRIBUTE.fetch(:origin).to_sym => origin_param_value,
      QUERY_PARAM_KEYS_BY_ATTRIBUTE.fetch(:referring_account_login).to_sym => referring_account_login,
    }.compact
  end

  def referring_account
    User.find_by(login: referring_account_login)
  end

  private

  def source_param_value
    QUERY_PARAM_VALUES_BY_SOURCE.fetch(source) if source.present?
  end

  def origin_param_value
    QUERY_PARAM_VALUES_BY_ORIGIN.fetch(origin) if origin.present?
  end
end
