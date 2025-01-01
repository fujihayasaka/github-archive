# typed: strict
# frozen_string_literal: true

class Billing::Contact < ApplicationRecord::Domain::Billing
  include GitHub::Memoizer
  include GitHub::Validations
  include Instrumentation::Model
  include Billing::TradeCompliance::ContactDependency

  class ContactDeletionError < StandardError; end

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

  # Contact attributes that are considered PII and only updated by the customer.
  # Postal code is intentionally excluded here because it can be both updated by the customer and internally
  # via taxamo/address validation. All other fields are considered internal attributes.
  PII_ATTRIBUTES = T.let(%w(first_name last_name entity_name address1 address2 city region country_code).freeze, T::Array[String])
  INTERNAL_ATTRIBUTES = T.let((Billing::Contact.attribute_names - PII_ATTRIBUTES).freeze, T::Array[String])
  COUNTRIES_REQUIRING_REGION = T.let(%w(US CA), T::Array[String])
  ADDRESS_FIELDS = T.let(%w(address1 address2 country_code region city postal_code).freeze, T::Array[String])

  belongs_to :customer
  validates_presence_of :customer_id

  enum :address_type, { billing: 0, shipping: 1 }
  validates :address_type, presence: true, uniqueness: { scope: :customer_id }

  enum :trade_screening_status, AccountScreeningProfile::VALID_SDN_STATUSES

  validates_length_of :first_name, :last_name, maximum: 64
  validates_length_of :entity_name, maximum: 800
  validates_length_of :address1, :address2, maximum: 128
  validates_length_of :city, :region, maximum: 64
  validates_length_of :postal_code, maximum: 32
  validates_length_of :country_code, maximum: 3
  validate :contact_allowed_for_org_type
  validate :allowed_to_update

  validates :entity_name, presence: true, on: :new_self_serve_business
  validates :country_code, presence: true, on: :new_self_serve_business

  after_commit :update_zuora_account_information, on: [:create, :update]
  after_commit :rescreen_on_pii_update, on: :update

  before_destroy :ensure_allowed_to_delete

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

  sig { returns(T.any(T::Boolean, T.self_type)) }
  def destroy
    return super unless persisted?

    billable_owner = self.billable_owner
    if billable_owner&.is_a?(User)
      billable_owner.unlink_contact_from_all_linked_orgs
    end

    super
  end

  sig { returns(T.nilable(Billing::Types::Account)) }
  def billable_owner
    customer&.billable_owner
  end

  sig { returns(String) }
  def fullname
    billable_owner = self.billable_owner
    user_owned = (billable_owner.blank? && entity_name.blank?) || billable_owner&.user?

    return "#{first_name} #{last_name}".strip if user_owned

    entity_name.to_s.strip
  end

  sig { returns(TradeControls::Country) }
  def country
    country_info = Braintree::Address::CountryNames.find do |_, alpha2, _, _|
      alpha2 == country_code
    end
    TradeControls::Country.from_braintree(country_info)
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

  sig { returns(T::Boolean) }
  def validated_for_sales_tax?
    # At this time, only United States requires the address to be validated
    return true unless country_is_united_states?
    address_validated_at?
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

  sig { returns(T::Boolean) }
  def country_is_united_states?
    country_code == "US"
  end

  sig { returns(T.nilable(String)) }
  def us_state
    StatesAndProvinceHelper.find_state(region)
  end

  sig { returns(T.nilable(String)) }
  def vat_code
    billable_owner&.trade_screening_record&.vat_code || customer&.vat_code
  end

  sig { returns(Billing::ContactUpdateStash) }
  memoize def contact_information_stash
    Billing::ContactUpdateStash.retrieve_stashed_update_for(billable_owner, self.address_type)
  end

  private

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
    return unless owner.feature_enabled?(:read_billing_information_from_contacts)

    # Prevent memoization issues from fetching linked orgs. Tests surfaced this issue
    # when initially creating the contact which would load the orgs and memoize them
    # any further actions on the record would not reload the memoized cache causing the tests to fail
    # due to the orgs not showing up on the instance of the contact.
    owner = User.find(owner.id)
    owner.orgs_linked_to_billing_contact.each { |org| self.update_zuora_account_information(customer: org.customer) }
  end

  sig { overridable.returns(T::Boolean) }
  def can_update?
    return true if self.new_record?

    !self.has_update_trade_restrictions?
  end

  sig { overridable.returns(T::Boolean) }
  def can_delete?
    return true if self.new_record?
    return false if self.has_delete_trade_restrictions?
    return true if destroyed_by_association.present?

    return true unless billable_owner = self.billable_owner
    return true if billable_owner.is_a?(User) && Organization.transforming?(billable_owner)
    return false if billable_owner.is_a?(User) && billable_owner.upcoming_charges?
    return false if billable_owner.is_a?(Business) && (!billable_owner.trial? || !billable_owner.self_serve_payment?)

    !billable_owner.invoiced?
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
    return false unless Customer::COUNTRY_CODES_REQUIRING_VALIDATED_ADDRESS_FOR_SALES_TAX.include?(country_code)
    address_validated_at.blank? || changed? && changed.any? { |field| ADDRESS_FIELDS.include?(field) }
  end

  sig { void }
  def allowed_to_update
    return if new_record?
    return unless changed?
    return if internal_attribute_update_only?

    return if can_update?

    errors.add(:updates, "are not allowed")
  end

  sig { void }
  def ensure_allowed_to_delete
    return if can_delete?

    raise ContactDeletionError.new("Contact is not allowed to be deleted")
  end

  # Private: Check if the changes in the model are only for internal attributes
  sig { returns(T::Boolean) }
  def internal_attribute_update_only?
    self.changed? && (self.changed - INTERNAL_ATTRIBUTES).empty?
  end
end
