# typed: true
# frozen_string_literal: true

class OrganizationProfile < ApplicationRecord::Domain::Sponsors
  extend T::Sig

  before_validation :normalize_sponsors_update_email,
    if: :sponsors_update_email_changed?

  validates :sponsors_update_email,
    format: {
      with: User::EMAIL_REGEX,
      message: "does not look like an email address",
    },
    allow_nil: true
  validates :stripe_customer_id, uniqueness: true, allow_nil: true
  validates :organization_id, uniqueness: true

  belongs_to :organization, required: true
  belongs_to :sponsoring_linked_organization, class_name: "Organization"

  scope :for_organization, ->(org) { where(organization_id: org) }
  scope :for_sponsoring_linked_org, ->(org) { where(sponsoring_linked_organization_id: org) }
  scope :with_sponsoring_linked_organization_id, -> { where.not(sponsoring_linked_organization_id: nil) }

  sig { params(actor: T.nilable(User)).void }
  def instrument_stripe_customer_create(actor:)
    GlobalInstrumenter.instrument("sponsors.sponsors_invoiced_account_stripe_customer_create", {
      organization: organization,
      actor: actor,
      stripe_customer_id: stripe_customer_id,
    })
  end

  private

  def normalize_sponsors_update_email
    return if sponsors_update_email.present?
    self.sponsors_update_email = nil
  end
end
