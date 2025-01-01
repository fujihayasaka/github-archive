# typed: true
# frozen_string_literal: true

module Site::CookieConsentDependency
  extend ActiveSupport::Concern

  extend T::Helpers
  requires_ancestor { ApplicationController }

  include GitHub::Memoizer

  COOKIE_CONSENT_REQUIRED_COUNTRY_CODES = %w(
    AT
    BE
    BG
    BR
    CA
    CH
    CN
    CY
    CZ
    DE
    DK
    EE
    ES
    FI
    FR
    GB
    GR
    HR
    HU
    IE
    IS
    IT
    LI
    LT
    LU
    LV
    MT
    NL
    NO
    PL
    PT
    RO
    SE
    SI
    SK
    TR
  ).freeze

  private

  memoize def enable_cookie_consent
    return if GitHub.single_or_multi_tenant_enterprise?

    @cookie_consent_enabled = feature_enabled_globally_or_for_current_user?(:marketing_cookie_consent_banner)
    @cookie_consent_required = COOKIE_CONSENT_REQUIRED_COUNTRY_CODES.include?(GitHub.context[:country_code]&.upcase)

    GitHub.logger.info(
      "Evaluating cookie consent for consent banner",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.consent_banner.cookie_consent.required" => @cookie_consent_required,
      "gh.consent_banner.country.code" => GitHub.context[:country_code]&.upcase,
    )
  end

  memoize def allow_initial_cookie_consent
    return if GitHub.single_or_multi_tenant_enterprise?

    @initial_cookie_consent_allowed = true
  end
end
