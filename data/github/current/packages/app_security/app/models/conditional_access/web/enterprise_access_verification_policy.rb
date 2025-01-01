# typed: true
# frozen_string_literal: true

# The Enterprise Managed User policy makes sure access the users using GitHub
# match the security header value defined in the "sec-GitHub-allowed-enterprise" header
#
# This is the ApplicationController specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Web::EnterpriseAccessVerificationPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::EnterpriseAccessVerification

  # application controller specific enforcement implementation
  def enterprise_access_verification_enforce(target)
    if enterprise_access_verification_public_beta_enabled?
      business_from_header = business_from_security_header(business_security_header)
    else
      business_from_header = business_from_slug(business_security_header)
    end
    if business_from_header
      callback.send(:render, json: { error: ConditionalAccess::Web::EnterpriseAccessVerificationPolicy.message(business_from_header, business_security_header) }, status: 403)
    else
      callback.send(:render, json: { error: ConditionalAccess::Web::EnterpriseAccessVerificationPolicy.message(business_from_header, business_security_header) }, status: 400)
    end
  end

  def self.message(business, security_header)
    if business
      "Your network administrator has blocked access to GitHub except for the '#{business.name}' Enterprise. Please sign in with your '_#{business.shortcode} account to access GitHub."
    elsif security_header.to_s.include?(",")
      "Only one enterprise can be used with the 'sec-GitHub-allowed-enterprise header'. Ensure that only a single enterprise and header is provided. If this issue persists, contact your network administrator."
    else
      "The enterprise named in the 'sec-GitHub-allowed-enterprise' header cannot be found. Ensure that the '#{security_header}' is entered correctly in the firewall or proxy settings. Contact your network administrator if this error persists."
    end
  end
end
