# typed: true
# frozen_string_literal: true

# This is part of an experiment to localize the homepage to Brazilian Portuguese
# This code may be removed after the experiment. Ping #i18n in Slack with any questions.
module ApplicationController::LocalizationDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }

  extend ActiveSupport::Concern
  include ResilienceHelper

  CONFIG_PATH = Rails.root.join("config", "localized_controllers.yml")

  included do
    T.bind(self, T.class_of(ApplicationController))
    before_action :set_default_locale
    helper_method :user_currency
    helper_method :localization_config
    helper_method :user_country_code
    helper_method :user_defined_locale_enabled?
  end

  module ClassMethods
    def enabled_controllers
      config = YAML.load_file(CONFIG_PATH)
      config.fetch("controllers", {}).select { |_k, v| v["enabled"] }.keys
    end

    def localization_enabled?
      return @localization_enabled unless @localization_enabled.nil?
      @localization_enabled = enabled_controllers.include?(T.unsafe(self).name)
    end
  end

  private

  def set_default_locale
    Site::Localization.reset
  end

  def switch_locale(&block)
    # Tells varnish we want to cache 1 variation per language
    # @see https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Vary
    add_headers_to_vary(["Accept-Language"])
    response.headers["Content-Language"] = user_locale

    if redirect_for_locale?
      redirect_for_localization
    else
      Site::Localization.with_locale_from_http_accept_language_header(user_locale, &block)
    end
  end

  def user_locale
    if cookies[:locale].present? && user_defined_locale_enabled?
      locale = cookies[:locale]
    elsif params[:locale].present? && user_defined_locale_enabled?
      locale = params[:locale]
    else
      locale = request.headers["HTTP_ACCEPT_LANGUAGE"]
    end
    Site::Localization::AcceptHeaderLocaleResolver.new.resolve(locale)
  end

  def default_locale
    "en-us"
  end

  def user_defined_locale_enabled?
    # This conditional should be temporary and exists to protect against a root route bug that appears only in prod
    if request.path == "/" && !FeatureFlag.vexi.enabled?(:root_localization_experiment, current_user, default: false)
      return false
    end

    # Uses the YAML-based allowlist and feature flag
    T.unsafe(self.class).localization_enabled? &&
      FeatureFlag.vexi.enabled_or_raise?(:marketing_localization_experiment, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def user_currency
    localization_config.user_currency
  end

  def user_country_code
    localization_config.country_code
  end

  def localization_config
    @localization_config ||= Site::Localization::Config.new(actor: current_user, request: request)
  end

  def localized_alternative_links
    @show_alternative_links = true
  end

  def redirect_for_localization
    uri = URI.parse(request.original_url)
    query_params = request.query_parameters
    query_params.delete("locale")

    if (params[:locale] || "").downcase == default_locale
      uri.query = query_params.empty? ? nil : URI.encode_www_form(query_params)
    else
      # Ensure all other params come first, then append locale
      ordered_params = query_params.to_a + [["locale", user_locale]]
      uri.query = URI.encode_www_form(ordered_params)
    end

    redirect_to uri.to_s
  end

  def redirect_for_locale?
    return false unless user_defined_locale_enabled?

    params_locale = params[:locale]

    if user_locale.downcase == default_locale
      # For English: redirect only if locale param is present (to remove it)
      params_locale.present?
    else
      # For non-English: redirect if no locale param or wrong locale param
      params_locale.nil? || params_locale.downcase != user_locale.downcase
    end
  end
end
