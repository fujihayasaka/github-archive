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

    country_code = GitHub.context[:country_code]&.upcase

    @cookie_consent_enabled = FeatureFlag.vexi.enabled?(:marketing_cookie_consent_banner, current_user, default: false)
    @cookie_consent_required = COOKIE_CONSENT_REQUIRED_COUNTRY_CODES.include?(country_code)

    GitHub.dogstats.distribution(
      "site.cookie_consent.evaluation",
      1,
      # Use DEFAULT_HOST_TAG to collapse the host dimension (which can have thousands of
      # unique values) into a single tag, keeping overall cardinality low enough to
      # safely include additional tags like country_code.
      tags: [
        GitHub::Dogstats::DEFAULT_HOST_TAG,
        "cookie_consent_required:#{@cookie_consent_required}",
        "country_code:#{country_code}"
      ],
      sample_rate: 0.5,
    )

    span_attributes = {
      "gh.cookie.consent.required" => @cookie_consent_required,
      "geo.country.iso_code" => country_code,
    }

    span_attributes.compact!

    OpenTelemetry::Instrumentation::Rack.current_span&.add_attributes(span_attributes)
  end

  memoize def allow_initial_cookie_consent
    return if GitHub.single_or_multi_tenant_enterprise?

    @initial_cookie_consent_allowed = true
  end
end
