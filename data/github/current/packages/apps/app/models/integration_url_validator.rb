# typed: true
# frozen_string_literal: true

class IntegrationUrlValidator < ActiveModel::Validator
  ALWAYS_VALIDATE_STRICTLY = %w(Integration)

  def validate(record)
    application = record&.application

    # Determine whether to block fragments based on feature flag and app type
    # - GitHub Apps: always block fragments (strict validation)
    # - OAuth Apps: block fragments only when oauth_fragment_rejection is enabled and not exempt
    allow_fragment = if ALWAYS_VALIDATE_STRICTLY.include?(application.class.name)
      false  # GitHub Apps always block fragments
    elsif application.respond_to?(:oauth_fragment_exempt?) &&
          FeatureFlag.vexi.enabled?(:oauth_fragment_rejection, application, default: false) &&
          !application.oauth_fragment_exempt?
      false  # OAuth Apps block fragments when rejection is enabled and app is not exempt
    else
      !validate_strictly?(application, record)  # Legacy: depends on strict/permissive validation
    end

    # Pass record so validate_strictly? can check per-URL matching strategy
    options = {
      allow_fragment: allow_fragment
    }

    strict = validate_strictly?(application, record)
    if strict
      # Strict validation: block reserved query keys
      options[:blocked_query_keys] = OauthUtil::RESERVED_REDIRECT_URI_QUERY_KEYS
    end

    valid = IntegrationUrl.valid_callback_url?(record.url, options)

    app_type = application.is_a?(Integration) ? "integration" : "oauth_application"
    validation_mode = strict ? "strict" : "permissive"
    GitHub.dogstats.increment "auth.oauth.callback_url_registration", tags: [
      "result:#{valid ? "valid" : "invalid"}",
      "app_type:#{app_type}",
      "validation_mode:#{validation_mode}",
    ]

    return if valid

    record.errors.add(:url, Integration::INVALID_URL_MESSAGE)
  end

  # Determines whether to enforce strict validation rules for a callback URL.
  # When callback_url_matching_strategy is enabled, respects the per-URL
  # matching_strategy attribute. Otherwise falls back to legacy behavior.
  #
  # @param application [OauthApplication, Integration] The app owning the callback URL
  # @param record [ApplicationCallbackUrl] The callback URL being validated (optional)
  # @return [Boolean] true if strict validation should be enforced
  def validate_strictly?(application, record = nil)
    return false unless ApplicationCallbackUrl::VALID_APPLICATION_TYPES.include?(application.class.name)

    # We always validate GitHub App callback URLs strictly on creation,
    # even if we don't neccessarily enforce strict validation on OAuth
    # authorization. This is to prevent 'bad' data getting into the database.
    return true if ALWAYS_VALIDATE_STRICTLY.include?(application.class.name)

    # When callback_url_matching_strategy is enabled, respect the individual
    # URL's matching strategy. This allows apps to choose permissive (allows
    # fragments, reserved query keys) or strict (blocks them) per callback URL.
    if record && FeatureFlag.vexi.enabled?(:callback_url_matching_strategy, application, default: false)
      # Strict strategy: block fragments and reserved query keys at registration
      # Permissive strategy: allow them at registration (for flexibility)
      return record.strict_matching_strategy?
    end

    # OAuth Apps have different rules because there is already bad data in the
    # database and we haven't yet enforced strict validation for all
    # integrators. Fallback to legacy behavior: strict only if multiple callbacks.
    application.strict_callback_url_validation?
  end
end
