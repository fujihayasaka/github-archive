# typed: true
# frozen_string_literal: true

class Marketplace::Agreement < ApplicationRecord::Domain::Integrations
  extend GitHub::Encoding
  force_utf8_encoding :body

  include GitHub::Relay::GlobalIdentification

  self.table_name = "marketplace_agreements"

  enum :signatory_type, { integrator: 0, end_user: 1 }

  INTEGRATOR_AGREEMENT_NAME = "Marketplace Developer Agreement".freeze
  END_USER_AGREEMENT_NAME = "Marketplace Terms of Service".freeze

  validates :body, :version, :signatory_type, presence: true
  validates :version, uniqueness: { scope: :signatory_type, case_sensitive: false }
  validate :version_is_later_than_previous

  # rubocop:todo Rails/InverseOf
  has_many :signatures, class_name: "Marketplace::AgreementSignature",
                        foreign_key: "marketplace_agreement_id"
  # rubocop:enable Rails/InverseOf

  scope :latest, -> { order("version DESC") }

  # Public: Returns the most recent agreement for integrators to sign.
  def self.latest_for_integrators
    latest.integrator.first
  end

  # Public: Returns the most recent agreement for end users to sign.
  def self.latest_for_end_users
    latest.end_user.first
  end

  # Public: Returns true if the given User has signed this agreement for their
  # personal account.
  def signed_by?(user)
    signatures.exists?(signatory_id: user, organization_id: nil)
  end

  # Public: Returns true if the given Organization has had this agreement signed
  # on its behalf.
  def signed_for?(organization)
    signatures.exists?(organization_id: organization)
  end

  # Public: Returns a string describing this agreement, based on the signatory type.
  def name
    if integrator?
      INTEGRATOR_AGREEMENT_NAME
    elsif end_user?
      END_USER_AGREEMENT_NAME
    end
  end

  def event_prefix
    :marketplace_agreement
  end

  def event_context(prefix: event_prefix)
    {
      "#{prefix}_id".to_sym => id,
      prefix => name,
    }
  end

  # Public: Sign this agreement as the given user on behalf of the given, optional organization.
  # Returns true if the signature was created successfully, false otherwise.
  def sign(user:, organization: nil)
    signature = signatures.new(signatory_id: user, organization_id: organization)
    signature.save
  end

  def platform_type_name
    "MarketplaceAgreement"
  end

  private

  def version_is_later_than_previous
    return unless T.unsafe(version) && signatory_type

    previous_agreement = if integrator?
      self.class.latest_for_integrators
    elsif end_user?
      self.class.latest_for_end_users
    end

    return unless previous_agreement

    if version <= previous_agreement.version
      errors.add(:version, "#{version} must come after the previous #{signatory_type} " +
                           "version #{previous_agreement.version}")
    end
  end
end
