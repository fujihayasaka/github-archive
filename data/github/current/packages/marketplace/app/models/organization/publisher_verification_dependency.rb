# typed: true
# frozen_string_literal: true

module Organization::PublisherVerificationDependency
  extend T::Helpers
  requires_ancestor { Organization }

  PROFILE_ERROR_MESSAGES = {
    details_missing: "Either organization name, profile picture, email or location is not provided",
    invalid_location: "A valid location is required. Please select another location",
    embargo_location: "Publisher Verification is not available for your current location",
    email_unverified: "Profile email verification is not completed. Please verify your profile email.",
    unknown_error: "An unknown error has occured",
  }

  CUBA = Braintree::Address::CountryNames.find { |c| c[1] == "CU" }[0]
  SYRIA = Braintree::Address::CountryNames.find { |c| c[1] == "SY" }[0]
  NORTH_KOREA = Braintree::Address::CountryNames.find { |c| c[1] == "KP" }[0]
  IRAN = Braintree::Address::CountryNames.find { |c| c[1] == "IR" }[0]
  PUBLISHER_VERIFICATION_DENYLIST = Set.new([CUBA, NORTH_KOREA, SYRIA, IRAN])

  def can_request_verification?(current_user)
    profile_complete? && current_user.two_factor_authentication_enabled? && has_verified_domain?
  end

  def can_request_verification_for_org?
    profile_complete? && two_factor_requirement_enabled? && has_verified_domain?
  end

  def is_org_app_listed?
    self.oauth_applications.count > 0 || self.integrations.count > 0
  end

  def has_verified_domain?
    verified_profile_domains.any?
  end

  def countries_list
    Braintree::Address::CountryNames.map do |country_name, _, _, _|
      country_name
    end
  end

  def is_allowed_to_publish?
    !self.has_any_trade_restrictions?
  end

  def is_location_allowed?
    (self.countries_list.include? T.unsafe(self).profile_location) && !(PUBLISHER_VERIFICATION_DENYLIST.include? T.unsafe(self).profile_location)
  end

  def profile_complete?
    T.unsafe(self).profile_email.present? &&
    self.profile_name.present? &&
    T.unsafe(self).profile_location.present? &&
    self.is_location_allowed? &&
    self.is_allowed_to_publish? &&
    email_verified?
  end

  def profile_error
    if !T.unsafe(self).profile_email.present? || !self.profile_name.present? || !T.unsafe(self).profile_location.present?
      PROFILE_ERROR_MESSAGES[:details_missing]
    elsif !(self.countries_list.include? T.unsafe(self).profile_location)
      PROFILE_ERROR_MESSAGES[:invalid_location]
    elsif (PUBLISHER_VERIFICATION_DENYLIST.include? T.unsafe(self).profile_location) || (!self.is_allowed_to_publish?)
      PROFILE_ERROR_MESSAGES[:embargo_location]
    elsif !email_verified?
      PROFILE_ERROR_MESSAGES[:email_unverified]
    else
      PROFILE_ERROR_MESSAGES[:unknown_error]
    end
  end

  def email_verified?
    profile_email_verification.present? && profile_email_verification.verified?
  end

  def profile_email_verification
    self.organization_profile_emails.for_profile_email(T.unsafe(self).profile_email).first
  end
end
