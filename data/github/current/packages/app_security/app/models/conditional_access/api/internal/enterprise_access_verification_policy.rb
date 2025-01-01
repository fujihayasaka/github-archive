# typed: true
# frozen_string_literal: true

# The Enterprise Managed User policy makes sure access the users using GitHub
# match the security header value defined in the "sec-GitHub-allowed-enterprise" header
#
# This is the Internal API specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Internal::EnterpriseAccessVerificationPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::EnterpriseAccessVerification

  # Public API specific enforcement implementation
  def enterprise_access_verification_enforce(target)
    if enterprise_access_verification_public_beta_enabled?
      business_from_header = business_from_security_header(business_security_header)
    else
      business_from_header = business_from_slug(business_security_header)
    end
    raise Platform::Errors::Execution.new("EMU enterprise access verification", ConditionalAccess::Api::Internal::EnterpriseAccessVerificationPolicy.message(business_from_header, business_security_header))
  end

  def self.message(business, security_header)
    if business
      "Your network administrator has blocked access to GitHub except for the '#{business.name}' Enterprise. Only tokens for the '#{business.name}' enterprise can access GitHub."
    elsif security_header.to_s.include?(",")
      "Only one enterprise can be used with the 'sec-GitHub-allowed-enterprise header'. Ensure that only a single enterprise and header is provided. If this issue persists, contact your network administrator."
    else
      "The enterprise named in the 'sec-GitHub-allowed-enterprise' header cannot be found. Ensure that the '#{security_header}' is entered correctly in the firewall or proxy settings. Contact your network administrator if this error persists."
    end
  end
end
