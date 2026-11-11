# typed: true
# frozen_string_literal: true

class IntegrationUrlValidator < ActiveModel::Validator
  ALWAYS_VALIDATE_STRICTLY = %w(Integration)

  def validate(record)
    options = {}
    if validate_strictly?(record&.application)
      options[:blocked_query_keys] = OauthUtil::RESERVED_REDIRECT_URI_QUERY_KEYS
      options[:allow_fragment] = false
    end

    return if IntegrationUrl.valid_callback_url?(record.url, options)

    record.errors.add(:url, Integration::INVALID_URL_MESSAGE)
  end

  def validate_strictly?(application)
    return false unless ApplicationCallbackUrl::VALID_APPLICATION_TYPES.include?(application.class.name)

    # We always validate GitHub App callback URLs strictly on creation,
    # even if we don't neccessarily enforce strict validation on OAuth
    # authorization. This is to prevent 'bad' data getting into the database.
    return true if ALWAYS_VALIDATE_STRICTLY.include?(application.class.name)

    # OAuth Apps have different rules because there is already bad data in the
    # database and we haven't yet enforced strict validation for all
    # integrators.
    application.strict_callback_url_validation?
  end

end
