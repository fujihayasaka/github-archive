# typed: strict
# frozen_string_literal: true

require "enterprise/crypto"
require "securerandom"

class Licensing::GhesLicense::LicenseKeyGenerator

  include GitHub::Memoizer

  KEYS_PATH = T.let(GitHub::AppEnvironment.root.join("enterprise"), Pathname)

  CUSTOMER_SECRET_KEY = T.let(KEYS_PATH.join("customer", "gpg", "secring.gpg"), Pathname)
  CUSTOMER_PUBLIC_KEY = T.let(KEYS_PATH.join("customer", "gpg", "pubring.gpg"), Pathname)

  LICENSE_SECRET_KEY = T.let(KEYS_PATH.join("license", "gpg", "secring.gpg"), Pathname)
  LICENSE_PUBLIC_KEY = T.let(KEYS_PATH.join("license", "gpg", "pubring.gpg"), Pathname)

  sig { returns(Licensing::GhesLicense) }
  attr_reader :ghes_license

  sig { returns(T.nilable(String)) }
  attr_reader :license_key

  delegate :business, to: :ghes_license

  sig { returns(Enterprise::Crypto::CustomerVault) }
  def self.customer_vault
    Enterprise::Crypto::CustomerVault.new(CUSTOMER_SECRET_KEY.read, CUSTOMER_PUBLIC_KEY.read, blank_password: true)
  end

  sig { returns(Enterprise::Crypto::LicenseVault) }
  def self.license_vault
    Enterprise::Crypto::LicenseVault.new(LICENSE_SECRET_KEY.read, LICENSE_PUBLIC_KEY.read, blank_password: true)
  end

  sig { params(ghes_license: Licensing::GhesLicense).void }
  def initialize(ghes_license)
    @ghes_license = T.let(ghes_license, Licensing::GhesLicense)
    @license_key = T.let(nil, T.nilable(String))
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  memoize def metadata
    {
      reference_number: ghes_license.reference_number,
      company: business.name,
      seats: ghes_license.seats,
      metered: ghes_license.metered,
      ssh_allowed: true,
      cluster_support: false, # Not allowed to be set for now but we can support setting it from stafftools if needed
      croquet_support: true, # Connect support is required for metered GHES
      support_key: false, # Not allowed to be set for now but we can support setting it from stafftools if needed
      unlimited_seating: false, # Can never be true for metered GHES
      perpetual: false, # Can never be true for metered GHES
      evaluation: false, # Can never be true for metered GHES
      insights_enabled: false,
      insights_expire_at: ghes_license.expires_at,
      advanced_security_enabled: ghes_license.advanced_security_enabled,
      advanced_security_seats: ghes_license.advanced_security_seats,
      code_security_enabled: ghes_license.code_security_enabled,
      code_security_licenses: ghes_license.code_security_licenses,
      secret_protection_enabled: ghes_license.secret_protection_enabled,
      secret_protection_licenses: ghes_license.secret_protection_licenses,
    }
  end

  sig { void }
  def generate!
    # Include the elasticsearch license as a file if available in environment
    files = {}
    if ENV["ELASTICSEARCH_LICENSE"].present?
      files["elasticsearch_license.json"] = ENV["ELASTICSEARCH_LICENSE"]
    end

    customer = find_or_generate_enterprise_crypto_customer_from_keypair
    license = customer.generate_license(
      ghes_license.seats,
      ghes_license.expires_at,
      nil,
      metadata
    )

    @license_key = license.to_bin(self.class.license_vault)
  end

  private

  sig { returns(Enterprise::Crypto::Customer) }
  def find_or_generate_enterprise_crypto_customer_from_keypair
    if ghes_keypair = Licensing::GhesKeypair.get_by_business_id(business.id.to_s)
      customer = Enterprise::Crypto::Customer.from(ghes_keypair.secret_key_data, ghes_keypair.public_key_data, self.class.customer_vault)
      return customer if customer.name == business.name
    end
    email = "business-#{business.id}@github.com"
    customer = Enterprise::Crypto::Customer.generate(business.name, email, self.class.customer_vault)
    Licensing::GhesKeypair.new(
      business_id: business.id.to_s,
      secret_key_data: customer.secret_key_data,
      public_key_data: customer.public_key_data,
    ).save!
    customer
  end
end
