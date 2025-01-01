# typed: true
# frozen_string_literal: true

# This is part of an experiment to localize the homepage to Brazilian Portuguese
# This code may be removed after the experiment. Ping #i18n in Slack with any questions.
module ApplicationController::LocalizationDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }

  extend ActiveSupport::Concern
  include ResilienceHelper

  included do
    T.bind(self, T.class_of(ApplicationController))
    before_action :set_default_locale
    helper_method :user_currency
    helper_method :localization_config
    helper_method :user_country_code
  end

  private

  def set_default_locale
    Localization.reset
  end

  def switch_locale(&block)
    # Tells varnish we want to cache 1 variation per language
    # @see https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Vary
    response.headers["Vary"] = [response.headers["Vary"].presence, "Accept-Language"].compact.join(", ")

    user_accepted_language = request.headers["HTTP_ACCEPT_LANGUAGE"]
    chosen_locale = Localization
      .with_locale_from_http_accept_language_header(user_accepted_language, &block)
    response.headers["Content-Language"] = chosen_locale
  end

  def user_currency
    localization_config.user_currency
  end

  def user_country_code
    localization_config.country_code
  end

  def localization_config
    @localization_config ||= Localization::Config.new(actor: current_user, request: request)
  end
end
