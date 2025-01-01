# typed: true
# frozen_string_literal: true

require "authorization/content_authorization_error"

class ContentAuthorizationError::EmailVerificationRequired < ContentAuthorizationError
  def symbolic_error_code
    :verified_email_required
  end

  def message
    "At least one email address must be verified to do that."
  end

  def documentation_url
    "#{GitHub.help_url}/articles/adding-an-email-address-to-your-github-account"
  end
end
