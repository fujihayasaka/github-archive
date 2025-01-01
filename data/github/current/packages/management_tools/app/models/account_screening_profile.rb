# typed: strict
# frozen_string_literal: true

# An account screening profile for trade controls
#
# The account screening profile stores the account's identification information for
# SDN (specially designated nationals) screening purposes.
class AccountScreeningProfile < ApplicationRecord::Collab
  BATCH_SIZE = T.let(1000.freeze, Integer)
  self.table_name = "user_personal_profiles"
  TOS_CHANGE_BY_STAFF_REASON = T.let("Terms of service changed by staff".freeze, String)
  HUMANIZED_ATTRIBUTES = T.let({
    address1: "Address",
    country_code: "Country/Region",
  }.freeze, T::Hash[Symbol, String])

  include Instrumentation::Model
  include GitHub::Validations
  include GitHub::Memoizer

  class AccountScreeningProfileUpdateError < StandardError; end
  class AccountScreeningProfileDeleteError < StandardError; end
  class InvalidScreeningFieldsError < StandardError; end
  class SyncToContactError < StandardError; end
  class CreateCustomerError < StandardError; end

  # order here matters since this is used by msft_trade_screening_status
  VALID_SDN_STATUSES = T.let([
    :not_screened,
    :no_hit,
    :hit_in_review,
    :true_match,
    :retry,
    :ingestion_error,
    :error,
    :ssi_d,
    :ssi_d_30,
    :ssi_e,
    :ssi_e_60,
    :ssi_f,
    :ssi_f_14,
    :lic_r,
    :lic_a,
    :data_issue,
    :spammy
  ].freeze, T::Array[Symbol])

  # SDN Screening statuses where the actor is allowed to
  # perform a commercial interaction
  SDN_ALLOW_LIST = T.let(%w[
    no_hit
    not_screened
    ssi_d_30
    ssi_e_60
    ssi_f_14
    lic_a
  ].freeze, T::Array[String])

  # SDN Screening statuses where the actor is allowed to modify their
  # personal information (i.e update first_name)
  SDN_STATUS_UPDATE_ALLOW_LIST = T.let(SDN_ALLOW_LIST + %w[
    ingestion_error
    data_issue
  ].freeze, T::Array[String])

  # SDN Screening statuses where the actor is allowed to remove their
  # personal information
  SDN_STATUS_REMOVE_ALLOW_LIST = T.let(%w[
    not_screened
    no_hit
    ingestion_error
    data_issue
  ].freeze, T::Array[String])

  # SDN Screening statuses where staff is allowed to trigger a manual screening on
  SDN_STATUS_MANUAL_SCREENING_ALLOW_LIST = T.let(VALID_SDN_STATUSES - %i[
    ssi_d
    ssi_d_30
    ssi_e
    ssi_e_60
    ssi_f
    ssi_f_14
    lic_r
    lic_a
    true_match
  ].freeze, T::Array[Symbol])

  # SDN Screening statuses where the actor is allowed to modify their
  # metered billing budget.
  SDN_BUDGET_UPDATE_ALLOW_LIST = T.let(SDN_ALLOW_LIST + %w[
    lic_r
    true_match
  ].freeze, T::Array[String])

  # SDN Screening statuses where the actor is allowed to create a free organization
  SDN_FREE_ORG_CREATION_ALLOW_LIST = T.let(SDN_ALLOW_LIST + %w[
    lic_r
    true_match
  ].freeze, T::Array[String])

  # SDN Screening statuses where the actor is allowed to update their billing cycle
  SDN_BILLING_CYCLE_UPDATE_ALLOW_LIST = T.let(SDN_ALLOW_LIST + %w[
    lic_r
    true_match
  ].freeze, T::Array[String])

  # SDN Screening statuses where the actor is allowed to change their repository visibility
  SDN_REPOSITORY_VISIBILITY_CHANGE_ALLOW_LIST = T.let(SDN_ALLOW_LIST + %w[
    lic_r
    true_match
  ].freeze, T::Array[String])

  # SDN statuses that prevent staff from refunding accounts
  SDN_REFUND_RESTRICTING_STATUSES = T.let(%w[
    hit_in_review
  ].freeze, T::Array[String])

  # SDN statuses that prevent an org from changing their Terms of Service
  TERMS_OF_SERVICE_CHANGE_RESTRICTED_STATUSES = T.let(%w[
    lic_r
    hit_in_review
    true_match
  ].freeze, T::Array[String])

  # SDN statuses that prevent an actor from signing up for Copilot
  COPILOT_RESTRICTED_STATUSES = T.let(%w[
    lic_r
    lic_a
    hit_in_review
    true_match
    data_issue
    ingestion_error
    spammy
  ].freeze, T::Array[String])

  FEATURE_TYPE_ALLOW_LISTS = T.let({
    default: SDN_ALLOW_LIST,
    update_info: SDN_STATUS_UPDATE_ALLOW_LIST,
    cost_management: SDN_BUDGET_UPDATE_ALLOW_LIST,
    free_org_creation: SDN_FREE_ORG_CREATION_ALLOW_LIST,
    billing_cycle_update: SDN_BILLING_CYCLE_UPDATE_ALLOW_LIST,
    repository_visibility_change: SDN_REPOSITORY_VISIBILITY_CHANGE_ALLOW_LIST,
    refund_eligible: VALID_SDN_STATUSES.map { |status| status.to_s } - SDN_REFUND_RESTRICTING_STATUSES,
    terms_of_service_change: VALID_SDN_STATUSES.map { |status| status.to_s } - TERMS_OF_SERVICE_CHANGE_RESTRICTED_STATUSES,
    copilot: VALID_SDN_STATUSES.map { |status| status.to_s } - COPILOT_RESTRICTED_STATUSES,
    copilot_vnext: VALID_SDN_STATUSES.map { |status| status.to_s } - COPILOT_RESTRICTED_STATUSES + ["lic_a"],
    direct_org_to_enterprise_upgrade: SDN_ALLOW_LIST,
  }.freeze, T::Hash[Symbol, T::Array[String]])

  # SDN screening statuses where the actor can have their Sponsors profile made public automatically.
  SDN_ALLOWED_AUTO_SPONSORSHIP_LIST = T.let(%w(not_screened no_hit ssi_d_30 ssi_e_60 ssi_f_14).freeze, T::Array[String])

  # Personally Identifiable fields which when updated triggers a rescreen
  RESCREEN_PII_FIELDS = T.let(%w[
    first_name
    last_name
    middle_name
    entity_name
    region
    city
    country_code
    address1
    address2
    vat_code
  ].freeze, T::Array[String])

  # All Personally Identifiable fields
  PII_DATA_FIELDS = T.let((RESCREEN_PII_FIELDS + %w[postal_code]).freeze, T::Array[String])

  ADDRESS_FIELDS = T.let(%w(address1 address2 country_code region city postal_code).freeze, T::Array[String])

  # SDN statuses where the actor is no longer
  # allowed to perform a commercial interaction given the following:
  # GH haven't received an update after one of these statuses
  # and therefore we do not expect one anymore.
  # and this is true when the last status update was more than 7 days ago
  PERMANENTLY_BLOCKED_STATUSES = T.let(%i[ssi_d ssi_e ssi_f lic_r spammy error true_match].freeze, T::Array[Symbol])

  BLOCKED_STATUSES = T.let(PERMANENTLY_BLOCKED_STATUSES + [
    :hit_in_review
  ].freeze, T::Array[Symbol])

  SPONSORSHIP_DISABLING_STATUSES = T.let([
    :hit_in_review
  ].freeze, T::Array[Symbol])

  # SDN Screening statuses where the actor's monthly automatic
  # payments should be disabled
  DISABLE_AUTOPAY_STATUSES = T.let(%i[
    ssi_d
    ssi_e
    ssi_f
    hit_in_review
    ingestion_error
    data_issue
  ].freeze, T::Array[Symbol])

  SDN_DATA_ISSUE_STATUSES = T.let(%w[
    ingestion_error
    data_issue
  ].freeze, T::Array[String])

  SDN_TEMPORARY_STATUSES = T.let(%w[
    hit_in_review
    ingestion_error
    data_issue
  ].freeze, T::Array[String])

  # SDN statuses that prevent a user from deleting their profile
  SDN_STATUS_DELETE_RESTRICTED_STATUSES = T.let(%w[
    hit_in_review
    true_match
  ].freeze, T::Array[String])

  # SDN attributes that are allowed to be updated despite having a blocked SDN status.
  # These attributes are internal attributes (like updating the SDN status) and not user data fields.
  INTERNAL_ATTRIBUTES = T.let(
    %w(
      billing_address_validated_at
      msft_trade_screening_status
      billing_trade_screening_status
      postal_code
      last_trade_screen_date
      updated_at
      metadata
      overdue_email
    ).freeze,
    T::Array[String]
  )

  belongs_to :owner, polymorphic: true, inverse_of: :trade_screening_record

  sig { returns(T.nilable(User)) }
  def actor
    user
  end

  validates :owner_id, presence: true, uniqueness: { scope: :owner_type }, if: :owner_required?
  validates :first_name, :last_name, presence: true, length: { minimum: 2, too_short: "is too short" }, unicode3: true, if: :name_required?
  validates :entity_name, presence: true, unicode3: true, if: :entity_name_required?
  validates :vat_code, presence: true, unicode3: true, if: :vat_code_required?
  validates :address1, presence: true, unicode3: true, if: :address1_required?
  validates :city, presence: true, unicode3: true, if: :city_required?
  validates :region, presence: true, unicode3: true, if: :region_required?
  validates :country_code, presence: true, unicode3: true, if: :country_code_required?
  validates :postal_code, presence: true, unicode3: true, if: :postal_code_required?
  validates_length_of :first_name, :last_name, maximum: 64
  validates_length_of :entity_name, maximum: 800
  validates_length_of :vat_code, maximum: 50
  validates_length_of :address1, maximum: 128
  validates_length_of :city, maximum: 64
  validates_length_of :region, maximum: 64
  validates_length_of :country_code, maximum: 3
  validates_length_of :postal_code, maximum: 10
  validate :valid_owner_type, if: :owner_required?
  validate :validate_org_owner_is_business_owned, if: :owner_required?
  validate :valid_updates_allowed

  before_create :update_marketplace_owner_metadata

  before_update :track_status_change, if: :will_save_change_to_trade_screening_status?
  before_update :send_overdue_email, if: :will_save_change_to_trade_screening_status?
  before_update :reset_status_reason, if: :will_save_change_to_trade_screening_status?
  before_update :unsuspend_on_status_change_from_true_match, if: :will_save_change_to_trade_screening_status?
  before_update :reset_screening_context, if: :will_save_change_to_trade_screening_status?

  before_save :set_last_trade_screen_date, if: :will_save_change_to_trade_screening_status?
  before_save :set_data_issue_status_reason_if_missing, if: :will_save_change_to_trade_screening_status?
  before_save :filter_metadata, if: :will_save_change_to_metadata?

  # String universally unique identifier for external systems. Not
  # intended for use as an identifier in this application.
  before_save :set_external_uuid

  after_save :sync_to_contact
  before_destroy :ensure_personal_profile_deletion_is_allowed

  after_update_commit :send_llama2_access_request, if: :saved_change_to_trade_screening_status?
  after_update_commit :enqueue_check_sponsors_listing_job, if: :saved_change_to_trade_screening_status?
  after_update_commit :rescreen_on_pii_update

  after_commit :enqueue_status_sla_check_job, if: :saved_change_to_trade_screening_status?, on: [:create, :update]
  after_commit :enqueue_billing_changes, if: :saved_change_to_trade_screening_status?, on: [:create, :update]
  after_commit :update_customer_in_billing_platform, if: :saved_change_to_trade_screening_status?

  after_commit :instrument_creation, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_deletion, on: :destroy

  enum :msft_trade_screening_status, VALID_SDN_STATUSES
  enum :billing_trade_screening_status, VALID_SDN_STATUSES, prefix: :billing
  enum :overdue_email, { not_sent: 0, first_sent: 1, second_sent: 2 }

  scope :sdn_retries, -> { where(msft_trade_screening_status: %w[retry error]) }
  scope :hit_in_review_breached, -> { where("last_trade_screen_date <= ?", 2.days.ago).where(msft_trade_screening_status: "hit_in_review") }
  scope :sdn_blocked, -> { where(msft_trade_screening_status: BLOCKED_STATUSES) }
  scope :with_sdn_status, ->(sdn_status) { where(msft_trade_screening_status: sdn_status).order(last_trade_screen_date: :desc) }
  scope :marketplace_app_owners, -> { where(marketplace_app_owner: true) }

  # This accessor stores an array of PII field names that were changed during an update operation.
  # Used when performing rescreening to track which specific PII fields triggered the rescreening.
  # The field names stored here are used for logging and instrumentation purposes in methods like
  # instrument_live_sdn_screening to provide detailed analytics about what changed.
  sig { returns(T.nilable(T::Array[String])) }
  attr_accessor :changed_pii_fields

  sig { params(attr: T.any(String, Symbol), options: T::Hash[Symbol, T.untyped]).returns(String) }
  def self.human_attribute_name(attr, options = {})
    HUMANIZED_ATTRIBUTES[attr.to_sym] || super
  end

  sig { returns(T.nilable(User)) }
  def user
    return @user if defined?(@user)

    if owner_type == "User" && !owner.nil? && owner.user?
      return @user = T.let(T.cast(owner, User), T.nilable(User))
    end

    @user = nil
  end

  sig { returns(T.nilable(Organization)) }
  def organization
    return @organization if defined?(@organization)

    if owner_type == "User" && !owner.nil? && owner.organization?
      return @organization = T.let(T.cast(owner, Organization), T.nilable(Organization))
    end

    @organization = nil
  end

  sig { returns(T.nilable(Business)) }
  def business
    return @business if defined?(@business)

    if owner_type == "Business" && owner.is_a?(Business)
      return @business = T.let(T.cast(owner, Business), T.nilable(Business))
    end

    @business = nil
  end

  # This method is the same as #owner and is added to allow easier migration to Billing::Contact
  sig { returns(Billing::Types::Account) }
  def billable_owner
    owner
  end

  sig { returns(T::Boolean) }
  def user_owned?
    !user.nil?
  end

  # This method is the same as #user_owned? and is added to allow easier migration to Billing::Contact
  sig { returns(T::Boolean) }
  def individual_owned?
    user_owned?
  end

  sig { returns(T::Boolean) }
  def organization_owned?
    !organization.nil?
  end

  sig { returns(T::Boolean) }
  def business_owned?
    !business.nil?
  end

  sig { returns(T::Boolean) }
  def owner_required?
    !%i(user entity individual_trade_screening entity_trade_screening).include?(validation_context)
  end

  sig { returns(T::Boolean) }
  def entity_name_required?
    return false if exempt_from_validations?(include_sales_serve_business_checks: true)

    entity_validation?
  end

  sig { returns(T::Boolean) }
  def name_required?
    return false if exempt_from_validations?

    user_validation?
  end

  sig { returns(T::Boolean) }
  def address1_required?
    return false if exempt_from_validations?(include_self_serve_business_checks: true, include_sales_serve_business_checks: true)

    true
  end

  sig { returns(T::Boolean) }
  def city_required?
    return false if exempt_from_validations?(include_self_serve_business_checks: true, include_sales_serve_business_checks: true)

    true
  end

  sig { returns(T::Boolean) }
  def region_required?
    return false if exempt_from_validations?(include_self_serve_business_checks: true, include_sales_serve_business_checks: true)

    country_code == "US" || country_code == "CA"
  end

  sig { returns(T::Boolean) }
  def country_code_required?
    return false if exempt_from_validations?(include_sales_serve_business_checks: true)

    true
  end

  sig { returns(T::Boolean) }
  def vat_code_required?
    return false if exempt_from_validations?(include_self_serve_business_checks: true, include_sales_serve_business_checks: true)

    vat_code_required_geo?
  end

  sig { returns(T::Boolean) }
  def postal_code_required?
    return false if exempt_from_validations?(include_self_serve_business_checks: true, include_sales_serve_business_checks: true)

    postal_code_required_geo?
  end

  sig { returns(T::Boolean) }
  def new_business_profile_on_trial?
    business_owned? && T.must(business).trial? && new_record?
  end

  sig { returns(T::Boolean) }
  def business_is_sales_serve?
    business_owned? && T.must(business).invoiced?
  end

  # Checks if the record is a pseudo record (a partially filled record with a valid screening status).
  sig { returns(T::Boolean) }
  def pseudo?
    return false if not_screened?
    return false unless persisted?
    !valid_for_owner_type?
  end

  # Check for validations that are required for a user owner
  # Can be forced by using the :user validation context `valid?(:user)`
  sig { returns(T::Boolean) }
  def user_validation?
    return true if validation_context == :user || validation_context == :individual_trade_screening
    return false if validation_context == :entity || validation_context == :entity_trade_screening

    user_owned?
  end

  # Check for validations that are required for an entity (CToS org, Business) owner
  # Can be forced by using the :entity validation context `valid?(:entity)`
  sig { returns(T::Boolean) }
  def entity_validation?
    return true if validation_context == :entity || validation_context == :entity_trade_screening
    return false if validation_context == :user || validation_context == :individual_trade_screening

    organization_owned? || business_owned?
  end

  # Public: Checks if postal code is required for the record based on the country
  sig { returns(T::Boolean) }
  def postal_code_required_geo?
    ::TradeControls::Countries.postal_code_required_geo?(country_code)
  end

  # Public: Checks if vat code is required for the record based on the country
  sig { returns(T::Boolean) }
  def vat_code_required_geo?
    return false if user_validation?
    ::TradeControls::Countries.vat_code_required_geo?(country_code)
  end

  sig { returns(T.nilable(SponsorsListing)) }
  def sponsors_listing
    return @sponsors_listing if defined?(@sponsors_listing)
    @sponsors_listing = T.let(user&.sponsors_listing, T.nilable(SponsorsListing))
  end

  sig { returns(T.nilable(String)) }
  def fullname
    return "#{first_name}" + " #{middle_name}".rstrip + " #{last_name}".rstrip if user_owned?

    entity_name
  end

  sig { returns(TradeControls::Country) }
  def country
    country_info = Braintree::Address::CountryNames.find do |_, alpha2, _, _|
      alpha2 == country_code
    end
    TradeControls::Country.from_braintree(country_info)
  end

  sig { returns(T::Boolean) }
  def country_is_united_states?
    country.name == "United States of America"
  end

  sig { returns(T.nilable(String)) }
  def us_state
    StatesAndProvinceHelper.find_state(region)
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def metadata
    super || self.metadata = {}
  end

  sig { returns(T.nilable(String)) }
  def screening_status_reason
    metadata["status_reason"]
  end

  sig { returns(Symbol) }
  def hydro_actor
    actor_type = if user_owned?
      :USER
    elsif organization_owned? && T.must(organization).on_standard_terms_of_service?
      :ORGANIZATION
    elsif org_owner_is_on_corporate_tos?
      :CTOS_ORGANIZATION
    elsif business_owned?
      :BUSINESS
    else
      :ACTOR_TYPE_UNKNOWN
    end
  end

  # Public: Compares the actors screening status against the SDN_STATUS_UPDATE_ALLOW_LIST list.
  sig { returns(T::Boolean) }
  def has_update_trade_restrictions?
    AccountScreeningProfile.has_update_trade_restrictions?(screening_status: msft_trade_screening_status)
  end

  sig { params(screening_status: String).returns(T::Boolean) }
  def self.has_update_trade_restrictions?(screening_status:)
    SDN_STATUS_UPDATE_ALLOW_LIST.exclude? screening_status
  end

  # Public: Compares the screening status against the SDN_STATUS_REMOVE_ALLOW_LIST list.
  sig { returns(T::Boolean) }
  def has_delete_pii_trade_restrictions?
    AccountScreeningProfile.has_delete_pii_trade_restrictions?(screening_status: msft_trade_screening_status)
  end

  sig { params(screening_status: String).returns(T::Boolean) }
  def self.has_delete_pii_trade_restrictions?(screening_status:)
    SDN_STATUS_REMOVE_ALLOW_LIST.exclude? screening_status
  end

  sig { params(actor: User).returns(T::Boolean) }
  def remove_billing_information(actor:)
    return false unless owner.is_allowed_to_remove_billing_information?

    owner.remove_all_payment_methods(actor)
    raise AccountScreeningProfileUpdateError.new("Remove payment method failed") if owner.has_valid_payment_method?(feature_type: :noncommercial)

    T.must(user).unlink_contact_from_all_linked_orgs if user_owned?
    raise AccountScreeningProfileUpdateError.new("Unlinking organizations failed") if user_owned? && T.must(user).orgs_linked_to_billing_contact.any?

    PII_DATA_FIELDS.each { |field| self[field] = "" }
    raise AccountScreeningProfileUpdateError.new("Save profile failed") unless save(validate: false)

    # Log the success to Splunk
    GitHub.logger.info("account_screening_profile.remove_billing_information.success",
      "gh.sdn_api_service.owner_type": owner_type,
      "gh.sdn_api_service.status": msft_trade_screening_status,
      "gh.sdn_api_service.external_uuid": external_uuid,
    )

    # destroy the associated billing contact if it exists
    destroy_contacts

    # return true to inform the caller that the clear PII succeeded
    true
  rescue ActiveRecord::ActiveRecordError, AccountScreeningProfileUpdateError => exception
    # Log the failure to Splunk
    GitHub.logger.error("account_screening_profile.remove_billing_information.failed",
      "gh.sdn_api_service.owner_type": owner_type,
      "gh.sdn_api_service.status": msft_trade_screening_status,
      "gh.sdn_api_service.external_uuid": external_uuid,
      "error.message": exception.message,
    )

    # Report the original exception to Sentry
    Failbot.report(exception)

    # return false to inform the caller that the clear PII failed
    false
  end

  # Public: Compares the actors screening status and checks if their profile is delete restricted
  sig { returns(T::Boolean) }
  def delete_restricted?
    return true if is_true_match_restricted?
    AccountScreeningProfile.delete_restricted?(screening_status: msft_trade_screening_status)
  end

  sig { params(screening_status: String).returns(T::Boolean) }
  def self.delete_restricted?(screening_status:)
    SDN_STATUS_DELETE_RESTRICTED_STATUSES.include? screening_status
  end

  # Public: Compares the actors screening status and checks if their profile has a temporary hold status
  sig { returns(T::Boolean) }
  def temporary_status?
    SDN_TEMPORARY_STATUSES.include? msft_trade_screening_status
  end

  # Public: Checks to see if triggering a manual screening for this status is allowed
  sig { returns(T::Boolean) }
  def allowed_to_manually_screen?
    return false if is_true_match_restricted?
    SDN_STATUS_MANUAL_SCREENING_ALLOW_LIST.include? msft_trade_screening_status.to_sym
  end

  # Public: Check to see if a user has a screening status that allows them
  # to have their Sponsors profile automatically approved.
  sig { returns(T::Boolean) }
  def allowed_auto_sponsorship?
    SDN_ALLOWED_AUTO_SPONSORSHIP_LIST.include? msft_trade_screening_status
  end

  sig { params(feature_type: Symbol).returns(T::Boolean) }
  def sdn_status_allowed?(feature_type: :default)
    feature_type = :copilot_vnext if feature_type == :copilot && sdn_copilot_vnext?
    unless FEATURE_TYPE_ALLOW_LISTS.has_key?(feature_type)
      raise ArgumentError, "#{feature_type} is not a valid feature type for SDN checks."
    end
    return false if is_true_match_restricted?
    T.must(FEATURE_TYPE_ALLOW_LISTS[feature_type]).include? msft_trade_screening_status
  end

  sig { returns(T::Boolean) }
  def blocked_status_for_sponsorship_disable?
    return true if is_true_match_restricted?
    SPONSORSHIP_DISABLING_STATUSES.include?(msft_trade_screening_status.to_sym)
  end

  # Public: Checks to see if we should disable autopay for the record owner.
  sig { returns(T::Boolean) }
  def disable_autopay_status?
    return true if is_true_match_restricted?
    DISABLE_AUTOPAY_STATUSES.include?(msft_trade_screening_status.to_sym)
  end

  # Public: Checks to see if we can enable autopay for the record owner.
  # If the record is blocked, we can't enable autopay with the exception of
  # lic_r status where the owner is expected to continue to pay their existing
  # subscriptions normally.
  sig { returns(T::Boolean) }
  def can_enable_autopay?
    sdn_status_allowed?(feature_type: :cost_management)
  end

  sig { returns(T::Boolean) }
  def is_true_match_restricted?
    return false unless true_match?
    return true if !user_owned?
    return true if staff_action?

    owner.sdn_suspended?
  end

  sig { params(actor: T.nilable(User), reason: T.nilable(String)).returns(T.any(T::Boolean, T.self_type)) }
  def destroy(actor: nil, reason: "no reason set")
    return super() unless persisted?

    @actor = T.let(actor, T.nilable(User))
    @reason = T.let(reason, T.nilable(String))

    T.must(user).unlink_contact_from_all_linked_orgs if user_owned?
    owner.remove_all_payment_methods(actor)

    destroy_contacts unless delete_restricted?

    unless sdn_status_allowed?
      enqueue_billing_changes(async: false)
    end
    super()
  end

  sig { returns(T::Boolean) }
  def last_trade_screen_date_less_than_2_days_ago?
    return false if last_trade_screen_date.blank?

    last_trade_screen_date >= 2.days.ago
  end

  sig { returns(T::Boolean) }
  def last_trade_screen_date_less_than_7_days_ago?
    return false if last_trade_screen_date.blank?

    last_trade_screen_date >= 7.days.ago
  end

  sig { returns(T::Boolean) }
  def last_trade_screen_date_older_than_7_days_ago?
    return false if last_trade_screen_date.blank?

    last_trade_screen_date < 7.days.ago
  end

  sig { returns(T::Boolean) }
  def owner_has_requested_llama2_access?
    metadata["llama2_access"].present?
  end

  sig { returns(T::Boolean) }
  def update_marketplace_owner_metadata
    has_listings = owner_has_marketplace_app?
    marketplace_metadata_exists = self.metadata["marketplace_app_owner"]
    return false if has_listings && marketplace_metadata_exists
    return false if !has_listings && !marketplace_metadata_exists

    if has_listings
      self.metadata["marketplace_app_owner"] = true
    else
      self.metadata.delete "marketplace_app_owner"
    end

    true
  end

  # Sends the llama2 access request as long as the account is currently not in hit_in_review status and the request wasn't previously sent
  sig { void }
  def send_llama2_access_request
    return unless user_owned?
    return if hit_in_review?
    return unless owner_has_requested_llama2_access?
    return if metadata["llama2_access"]["dwh_data_sent"] == true

    GlobalInstrumenter.instrument("sdn_llama2.request_made", {
      user_login: T.must(user).display_login,
      user_id: T.must(user).id,
      approval_status: sdn_status_allowed? ? "APPROVED" : "REJECTED",
      external_user_id: external_uuid,
    })

    metadata["llama2_access"]["dwh_data_sent"] = true
    save
  end

  sig { void }
  def rescreen_on_sla_breach
    if valid_for_owner_type? && owner.should_perform_live_sdn_rescreening?
      self.metadata["rescreen_reason"] = "sla_breach"
      owner.perform_live_sdn_screening(force: true, account_screening_profile: self)
    end
  end

  # Adding this to unblock having to add complex checks during the migration to the `Billing::Contact` table
  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def address_validated_at
    billing_address_validated_at
  end

  sig { returns(T::Boolean) }
  def validated_for_sales_tax?
    # At this time, only United States requires the address to be validated
    return true unless country_is_united_states?
    billing_address_validated_at?
  end

  # Public: Checks if the billing information address is valid for tax purposes
  sig { returns(Billing::Public::AddressValidityResponse) }
  def validate_billing_information_for_tax
    return Billing::Public::AddressValidityResponse.new(valid: true, error: "") unless should_validate_for_tax?

    response = Billing::Public.validate_address(
      street: address1.to_s,
      city: city.to_s,
      region: region.to_s,
      postal_code: postal_code.to_s,
      billing_country_code: country_code.to_s,
    )
    if response.valid
      self.postal_code = response.suggested_postal_code unless response.suggested_postal_code.blank?
      self.billing_address_validated_at = GitHub::Billing.timezone.now
    end

    Billing::Public::AddressValidityResponse.new(valid: response.valid, error: response.error)
  end

  alias_method :validate_address, :validate_billing_information_for_tax

  sig { returns(TradeCompliance::TradeScreening::CustomerDetails) }
  def customer_details
    TradeCompliance::TradeScreening::CustomerDetails.new(
      id: request_id,
      first_name: self.first_name,
      last_name: self.last_name,
      entity_name: self.entity_name,
      vat_code: self.vat_code,
      address1: self.address1,
      address2: self.address2,
      city: self.city,
      region: self.region,
      country_code: self.country_code,
      postal_code: self.postal_code
    )
  end

  sig { returns(TradeCompliance::TradeScreening::ScreeningDetails) }
  def screening_details
    raise AccountScreeningProfileUpdateError.new("Screening details can only be generated for persisted records") unless persisted?

    screening_details = TradeCompliance::TradeScreening::ScreeningDetails.new(account_type: account_type, external_id: external_uuid)
    return screening_details if owner.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)

    screening_details.add_customer_details(details: customer_details)
  end

  sig { returns(String) }
  def request_id
    account_type == TradeCompliance::TradeScreening::AccountType::Individual ? "IndName_IndAddr" : "OrgName_OrgAddr"
  end

  # Public: Checks if the record is valid based on the owner type
  sig { params(skip_validation_errors: T::Boolean, owner_type: T.nilable(Symbol)).returns(T::Boolean) }
  def valid_for_owner_type?(skip_validation_errors: false, owner_type: nil)
    symbolized_owner_type = if owner_type.present?
      owner_type
    else
      user_owned? ? :individual_trade_screening : :entity_trade_screening
    end
    record = skip_validation_errors ? self.dup : self
    record.valid?(symbolized_owner_type)
  end

  # Public: Checks if the record is valid based on the owner type
  # This method is the same as #valid_for_owner_type? and is added to allow easier migration to Billing::Contact
  sig { params(skip_validation_errors: T::Boolean, owner_type: T.nilable(Symbol)).returns(T::Boolean) }
  def valid_for_trade_screening?(skip_validation_errors: false, owner_type: nil)
    valid_for_owner_type?(skip_validation_errors:, owner_type:)
  end

  # Returns the owner's contacts excluding the billing address contact
  sig { returns(T::Array[Billing::Contact]) }
  def owner_contacts
    return [] unless customer = owner.customer

    return customer.contacts.to_a if owner.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)

    customer.contacts.reject { |contact| contact.billing? }
  end

  # This is to give the accounts screening profile it's own address type to mimic the
  #   billing contact address type (:billing/:shipping).
  #   TODO: Remove this once the billing information migration is complete.
  sig { returns(String) }
  def address_type
    "billing"
  end

  sig { returns(Billing::ContactUpdateStash) }
  memoize def contact_information_stash
    Billing::ContactUpdateStash.retrieve_stashed_update_for(owner, address_type)
  end

  # enqueues a job to change the user billing settings according to their SDN status
  sig { params(async: T::Boolean).void }
  def enqueue_billing_changes(async: true)
    return unless id.present?
    return if attribute_before_last_save(:id).nil? && msft_trade_screening_status == "not_screened"

    return TradeControls::Sdn::BillingChangesJob.perform_later(id) if async
    TradeControls::Sdn::BillingChangesJob.perform_now(id)
  end

  sig { params(changed_attributes: T::Hash[T.any(String, Symbol), T.untyped]).void }
  def instrument_live_sdn_screening(changed_attributes: saved_changes)
    return unless saved_change_to_last_trade_screen_date? || saved_change_to_msft_trade_screening_status?

    changed_fields = changed_pii_fields || []
    pii_changes = (changed_attributes.keys & PII_DATA_FIELDS).presence || (changed_fields & PII_DATA_FIELDS).presence
    status_reason = (retry? || error? ? screening_status_reason : nil) # include status reason if record failed to screen
    instrument :live_sdn_screening, {
      changed_attributes: pii_changes&.to_sentence,
      screening_status: msft_trade_screening_status,
      status_reason: status_reason
    }

    GitHub.dogstats.increment("sdn.status.error", tags: ["status_reason:#{status_reason}"]) if error?
  end

  sig { returns(T::Boolean) }
  def reset_trade_screening_status
    return true if not_screened?
    return false if has_update_trade_restrictions? || delete_restricted?
    self.msft_trade_screening_status = :not_screened
    save
  end

  private

  sig { returns(T::Boolean) }
  def read_billing_information_from_contacts?
    # It is possible for owner to be nil when we are using an account screening profile in memory for validation
    return true if valid_owner_type? && !owner.nil? && owner.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
    FeatureFlag.vexi.enabled?(:read_billing_information_from_contacts, default: false)
  end

  sig { returns(T::Boolean) }
  def will_save_change_to_trade_screening_status?
    return true if will_save_change_to_msft_trade_screening_status?
    staff_action?
  end

  sig { returns(T::Boolean) }
  def saved_change_to_trade_screening_status?
    return false if self.destroyed?
    return true if saved_change_to_msft_trade_screening_status?

    staff_action?
  end

  sig { returns(T::Boolean) }
  def sdn_copilot_vnext?
    ::TradeControls::Countries.copilot_auth_blocked_countries(actor: owner).exclude?(country)
  end

  # Syncs billing address information changes to the Contact record
  sig { void }
  def sync_to_contact
    return if owner.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
    return if owner.org_is_on_standard_tos?
    return unless saved_change_to_vat_code?

    customer = owner.customer || create_customer
    return unless customer.present?

    customer.update(vat_code: vat_code)
  end

  sig { params(include_self_serve_business_checks: T::Boolean, include_sales_serve_business_checks: T::Boolean).returns(T::Boolean) }
  def exempt_from_validations?(include_self_serve_business_checks: false, include_sales_serve_business_checks: false)
    # When we enable the billing contact flag we will no longer need to check the billing information validations
    #   doing this means that other validation such as `owner_required?` will still be checked
    # TODO: Impliment this properly along with updates to the shared update_trade_screening_record method
    #   Implimenting this right now will not work due to the additional logic in update_trade_screening_record
    #   This will be implimented or updated in a future PR
    # return true if read_billing_information_from_contacts?

    # if the owner is not required, that means we are explicitly validating using the `validation_context`
    # in which case we don't care if they would be exempt from validation, we want to know if the profile is valid or not
    return false unless owner_required?

    return true if internal_attribute_update_only?
    return true if include_self_serve_business_checks && new_business_profile_on_trial?
    # TODO: Remove the following check once we no longer store PII on the trade screening record
    return true if include_sales_serve_business_checks && business_is_sales_serve?
    return true if true_match_validation_exemption?
    lic_r_validation_exemption_for_org?
  end

  sig { returns(TradeCompliance::TradeScreening::AccountType) }
  def account_type
    user_owned? ? TradeCompliance::TradeScreening::AccountType::Individual : TradeCompliance::TradeScreening::AccountType::Business
  end

  # Private: Checks if we should validate the billing information address for tax purposes
  sig { returns(T::Boolean) }
  def should_validate_for_tax?
    return false unless valid_owner_type?
    return false unless country_is_united_states?
    billing_address_validated_at.blank? || changed? && changed.any? { |field| ADDRESS_FIELDS.include?(field) }
  end

  # Private: Check that the owner is an Organization and that the Organization
  # is on the Corporate Terms of Service.
  #
  # This is used instead of calling `org_is_on_business_tos?` which caches the returned value.
  # We have seen issues with caching so this is to avoid that.
  sig { returns(T::Boolean) }
  def org_owner_is_on_corporate_tos?
    organization_owned? && T.must(organization).on_corporate_terms_of_service?
  end

  # Private: Check if the organization is a business owned organization.
  sig { returns(T::Boolean) }
  def org_owner_is_business_owned?
    return false unless organization_owned?
    T.must(organization).delegate_billing_to_business?
  end

  sig { void }
  def validate_org_owner_is_business_owned
    return unless org_owner_is_business_owned?
    return if T.must(organization).enterprise_managed_user_enabled?
    return if internal_attribute_update_only? || no_billing_information? || staff_action?
    errors.add(:base, "Business owned organizations cannot have billing information")
  end

  sig { returns(T::Boolean) }
  def no_billing_information?
    PII_DATA_FIELDS.all?(&:blank?)
  end

  sig { returns(T::Boolean) }
  def staff_action?
    !!screening_status_reason&.include?(TradeControls::AbstractTradeScreeningDependency::STAFF_ACTION)
  end

  # Private: Ensure that the record owner is a Business or User (Organization is also a User) on save.
  sig { void }
  def valid_owner_type
    return if valid_owner_type?
    errors.add(:owner, "must be an enterprise account or user")
  end

  sig { returns(T::Boolean) }
  def valid_owner_type?
    %w[Business User].include?(owner_type)
  end

  # Private: Validates whether the profile update is allowed to proceed.
  # There are a few types of updates that can occur. One is the user data update,
  # the other is the internal attributes update (like updating the SDN status).
  # In the case of a non-restrictive SDN status, all updates are allowed.
  # In the case of a restrictive SDN status, only updates to internal attributes are allowed.
  # In the case of a pseudo record, all updates are allowed unless it's a true_match status.
  sig { void }
  def valid_updates_allowed
    return if new_record?
    return unless self.owner.live_sdn_screening_enabled?
    # In the edge case where we try and update a screening status with the same value:
    # - Will fall into this callback as will_save_change_to_msft_trade_screening_status? is not true
    # - We may be updating i.e true match to true match, so it would raise the exception
    return unless changed?

    unless !has_update_trade_restrictions? || internal_attribute_update_only? || allowed_to_update_pseudo_record?
      errors.add(:updates_restricted, "Current account restrictions do not allow billing information updates.")
    end
  end

  # Private: Checks if normal validations on create should be excluded for an LIC-R
  # screened organization. These orgs can only have lic_r or no_hit status
  sig { returns(T::Boolean) }
  def lic_r_validation_exemption_for_org?
    # We want to allow the on create no_hit to go through, as that's only created by our internal
    # systems, whereas customers creating a record always start with a not_screened
    return false unless new_record? || internal_attribute_update_only?

    allowed_to_update_pseudo_record?
  end

  # Private: Checks if updates to a pseudo record are allowed
  sig { returns(T::Boolean) }
  def allowed_to_update_pseudo_record?
    return false unless organization_owned?
    return false unless changed?

    lic_r? || no_hit?
  end

  # Private: Checks if normal validations on create should be excluded for a True-Match
  # screened owner. These owners can only have true_match or no_hit status
  sig { returns(T::Boolean) }
  def true_match_validation_exemption?
    return false unless valid_owner_type?
    return false unless changed?

    # during creation, id is nil at this point, so we use that to determine if this is an on create or on update
    # validation. We want to allow the on create no_hit to go through, as that's only created by our internal
    # systems, whereas customers creating a record always start with a not_screened
    return false unless new_record? || internal_attribute_update_only?

    true_match? || no_hit?
  end

  # Private: Only personal profiles with specific statuses (see SDN_STATUS_DELETE_RESTRICTED_STATUSES)
  # are allowed to delete their information
  sig { void }
  def ensure_personal_profile_deletion_is_allowed
    if delete_restricted?
      raise AccountScreeningProfileDeleteError.new("Current SDN status does not allow personal profile deletion")
    end
  end

  # Private: Check if the changes in the model are only for internal attributes
  sig { returns(T::Boolean) }
  def internal_attribute_update_only?
    self.changed? && (self.changed - INTERNAL_ATTRIBUTES).empty?
  end

  # Private: Used to ensure metadata json column is not storing empty values
  sig { void }
  def filter_metadata
    filtered_metadata = metadata
    filtered_metadata = filtered_metadata.delete_if { |k, v| k.blank? || v.blank? }
    filtered_metadata = nil if filtered_metadata.blank?

    self.metadata = filtered_metadata
  end

  sig { returns(T::Boolean) }
  def owner_has_marketplace_app?
    return false if business_owned? # businesses can create integrations but can't be listed on the marketplace

    owner = T.cast(self.owner, T.any(User, Organization))
    Marketplace::Listing
      .where(listable: [owner.integrations, owner.oauth_applications])
      .any?
  end

  # Private: Sets the last_trade_screen_date for the record
  # when msft_trade_screening_status is updated
  sig { returns(Time) }
  def set_last_trade_screen_date
    self[:last_trade_screen_date] = Time.now.utc
  end

  # Creates a customer record for the owner of the account screening profile
  sig { returns(T.nilable(Customer)) }
  def create_customer
    result = GitHub::Billing.create_customer_service(owner, actor: User.ghost).perform
    if result.success?
      GitHub.dogstats.increment("sync_billing_info.new_customer_created")
      result.customer
    else
      Failbot.report(
        CreateCustomerError.new("Failed to create customer for target ID #{owner.id}"),
        trade_screening_record_id: external_uuid,
        errors: result.error_message
      )
      nil
    end
  end

  # Rescreen customer if they made an update to their PII data
  sig { void }
  def rescreen_on_pii_update
    changed_pii_fields = saved_changes.keys & RESCREEN_PII_FIELDS
    return unless changed_pii_fields.any?
    return if owner.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
    return unless owner.should_perform_live_sdn_rescreening?
    return unless owner.valid_trade_screening_details?

    self.changed_pii_fields = changed_pii_fields
    self.metadata["rescreen_reason"] = "pii_update"
    owner.perform_live_sdn_screening(force: true, account_screening_profile: self)
  end

  # Private: Reports to Datadog if a user changes from hit_in_review to an allowed/disallowed status
  # when msft_trade_screening_status is updated
  sig { void }
  def track_status_change
    if !has_update_trade_restrictions?
      GitHub.dogstats.increment(
        "sdn.status.to_allowed_to_update",
        tags: [
          "previous_status:#{msft_trade_screening_status_was}",
          "current_status:#{msft_trade_screening_status}"
        ],
      )
    else
      GitHub.dogstats.increment(
        "sdn.status.to_not_allowed_to_update",
        tags: [
          "previous_status:#{msft_trade_screening_status_was}",
          "current_status:#{msft_trade_screening_status}"
        ],
      )
    end
  end

  # Private: Sends an email if status changes from hit_in_review to an allowed/disallowed status
  # when msft_trade_screening_status is updated
  sig { void }
  def send_overdue_email
    return unless msft_trade_screening_status_changed?(from: "hit_in_review")

    if !has_update_trade_restrictions?
      if msft_trade_screening_status == "data_issue"
        owner.send_trade_controls_data_needs_fixing_status_email
      else
        owner.send_trade_controls_allowed_status_email
      end
    elsif !is_true_match_restricted?
      owner.send_trade_controls_not_allowed_status_email
    end
  end

  # private: Clears the status_reason field in the metadata attribute if the msft_trade_screening_status changes but status reason doesn't
  sig { void }
  def reset_status_reason
    return if self.data_issue?
    return if self.metadata_was.blank?
    return if screening_status_reason.blank?
    return unless screening_status_reason == self.metadata_was["status_reason"]

    self.metadata.delete("status_reason")
  end

  # private: Sends an email when the new_org_creation context resets
  sig { void }
  def send_email_when_new_org_context_resets
    return unless organization_owned?
    return unless self.metadata["screening_context"] == "new_org_creation"

    if sdn_status_allowed?
      T.must(organization).send_trade_controls_restricted_free_org_allowed_email
    end
  end

  # Private: Update metadata flag based on the restricted status
  sig { void }
  def reset_screening_context
    return if hit_in_review?
    return if true_match?
    return if self.metadata_was.blank?
    return unless self.metadata.key?("screening_context")

    send_email_when_new_org_context_resets
    self.metadata.delete "screening_context"
  end

  # Private: Sets a uuid for external systems to reference when the AccountScreeningProfile
  # record is first created.
  sig { returns(String) }
  def set_external_uuid
    self.external_uuid ||= SecureRandom.uuid
  end

  sig { void }
  def set_data_issue_status_reason_if_missing
    return unless self.data_issue?

    return if screening_status_reason.present?

    self.metadata["status_reason"] = "Data Issue - Missing"

    log_missing_status_reason
  end

  sig { void }
  def log_missing_status_reason
    GitHub.dogstats.increment(
      "sdn.status_reason.missing",
      tags: ["status:#{msft_trade_screening_status}"],
    )
  end

  sig { void }
  def instrument_creation
    instrument :create
  end

  sig { void }
  def instrument_update
    instrument :update

    self.instrument_live_sdn_screening
    self.instrument_trade_screening_record_link
  end

  sig { void }
  def instrument_trade_screening_record_link
    return unless saved_change_to_last_trade_screen_date? || saved_change_to_msft_trade_screening_status?
    return unless user_owned?
    user = T.must(self.user)

    user.orgs_linked_to_billing_contact.each do |org|
      Billing::ContactLinkManager.instrument_action(address_type: :Billing,
        actor: user,
        org: org,
        action: :UPDATE,
        new_id: user.billing_contact.id,
        old_status: msft_trade_screening_status_before_last_save,
        new_status: msft_trade_screening_status)
    end if user.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
    user.orgs_linked_to_billing_contact.each do |org|
      TradeControls::ScreeningRecordLinkManager.instrument_action(actor: user,
        org: org,
        action: :UPDATE,
        new_id: self.id,
        old_status: msft_trade_screening_status_before_last_save,
        new_status: msft_trade_screening_status)
    end unless user.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
  end

  sig { void }
  def instrument_deletion
    instrument :destroy, account_screening_profile_id: id, actor: @actor, reason: @reason
  end

  # Mark a user as not spammy and unsuspend the account when receiving an allowed status
  # from the SDN (specially designated nationals) database
  #
  # A sdn allowed status means that we (GitHub) can do business with the actor
  # we need to ensure that the user is not hidden (not spammy) and unsuspended
  sig { void }
  def unsuspend_on_status_change_from_true_match
    return unless msft_trade_screening_status_changed?(from: "true_match")

    # we don't need to call unsuspend if the action was staff triggered, since it's already called
    return if staff_action?

    owner.sdn_unsuspend(staff_user: User.staff_user, reason: "User was moved out of true match in the SDN database")
  end

  # Default instrumentation payload for AccountScreeningProfile
  sig { returns(T::Hash[Symbol, T.any(String, User)]) }
  def event_payload
    payload = {
      external_uuid: external_uuid,
    }

    # this is the actor prefix for our own instrumentation
    payload[hydro_actor.downcase] = owner

    # this is the hydro prefix to ensure that logs show up in the audit logs UI
    payload[owner.event_prefix] = owner
    payload
  end

  sig { void }
  def enqueue_status_sla_check_job
    return unless hit_in_review?
    return unless owner.valid_trade_screening_details?
    TradeCompliance::TradeScreening::ScreeningStatusSlaCheckJob.enqueue(id)
  end

  sig { void }
  def enqueue_check_sponsors_listing_job
    return unless GitHub.sponsors_enabled?
    return unless sponsors_listing
    TradeControls::Sdn::EnableOrDisableMaintainerJob.perform_later(self.id)
  end

  sig { returns(T::Boolean) }
  def pii_data_changed?
    (saved_changes.keys & PII_DATA_FIELDS).any?
  end

  sig { void }
  def destroy_contacts
    return unless customer = owner.customer

    customer.update(vat_code: nil)
    customer.contacts.delete_all
  end

  sig { void }
  def update_customer_in_billing_platform
    return unless customer = owner.customer
    Billing::UpdateCustomerInBillingPlatformJob.perform_later(customer)
  end
end
