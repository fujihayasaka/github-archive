# typed: true
# frozen_string_literal: true

class MultiTenantProvisioningRequest < ApplicationRecord::Domain::Users
  include GitHub::Validations

  TenantProvisioningError = Class.new(StandardError)

  MAX_NAME_LENGTH = 60
  SUBDOMAIN_REGEX = /\A[a-z0-9]+(-[a-z0-9]+)*\z/i
  SUBDOMAIN_VALIDATION_MESSAGE = "may only contain alphanumeric characters or single hyphens, and cannot begin or end with a hyphen"
  MIN_SUBDOMAIN_LENGTH = 3
  MAX_SUBDOMAIN_LENGTH = 60
  MAX_INDUSTRY_LENGTH = 64
  MAX_OTHER_INDUSTRY_LENGTH = 255
  MAX_NUMBER_OF_SEATS_LENGTH = 16
  MAX_COUNTRY_CODE_LENGTH = 3
  MAX_ADMIN_NAME_LENGTH = 255
  MAX_WORK_EMAIL_LENGTH = 255
  HUMANIZED_ATTRIBUTES = T.let(
    {
      name: "Enterprise name",
      subdomain: "Subdomain",
      industry: "Industry",
      other_industry: "Other industry",
      number_of_seats: "Number of seats",
      country_code: "Country",
      data_hosting_region: "Data hosting",
      provisioning_steps: "Provisioning step",
      emu_idp: "Identity provider",
      admin_name: "Admin name",
      admin_work_email: "Admin work email",
      trial_terms: "Terms"
    }.freeze, T::Hash[Symbol, String]
  )

  enum :data_hosting_region, {
    prod_weu_01: 0,
    prod_ae_01: 1,
    prod_cus_01: 2,
    prod_sdc_01: 3,
    staff_wus2_01: 4,
  }, default: :prod_weu_01, validate: true

  enum :provisioning_step, {
    pending: 0,
    in_progress: 1,
    completed: 2,
    failed: 3
  }, default: :pending, validate: true

  belongs_to :created_by, class_name: "User"

  attr_accessor :emu_idp, :trial_terms
  alias_attribute :employees_size, :number_of_seats
  alias_attribute :billing_full_name, :admin_name
  alias_attribute :billing_email, :admin_work_email
  attribute :staff_owned, :boolean, default: false
  attribute :marketing_consent, :boolean, default: false

  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
  validates :subdomain,
    presence: true,
    length: { in: MIN_SUBDOMAIN_LENGTH..MAX_SUBDOMAIN_LENGTH },
    format: { with: SUBDOMAIN_REGEX, message: SUBDOMAIN_VALIDATION_MESSAGE },
    uniqueness: {
      case_sensitive: false,
      message: "is already taken"
    }

  validates :industry, :number_of_seats, :country_code, :data_hosting_region, presence: { message: "must be selected" }
  validates :emu_idp, presence: { message: "must be selected" }, on: :create
  validates :industry, length: { maximum: MAX_INDUSTRY_LENGTH }
  validates :other_industry, length: { maximum: MAX_OTHER_INDUSTRY_LENGTH }
  validates :number_of_seats, length: { maximum: MAX_NUMBER_OF_SEATS_LENGTH }
  validates :country_code, length: { maximum: MAX_COUNTRY_CODE_LENGTH }
  validates :provisioning_step, presence: true
  validates :admin_name, presence: true, length: { maximum: MAX_ADMIN_NAME_LENGTH }
  validates :admin_work_email,
    presence: true,
    length: { maximum: MAX_WORK_EMAIL_LENGTH },
    format: {
      with: User::EMAIL_REGEX,
      message: "does not look like an email address",
    }

  scope :in_progress, -> { where(provisioning_step: :in_progress) }

  def self.human_attribute_name(attr, options = {})
    HUMANIZED_ATTRIBUTES[attr.to_sym] || super
  end

  def target_for_conditional_access
    created_by
  end

  def provision_tenant
    GitHub.dogstats.increment(
      "proxima.api.tenantmetadata.provision_client.total_requests"
      )
    client = Proxima::Api::TenantMetadataClient.new

    payload = {
      stamp: data_hosting_region.to_s.gsub("_", "-"),
      enterprise_request: {
        name: name,
        slug: subdomain,
        seats: Billing::EnterpriseCloudTrial::INITIAL_SEAT_COUNT,
        billing_end_date: (GitHub::Billing.today + 1.month).rfc3339,
        first_admin_user_email: admin_work_email,
        can_self_serve: true,
        trial_expires_at: (Time.current + Billing::EnterpriseCloudTrial.trial_length).rfc3339,
        billing_email: admin_work_email,
        is_staff_owned: staff_owned?
      },
      creator_username: "self-serve-form",
      is_stafftools: false
    }

    response = client.connection.post("/twirp/v0.TenantService/ProvisionTenant", payload.to_json)

    raise TenantProvisioningError unless response.success?
    response_body = JSON.parse(response.body)

    if response_body["result"] == "Success"
      self.provisioning_step = :in_progress
    else
      process_errors(response_body["error_messages"])
    end
  rescue Faraday::Error, JSON::ParserError, TenantProvisioningError => error
    Failbot.report(error)
    GitHub.dogstats.increment(
        "proxima.api.tenantmetadata.provision_client.failed_requests"
      )
  end

  def self.check_tenant_subdomain_validity(subdomain)
    client = Proxima::Api::TenantMetadataClient.new

    payload = {
      slug: subdomain
    }

    response = client.connection.post("/twirp/v0.TenantService/ValidateSlug", payload.to_json)

    return unless response.success?
    result = JSON.parse(response.body)["result"]
    return if result == "Valid"

    if result == "Invalid_Reserved" || result == "Invalid_AlreadyTaken"
      "is already taken"
    else
      "is invalid"
    end
  rescue Faraday::Error, JSON::ParserError => error
    Failbot.report(error)
  end

  private

  def process_errors(array)
    if array&.intersection(["Tenant already exists", "Slug is reserved and cannot be used"]).present?
      self.errors.add(:subdomain, "is already taken")
    end
  end
end
