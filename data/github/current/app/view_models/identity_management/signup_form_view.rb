# typed: true
# frozen_string_literal: true

class IdentityManagement::SignupFormView < BillingSettings::SignupFormView

  def initialize(user:)
    super(user, coupon_code = nil, users_path = urls.signup_path)
  end

  def password_hint
    "Use at least one lowercase letter, one numeral, and seven characters."
  end

  private

  # Internal: Call generated route and URL helpers through this
  # object.
  def urls
    @urls ||= ViewModel::URLs.new
  end
end
