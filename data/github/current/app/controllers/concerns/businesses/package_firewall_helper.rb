# typed: true
# frozen_string_literal: true

module Businesses
  # Shared helpers for the Package Firewall enterprise settings controllers
  # (`Businesses::PackageFirewallSettingsController` for the policy itself, and
  # `Businesses::PackageFirewallOverridesController` for per-package
  # allow/deny overrides). Carries the validation rules, the param shape, the
  # severity enum mapping, and the cached Twirp client.
  module PackageFirewallHelper
    extend T::Helpers
    extend ActiveSupport::Concern
    include GitHub::Memoizer

    requires_ancestor { Businesses::BusinessController }

    VALID_SEVERITY_THRESHOLDS = %w[low medium high critical].freeze
    VALID_ECOSYSTEMS = %w[npm].freeze
    MINIMUM_PACKAGE_AGE_RANGE = (0..720) # 0–30 days, in hours
    VALID_OVERRIDE_TYPES = %w[allow deny].freeze

    SEVERITY_TO_CLIENT = {
      SEVERITY_LOW: "low",
      SEVERITY_MEDIUM: "medium",
      SEVERITY_HIGH: "high",
      SEVERITY_CRITICAL: "critical",
    }.freeze
    SEVERITY_FROM_CLIENT = SEVERITY_TO_CLIENT.invert.transform_keys(&:to_s).freeze

    private

    sig { returns(PackageFirewall::Twirp::PackageFirewallClient) }
    memoize def package_firewall_client
      PackageFirewall::Twirp::PackageFirewallClient.new
    end

    sig { void }
    def ensure_package_firewall_enabled
      render_404 unless this_business.feature_flag_enabled?(:package_firewall_enterprise_policy_ui, default: false)
    end

    # ---- Serialization (server → camelCase JSON for the React client) ----

    sig { params(response: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def serialize_policy(response)
      data = response.respond_to?(:policy) ? response.policy : response
      policy = (data.respond_to?(:to_h) ? data.to_h : data).dup
      policy[:severity_threshold] = SEVERITY_TO_CLIENT[policy[:severity_threshold]]
      policy.transform_keys { |k| k.to_s.camelize(:lower).to_sym }
    end

    sig { params(response: T.untyped, list_key: Symbol).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def serialize_package_identifiers(response, list_key)
      data = response.respond_to?(:to_h) ? response.to_h : response
      (data[list_key] || []).map { |id| id.respond_to?(:to_h) ? id.to_h : id }
    end

    # ---- Param extraction (camelCase JSON in → snake_case Twirp params) ----

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def policy_params
      raw = (params[:policy] || {})
      policy = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.symbolize_keys : raw.dup.symbolize_keys
      if (severity = policy.delete(:severityThreshold))
        policy[:severity_threshold] = SEVERITY_FROM_CLIENT[severity] || :SEVERITY_UNSPECIFIED
      end
      if policy.key?(:minimumPackageAge)
        parsed = safe_integer(policy[:minimumPackageAge])
        if parsed.nil?
          policy.delete(:minimumPackageAge)
        else
          policy[:minimumPackageAge] = parsed
        end
      end
      policy
        .transform_keys { |k| k.to_s.underscore.to_sym }
        .compact
    end

    sig { returns(T::Hash[Symbol, String]) }
    def package_identifier_from_params
      {
        ecosystem: params[:ecosystem],
        name: params[:name],
        version: params[:version] || "",
      }.compact
    end

    # ---- Validation ----

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    def validate_policy_params
      errors = []
      raw = params[:policy] || {}
      policy = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.symbolize_keys : raw.dup.symbolize_keys

      if policy[:severityThreshold].present? && !VALID_SEVERITY_THRESHOLDS.include?(policy[:severityThreshold])
        errors << { field: "severityThreshold", message: "must be one of: #{VALID_SEVERITY_THRESHOLDS.join(", ")}" }
      end

      if policy[:minimumPackageAge].present?
        hours = safe_integer(policy[:minimumPackageAge])
        if hours.nil?
          errors << { field: "minimumPackageAge", message: "must be an integer number of hours" }
        elsif !MINIMUM_PACKAGE_AGE_RANGE.include?(hours)
          errors << {
            field: "minimumPackageAge",
            message: "must be between #{MINIMUM_PACKAGE_AGE_RANGE.min} and #{MINIMUM_PACKAGE_AGE_RANGE.max} hours",
          }
        end
      end

      errors
    end

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    def validate_override_params
      errors = []

      if params[:ecosystem].blank?
        errors << { field: "ecosystem", message: "is required" }
      elsif !VALID_ECOSYSTEMS.include?(params[:ecosystem])
        errors << { field: "ecosystem", message: "must be one of: #{VALID_ECOSYSTEMS.join(", ")}" }
      end

      if params[:name].blank?
        errors << { field: "name", message: "is required" }
      end

      if params[:type].blank?
        errors << { field: "type", message: "is required" }
      elsif !VALID_OVERRIDE_TYPES.include?(params[:type])
        errors << { field: "type", message: "must be one of: #{VALID_OVERRIDE_TYPES.join(", ")}" }
      end

      errors
    end

    # Strict integer parser: returns nil for nil, blanks, non-integer strings,
    # and floats with fractional parts. We deliberately avoid `to_i`, which
    # silently coerces "abc" to 0 and would let the range check pass with the
    # wrong value.
    sig { params(value: T.untyped).returns(T.nilable(Integer)) }
    def safe_integer(value)
      return nil if value.nil?
      return value if value.is_a?(Integer)
      Integer(value.to_s, 10)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
