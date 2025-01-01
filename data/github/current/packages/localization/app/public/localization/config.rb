# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Localization
  class Config
    def initialize(actor: nil, request: nil)
      @actor = actor
      @request = request
    end

    def for_actor(actor)
      self.class.new(actor: actor, request: @request)
    end

    def for_request(request)
      self.class.new(actor: @actor, request: request)
    end

    def default_currency
      "USD"
    end

    def user_currency
      default_currency
    end

    def supported_currencies
      ([default_currency] + localized_currencies - unsupported_currencies).uniq
    end

    def unsupported_currencies
      [
        # not supported by the currency exchange api
        "BYR",
        "SKK",
        "XBA",
        "XBB",
        "XBC",
        "XBD",
        "XTS",
        "ZMK",

        # not in config/country-codes.csv
        "BTN",
        "BYN",
        "CLF",
        "CUC",
        "HTG",
        "LSL",
        "MRU",
        "NAD",
        "PAB",
        "SVC",
        "VES",
        "XAG",
        "XAU",
        "XDR",
        "XPD",
        "XPT",
      ]
    end

    def localized_currencies
      if defined?(@localized_currencies)
        return @localized_currencies
      end

      @localized_currencies = []
    end

    def ugct_banner_enabled?
      GitHub.flipper[:ugc_machine_translation_banner].enabled?(@actor)
    end

    def browser_vitals_time_metric_enabled?
      GitHub.flipper[:browser_vitals_time_metric].enabled?(@actor)
    end

    def available_locales
      %w[
        en
        ja
        ko
        pt
        es
      ]
    end

    def default_locale
      available_locales.first
    end

    def allowed_accept_language_headers
      %w[en-US ja pt-BR ko-KR es-419]
    end

    def country_code
      if defined?(@country_code)
        return @country_code
      end

      @country_code ||= GitHub::Location.look_up(@request.remote_ip)[:country_code]
    end

    def region_name
      if defined?(@region_name)
        return @region_name
      end

      @region_name ||= GitHub::Location.look_up(@request.remote_ip)[:region_name]
    end

    def ugc_inline_machine_translation_enabled?
      GitHub.flipper[:ugc_inline_machine_translation].enabled?(@actor)
    end

    def ugct_languages
      %w[en ko pt es]
    end

    def ugct_supports_language?(language_code)
      ugct_languages.include?(language_code.to_s.split("-").first)
    end

    def primary_browser_language
      @primary_browser_language ||= AcceptLanguageHeaderParser.new.parse(@request.headers["HTTP_ACCEPT_LANGUAGE"]).first
    end

    def primary_browser_language_without_region
      @primary_browser_language_without_region = primary_browser_language.split("-").first
    end

    def primary_browser_language_name
      @primary_browser_language_name ||= language_name(primary_browser_language_without_region)
    end

    def language_name(code)
      code = code.to_s.split("-").first
      Trending::SpokenLanguageFinder.from_code(code).name
    end
  end
end
