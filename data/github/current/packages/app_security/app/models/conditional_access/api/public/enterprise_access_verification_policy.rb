# typed: true
# frozen_string_literal: true

# The Enterprise Managed User policy makes sure access the users using GitHub
# match the security header value defined in the "sec-GitHub-allowed-enterprise" header
# This is the Public API specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Public::EnterpriseAccessVerificationPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::EnterpriseAccessVerification

  # Public API specific enforcement implementation
  def enterprise_access_verification_enforce(target)
    business_identifiers = business_security_header.to_s.split(",").map(&:strip).reject(&:empty?)

    # Check if too many enterprises are specified
    if business_identifiers.length > ConditionalAccess::Policy::EnterpriseAccessVerification::MAX_BUSINESSES_IN_HEADER
      callback.set_forbidden_message(ConditionalAccess::Api::Public::EnterpriseAccessVerificationPolicy.multiple_enterprises_message([], business_security_header, true))
      return
    end

    businesses_from_header = businesses_from_security_header(business_identifiers)

    applicable_businesses = businesses_from_header.select { |business| business.enterprise_managed? && business.proxy_security_header_enabled? }
    callback.set_forbidden_message(ConditionalAccess::Api::Public::EnterpriseAccessVerificationPolicy.multiple_enterprises_message(applicable_businesses, business_security_header, false))
  end

  def self.multiple_enterprises_message(businesses, security_header, too_many_enterprises = false)
    # Check if too many enterprises are specified
    if too_many_enterprises
      return "Too many enterprises specified in the 'sec-GitHub-allowed-enterprise' header. A maximum of #{ConditionalAccess::Policy::EnterpriseAccessVerification::MAX_BUSINESSES_IN_HEADER} enterprises are allowed. Contact your network administrator if this error persists."
    end

    if businesses.any?
      business_names = businesses.map(&:name).join(", ")
      "Your network administrator has blocked access to GitHub except for the '#{business_names}' enterprises. Only tokens for the '#{business_names}' enterprises can access GitHub."
    else
      "The enterprise named in the 'sec-GitHub-allowed-enterprise' header cannot be found. Ensure that the '#{security_header}' is entered correctly in the firewall or proxy settings. Contact your network administrator if this error persists."
    end
  end
end
