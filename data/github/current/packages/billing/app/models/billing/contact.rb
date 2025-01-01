# typed: strict
# frozen_string_literal: true

class Billing::Contact < ApplicationRecord::Domain::Billing
  extend T::Sig
  include GitHub::Memoizer
  include GitHub::Validations
  include Instrumentation::Model
  include Billing::TradeCompliance::ContactDependency

  HUMANIZED_ATTRIBUTES = T.let(
    {
      entity_name: "Business/Institution name",
      address1: "Address",
      address2: "Address line 2",
      postal_code: "Postal/Zip code",
      country_code: "Country/Region",
      region: "State/Province"
    }.freeze, T::Hash[Symbol, String]
  )
  COUNTRIES_REQUIRING_REGION = T.let(%w(US CA), T::Array[String])
  ADDRESS_FIELDS = T.let(%w(address1 address2 country_code region city postal_code).freeze, T::Array[String])

  belongs_to :customer
  validates_presence_of :customer

  enum :address_type, { billing: 0, shipping: 1 }
  validates :address_type, presence: true, uniqueness: { scope: :customer_id }

  enum :trade_screening_status, AccountScreeningProfile::VALID_SDN_STATUSES

  validates_length_of :first_name, :last_name, maximum: 64
  validates_length_of :entity_name, maximum: 800
  validates_length_of :address1, :address2, maximum: 128
  validates_length_of :city, :region, maximum: 64
  validates_length_of :postal_code, maximum: 32
  validates_length_of :country_code, maximum: 3
  validate :has_name_or_entity
  validate :contact_allowed_for_org_type

  after_commit :update_zuora_account_information, on: [:create, :update]
  after_create_commit :instrument_create
  after_update_commit :instrument_update
  after_destroy_commit :instrument_destroy


  sig do
    params(
      attr: T.any(String, Symbol),
      options: T::Hash[Symbol, T.untyped]
    ).returns(String)
  end
  def self.human_attribute_name(attr, options = {})
    HUMANIZED_ATTRIBUTES[attr.to_sym] || super
  end

  sig { returns(T.nilable(Billing::Types::Account)) }
  def billable_owner
    customer&.billable_owner
  end

  sig { returns(String) }
  def fullname
    return "#{first_name} #{last_name}".strip unless entity_name.present?

    entity_name.to_s.strip
  end

  sig { returns(Billing::Public::AddressValidityResponse) }
  def validate_address
    return Billing::Public::AddressValidityResponse.new(valid: true, error: "") unless should_validate?

    result = Billing::Public.validate_address(
      street: address1.to_s,
      city: city.to_s,
      region: region.to_s,
      postal_code: postal_code.to_s,
      billing_country_code: country_code.to_s,
    )
    if result.valid
      self.postal_code = result.suggested_postal_code unless result.suggested_postal_code.blank?
      self.address_validated_at = GitHub::Billing.timezone.now
    end
    result
  end

  # The shipping contact can be used to determine the sales tax amount
  sig { returns(T::Boolean) }
  def eligible_for_sales_tax?
    shipping? && country_is_united_states?
  end

  sig { params(customer: T.nilable(Customer)).void }
  def update_zuora_account_information(customer: self.customer)
    return unless customer

    customer.update_contact_information(self)
    return unless zuora_account_id = customer.zuora_account_id

    UpdateZuoraAccountInformationJob.perform_later(zuora_account_id: zuora_account_id, contact_id: self.id)

    # We only want to update the linked orgs if this contact is being updated. If we're only updating zuora information
    # due to linking a a contact to an org, the contact information itself hasn't changed so we don't need to update all the linked orgs.
    update_linked_orgs_zuora_account_billing_information if customer.id == self.customer&.id
  end

  private

  sig { void }
  def has_name_or_entity
    name_present = first_name.present? || last_name.present?
    return unless name_present && entity_name.present?

    errors.add(:base, "Entity name cannot be provided if first name or last name is present")
  end

  sig { void }
  def contact_allowed_for_org_type
    return unless billable_owner&.org_is_on_standard_tos?

    errors.add(:base, "Organizations on standard terms of service can only have a linked Contact record to the user")
  end

  sig { void }
  def update_linked_orgs_zuora_account_billing_information
    return unless self.id
    return unless billing?

    owner = self.billable_owner
    return unless owner.is_a?(User)
    return if owner.id.blank?

    # Prevent memoization issues from fetching linked orgs. Tests surfaced this issue
    # when initially creating the contact which would load the orgs and memoize them
    # any further actions on the record would not reload the memoized cache causing the tests to fail
    # due to the orgs not showing up on the instance of the contact.
    owner = User.find(owner.id)
    owner.orgs_linked_to_billing_contact.each { |org| self.update_zuora_account_information(customer: org.customer) }
  end

  sig { void }
  def instrument_create
    instrument :contact_create
  end

  sig { void }
  def instrument_update
    instrument :contact_update
  end

  sig { void }
  def instrument_destroy
    instrument :contact_delete
  end

  sig { returns(Symbol) }
  def event_prefix
    :billing
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    {
      customer_id: customer_id,
      address_type: address_type,
      trade_screening_status: trade_screening_status,
    }.tap do |payload|
      owner = T.must(customer).billable_owner
      payload[owner.event_prefix] = owner if owner.present?
    end
  end

  sig { returns(T::Boolean) }
  def should_validate?
    return false unless country_is_united_states?
    address_validated_at.blank? || changed? && changed.any? { |field| ADDRESS_FIELDS.include?(field) }
  end

  sig { returns(T::Boolean) }
  def country_is_united_states?
    country_code == "US"
  end
end
