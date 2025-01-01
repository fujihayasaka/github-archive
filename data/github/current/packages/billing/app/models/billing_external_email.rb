# typed: true
# frozen_string_literal: true

class BillingExternalEmail < ApplicationRecord::Domain::Billing
  belongs_to :owner, polymorphic: true

  validates_format_of :email,
    with: User::EMAIL_REGEX,
    message: "does not look like an email address",
    allow_nil: false,
    allow_blank: false

  validate :email_can_not_be_primary
  validates :email, uniqueness: { scope: [:owner_id, :owner_type], case_sensitive: false }
  validate :ensure_email_not_disposable

  private

  def email_can_not_be_primary
    if owner.billing_email == self.email
      errors.add(:email, "can't be the same as primary billing email")
    end
  end

  def ensure_email_not_disposable
    if UserEmail::DisposableEmailsDependency.disposable_email?(email)
      errors.add(:email, "cannot be #{email} - #{UserEmail::GENERIC_DOMAIN_ERROR}")
    end
  end
end
