# typed: true
# frozen_string_literal: true

class MultiTenantProvisioningRequest < ApplicationRecord::Domain::Users
  include GitHub::Validations

  MAX_NAME_LENGTH = 60
  SUBDOMAIN_REGEX = /\A[a-z0-9]+(-[a-z0-9]+)*\z/i
  SUBDOMAIN_VALIDATION_MESSAGE = "may only contain alphanumeric characters or single hyphens, and cannot begin or end with a hyphen"
  MIN_SUBDOMAIN_LENGTH = 3
  MAX_SUBDOMAIN_LENGTH = 32
  MAX_INDUSTRY_LENGTH = 64
  MAX_NUMBER_OF_SEATS_LENGTH = 16
  MAX_COUNTRY_CODE_LENGTH = 3
  MAX_ADMIN_NAME_LENGTH = 255
  MAX_WORK_EMAIL_LENGTH = 255
  HUMANIZED_ATTRIBUTES = T.let(
    {
      name: "Enterprise name",
      subdomain: "Subdomain",
      industry: "Industry",
      number_of_seats: "Number of employees",
      country_code: "Country",
      data_hosting_region: "Region for data hosting",
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
    prod_sdc_01: 2,
  }, default: :prod_weu_01, validate: true

  enum :provisioning_step, {
    requested: 0
  }, default: :requested, validate: true

  belongs_to :created_by, class_name: "User"

  attr_accessor :emu_idp, :trial_terms
  alias_attribute :employees_size, :number_of_seats
  alias_attribute :billing_full_name, :admin_name
  alias_attribute :billing_email, :admin_work_email

  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
  validates :subdomain,
    presence: true,
    length: { in: MIN_SUBDOMAIN_LENGTH..MAX_SUBDOMAIN_LENGTH },
    format: { with: SUBDOMAIN_REGEX, message: SUBDOMAIN_VALIDATION_MESSAGE },
    uniqueness: {
      case_sensitive: false,
      message: "is already taken"
    }

  validates :industry, :number_of_seats, :country_code, :data_hosting_region, :emu_idp,
    presence: { message: "must be selected" }
  validates :industry, length: { maximum: MAX_INDUSTRY_LENGTH }
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

  def self.human_attribute_name(attr, options = {})
    HUMANIZED_ATTRIBUTES[attr.to_sym] || super
  end

  def target_for_conditional_access
    created_by
  end
end
