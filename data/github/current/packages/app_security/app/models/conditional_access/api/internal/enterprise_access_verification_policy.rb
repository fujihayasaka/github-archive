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
    business_from_header = business_from_slug(business_slug_header)
    raise Platform::Errors::Execution.new("EMU enterprise access verification", ConditionalAccess::Api::Internal::EnterpriseAccessVerificationPolicy.message(business_from_header, business_slug_header))
  end

  def self.message(business, business_slug)
    if business
      "Your network administrator has blocked access to GitHub except for the '#{business.name}' Enterprise. Only tokens for the '#{business.name}' enterprise can access GitHub."
    elsif business_slug.include?(",")
      "Only one enterprise can be used with the 'sec-GitHub-allowed-enterprise header'. Ensure that only a single enterprise and header is provided. If this issue persists, contact your network administrator."
    else
      "The enterprise named in the 'sec-GitHub-allowed-enterprise' header cannot be found. Ensure that the '#{business_slug}' is entered correctly in the firewall or proxy settings. Contact your network administrator if this error persists."
    end
  end
end
