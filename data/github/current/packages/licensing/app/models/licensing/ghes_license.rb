# typed: strict
# frozen_string_literal: true

require "enterprise/crypto"
require "securerandom"

class Licensing::GhesLicense < ApplicationRecord::Domain::LicensingCollab
  include GitHub::Memoizer
  include Instrumentation::Model

  LICENSE_STATES = T.let(%w(pending active canceled).map(&:freeze).freeze, T::Array[String])
  LICENSE_TYPES  = T.let(%w(evaluation perpetual unlimited standard).map(&:freeze).freeze, T::Array[String])

  SERVER_KEYS_CONTAINER = "licensing-ghes-server-keys"

  validates_presence_of :business
  validates_inclusion_of :state, in: LICENSE_STATES
  validates_inclusion_of :license_type, in: LICENSE_TYPES
  validates_uniqueness_of :reference_number

  belongs_to :business

  after_create_commit :instrument_creation
  after_create_commit :enqueue_generate_job

  sig { params(business: Business, reference_number: String).returns(Licensing::GhesLicense) }
  def self.create_metered_ghes_license(business:, reference_number: SecureRandom.hex(3))
    GitHub.dogstats.distribution_time("create_metered_ghes_license.create_ghes_license.time") do
      create!(
        business: business,
        reference_number: reference_number,
        seats: business.consumed_ghec_only_users_access_licenses,
        advanced_security_enabled: true,
        advanced_security_seats: 0,
        code_security_enabled: business.advanced_security_purchased? && !business.advanced_security_products_bundled?,
        code_security_licenses: 0,
        secret_protection_enabled: business.advanced_security_purchased? && !business.advanced_security_products_bundled?,
        secret_protection_licenses: 0,
        expires_at: 1.year.from_now,
        license_type: :standard,
        metered: true,
        state: :active,
      )
    end
  end

  sig { void }
  def generate_server_license_key
    log_context = {
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.business.id" => business_id,
      "gh.ghes_license.id" => id,
      "gh.ghes_license.reference_number" => reference_number,
      "gh.ghes_license.seats" => seats,
    }
    GitHub.logger.with_named_tags(log_context) do
      GitHub.dogstats.distribution_time("create_metered_ghes_license.generate_server_license_key.time") do
        begin
          generator = Licensing::GhesLicense::LicenseKeyGenerator.new(self)
          generator.generate!
          azure_blob_client.upload(
            SERVER_KEYS_CONTAINER,
            license_key_file_name,
            T.must(generator.license_key)
          )
          GitHub.logger.info("Successfully generated server license key")
        rescue Licensing::AzureBlobClient::UploadError, Licensing::AzureBlobClient::GetBlobError, Enterprise::Crypto::Error => e
          GitHub.logger.error("Failed to generate server license key", e)
          Failbot.report(e)
        end
      end
    end
  end

  sig { returns(T.nilable(String)) }
  def license_key
    (blob, content) = azure_blob_client.get_blob(SERVER_KEYS_CONTAINER, license_key_file_name)
    instrument_download
    content
  end

  sig { returns(String) }
  def license_key_file_name
    "github-enterprise-#{reference_number}.ghl"
  end

  sig { returns(String) }
  def job_id
    Licensing::GenerateMeteredServerLicenseJob.job_id(id)
  end

  private

  sig { returns(Licensing::AzureBlobClient) }
  memoize def azure_blob_client
    Licensing::AzureBlobClient.new
  end

  sig { void }
  def enqueue_generate_job
    Licensing::GenerateMeteredServerLicenseJob.perform_later(id)
  end

  sig { void }
  def instrument_creation
    instrument :create
  end

  sig { void }
  def instrument_download
    instrument :download
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def event_payload
    {
      business: business,
      business_id: business_id,
      license_id: id,
      reference_number: reference_number,
      metered: metered,
      seats: seats,
      advanced_security_enabled: advanced_security_enabled,
      advanced_security_seats: advanced_security_seats,
      code_security_enabled: code_security_enabled,
      code_security_licenses: code_security_licenses,
      secret_protection_enabled: secret_protection_enabled,
      secret_protection_licenses: secret_protection_licenses,
      license_expires_at: expires_at,
    }
  end

  sig { returns(Symbol) }
  def event_prefix
    :ghes_license
  end
end
