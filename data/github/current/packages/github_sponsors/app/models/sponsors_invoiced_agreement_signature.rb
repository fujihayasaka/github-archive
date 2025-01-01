# typed: strict
# frozen_string_literal: true

# Public: Represents a user's agreement on behalf of a particular organization to the terms and conditions for that
# org to be invoiced to increase their credit balance to be used for sponsorships.
class SponsorsInvoicedAgreementSignature < ApplicationRecord::Domain::Sponsors
  extend T::Sig
  include Instrumentation::Model

  DEFAULT_DURATION_IN_YEARS = 3
  BILLING_DOCS_URL = T.let(
    "#{GitHub.help_url}/sponsors/sponsoring-open-source-contributors/paying-for-github-sponsors-by-invoice",
    String
  )

  belongs_to :agreement, required: true, inverse_of: :invoiced_signatures, class_name: "SponsorsAgreement",
    foreign_key: :sponsors_agreement_id
  belongs_to :signatory, required: true, class_name: "User",
    inverse_of: :sponsors_invoiced_agreement_signatures_as_signatory
  belongs_to :organization, required: true, inverse_of: :sponsors_invoiced_agreement_signatures

  validate :signatory_has_organization_permission, on: :create
  validate :organization_is_an_org
  validate :agreement_is_invoiced_sponsor_kind
  validate :agreement_is_current_version, on: :create

  before_create :set_expiry
  after_commit :instrument_creation, on: :create

  scope :not_expired, -> { where(arel_table[:expires_on].gt(Date.current)) }
  scope :for_org, ->(org_or_id) { where(organization_id: org_or_id) }
  scope :for_agreement, ->(agreement_or_id) { where(sponsors_agreement_id: agreement_or_id) }
  scope :latest, -> do
    # SELECT sponsors_invoiced_agreement_signatures.*
    # FROM sponsors_invoiced_agreement_signatures
    # WHERE expires_on = (
    #   SELECT MAX(inner_signatures.expires_on)
    #   FROM sponsors_invoiced_agreement_signatures AS inner_signatures
    #   WHERE sponsors_invoiced_agreement_signatures.organization_id = inner_signatures.organization_id
    # )
    # GROUP BY organization_id

    outer_signatures = arel_table
    inner_signatures = arel_table.alias("inner_signatures")
    expiration_of_latest_signature = outer_signatures
      .project(inner_signatures[:expires_on].maximum).from(inner_signatures)
      .where(outer_signatures[:organization_id].eq(inner_signatures[:organization_id]))

    where(outer_signatures[:expires_on].eq(expiration_of_latest_signature))
      .group(:organization_id)
  end

  # Public: Has the invoiced sponsor agreement been signed for the specified organization?
  #
  # org_or_id - an Organization or its integer database ID
  # version - optional String version to check for a signature; by default will check for a signature with the latest
  #           version of the agreement
  #
  # Returns a Boolean.
  sig { params(org_or_id: T.any(Organization, Integer), version: T.nilable(String)).returns(T::Boolean) }
  def self.signed_for_org?(org_or_id, version: nil)
    agreement_scope = SponsorsAgreement.invoiced_sponsor_kind
    agreement_scope = version.nil? ? agreement_scope.with_latest_version : agreement_scope.with_version(version)
    signatures = org_or_id.is_a?(Organization) ? org_or_id.sponsors_invoiced_agreement_signatures : for_org(org_or_id)
    signatures.joins(:agreement).not_expired.merge(agreement_scope).exists?
  end

  # Public: Which version of the agreement was signed.
  #
  # Returns a String.
  sig { returns(T.nilable(String)) }
  def agreement_version
    agreement&.version
  end

  # Public: Is this signature expired?
  #
  # Returns a Boolean
  sig { returns(T::Boolean) }
  def expired?
    expires_on <= Date.current
  end

  # Public: Terminates the agreement signature by setting the expiration date to today.
  # Also enqueues an email to notify the org's admins of the termination.
  #
  # Returns a Boolean indicating success
  sig { returns(T::Boolean) }
  def terminate
    return false unless can_terminate?

    success = update(expires_on: Date.current)

    if success
      SponsorsPrimerMailer.invoice_agreement_signature_terminated(
        org: organization,
        termination_date: Date.current
      ).deliver_later
    end

    success
  end


  sig { returns(T.nilable(String)) }
  def signatory_login
    signatory&.display_login
  end

  sig { returns(User) }
  def safe_signatory
    signatory || User.ghost
  end

  sig { returns(T.any(User, Organization)) }
  def safe_organization
    organization || User.ghost
  end

  sig { returns(Symbol) }
  def event_prefix
    :sponsors_invoiced_agreement_signature
  end

  sig { params(prefix: T.any(String, Symbol)).returns(T::Hash[Symbol, T.untyped]) }
  def event_context(prefix: event_prefix)
    { "#{prefix}_id".to_sym => id }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    payload = {
      event_prefix => self,
      :sponsors_agreement_id => sponsors_agreement_id,
      :version => agreement_version,
      :actor_id => signatory_id,
      :org_id => organization_id,
      :expires_on => expires_on,
    }

    this_org = organization
    this_agreement = agreement
    this_signatory = signatory

    payload.merge!(this_org.event_context) if this_org
    payload.merge!(this_agreement.event_context) if this_agreement
    payload.merge!(this_signatory.event_context(prefix: :actor)) if this_signatory
    payload
  end

  # Public: Can this agreement signature be terminated?
  #
  # Returns a Boolean
  sig { returns(T::Boolean) }
  def can_terminate?
    return false if expired?

    # Per legal, if the customer has an open invoice, they are unable to terminate their agreement.
    # https://github.com/github/sponsors/issues/5216#issuecomment-1716179811
    !organization&.any_open_stripe_invoices?
  end

  private

  sig { void }
  def set_expiry
    self.expires_on = DEFAULT_DURATION_IN_YEARS.years.from_now
  end

  sig { void }
  def instrument_creation
    # Audit log
    instrument :invoiced_agreement_sign, prefix: :sponsors

    # Hydro
    GlobalInstrumenter.instrument("sponsors.invoiced_agreement_sign", signatory: signatory,
      agreement_version: agreement_version, organization: organization, expires_on: expires_on)
  end

  sig { void }
  def signatory_has_organization_permission
    return unless org = organization
    return unless signatory.present? && org.organization?
    unless org.billing_manageable_by?(signatory)
      errors.add(:signatory, "is not an owner or billing manager for @#{org.display_login}")
    end
  end

  sig { void }
  def organization_is_an_org
    return unless org = organization
    errors.add(:organization, "must be an organization") unless org.organization?
  end

  sig { void }
  def agreement_is_invoiced_sponsor_kind
    return unless this_agreement = agreement
    errors.add(:agreement, "kind does not match signature type") unless this_agreement.invoiced_sponsor_kind?
  end

  sig { void }
  def agreement_is_current_version
    current_agreement = SponsorsAgreement.current_invoiced_sponsor_agreement
    return unless current_agreement

    unless current_agreement.id == sponsors_agreement_id
      errors.add(:agreement, "must be the current version, #{current_agreement.version}")
    end
  end
end
