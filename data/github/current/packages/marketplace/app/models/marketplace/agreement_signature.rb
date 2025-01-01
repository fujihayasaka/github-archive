# typed: true
# frozen_string_literal: true

class Marketplace::AgreementSignature < ApplicationRecord::Domain::Integrations
  self.table_name = "marketplace_agreement_signatures"

  include Instrumentation::Model

  # rubocop:todo Rails/InverseOf
  belongs_to :agreement, class_name: "Marketplace::Agreement",
                         foreign_key: "marketplace_agreement_id"
  # rubocop:enable Rails/InverseOf
  belongs_to :signatory, class_name: "User"
  belongs_to :organization

  validates :agreement, :signatory, presence: true
  validate :signatory_is_org_admin

  scope :for_user, ->(user) { where(signatory_id: user) }

  scope :for_org, ->(org) { where(organization_id: org) }

  scope :latest, -> { order("#{table_name}.id DESC") }

  after_commit :instrument_creation, on: :create

  # Public: Returns the most recent integrator signature for the given User and optional
  # Organization.
  def self.for_integrator(user:, organization:)
    if user
      signatures = for_user(user).joins(:agreement).merge(Marketplace::Agreement.integrator)
      if organization
        # check for signature on behalf of organization
        signatures = signatures.for_org(organization)
      else
        # check for signature on behalf of user, if Organization nill is not pass, a non nill Organization signature is returned, which is not valid.
        signatures = signatures.where(organization_id: nil)
      end
    elsif user.nil? && organization != nil
      # find if there exists any agreement on behalf of organization, this is the case when we don't know who has singed it.
      signatures = for_org(organization).joins(:agreement).merge(Marketplace::Agreement.integrator)
    end
    signatures&.latest&.first
  end

  # Public: Returns the most recent end-user signature for the given User.
  def self.for_end_user(user)
    for_user(user).joins(:agreement).merge(Marketplace::Agreement.end_user).latest.first
  end

  def event_prefix
    :marketplace_agreement_signature
  end

  def event_context(prefix: event_prefix)
    { "#{prefix}_id".to_sym => id }
  end

  def event_payload
    payload = {
      event_prefix => self,
      :marketplace_agreement => agreement,
      :actor => signatory,
      :version => agreement&.version,
      :signatory_type => agreement&.signatory_type&.to_sym,
    }
    if organization
      payload[:org] = organization
    else
      payload[:user] = signatory
    end
    payload
  end

  def platform_type_name
    "MarketplaceAgreementSignature"
  end

  private

  def instrument_creation
    instrument :create
  end

  def signatory_is_org_admin
    return unless signatory && organization

    unless organization&.adminable_by?(signatory)
      errors.add(:signatory, "is not an administrator of #{organization}")
    end
  end
end
