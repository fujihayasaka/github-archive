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
    if FeatureFlag.vexi.enabled?(:multiple_enterprise_access_verification, default: false)
      multiple_enterprise_access_verification_enforce
    else
      business_from_header = business_from_security_header(business_security_header)
      raise Platform::Errors::Execution.new("EMU enterprise access verification", ConditionalAccess::Api::Internal::EnterpriseAccessVerificationPolicy.message(business_from_header, business_security_header))
    end
  end

  def multiple_enterprise_access_verification_enforce
    business_identifiers = business_security_header.to_s.split(",").map(&:strip).reject(&:empty?)

    # Check if too many enterprises are specified
    if business_identifiers.length > ConditionalAccess::Policy::EnterpriseAccessVerification::MAX_BUSINESSES_IN_HEADER
      raise Platform::Errors::Execution.new("EMU enterprise access verification", ConditionalAccess::Api::Internal::EnterpriseAccessVerificationPolicy.multiple_enterprises_message([], business_security_header, true))
    end

    businesses_from_header = businesses_from_security_header(business_identifiers)

    applicable_businesses = businesses_from_header.select { |business| business.enterprise_managed? && business.proxy_security_header_enabled? }
    raise Platform::Errors::Execution.new("EMU enterprise access verification", ConditionalAccess::Api::Internal::EnterpriseAccessVerificationPolicy.multiple_enterprises_message(applicable_businesses, business_security_header, false))
  end

  def self.multiple_enterprises_message(businesses, security_header, too_many_enterprises = false)
    # Check if too many enterprises are specified
    if too_many_enterprises
      return "Too many enterprises are specified. A maximum of #{ConditionalAccess::Policy::EnterpriseAccessVerification::MAX_BUSINESSES_IN_HEADER} enterprises are allowed. Contact your network administrator if this error persists."
    end

    if businesses.any?
      if security_header.to_s.include?(",") && businesses.none?(&:multiple_enterprise_access_verification_enabled?)
        "Only one enterprise can be used with the 'sec-GitHub-allowed-enterprise header'. Ensure that only a single enterprise and header is provided. If this issue persists, contact your network administrator."
      else

        business_names = businesses.map(&:name).join(", ")
        "Your network administrator has blocked access to GitHub except for the #{business_names} enterprises. Only tokens for these enterprises can access GitHub."
      end
    else
      "Enterprises named in the 'sec-GitHub-allowed-enterprise' header cannot be found. Ensure that the '#{security_header}' is entered correctly in the firewall or proxy settings. Contact your network administrator if this error persists."
    end
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
