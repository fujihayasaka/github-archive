# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::GhesLicense::LicenseKeyGeneratorTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @business = create(:business)
  end

  setup do
    Enterprise::Crypto.customer_vault = Licensing::GhesLicense::LicenseKeyGenerator.customer_vault
    Enterprise::Crypto.license_vault  = Licensing::GhesLicense::LicenseKeyGenerator.license_vault
  end

  context "#generate!" do
    test "uses the fields from the ghes_license to generate a license key" do
      customer = Enterprise::Crypto::Customer.generate(@business.name, "test@example.com", Licensing::GhesLicense::LicenseKeyGenerator.customer_vault)
      existing_ghes_keypair = Licensing::GhesKeypair.new(
        business_id: @business.id.to_s,
        secret_key_data: customer.secret_key_data,
        public_key_data: customer.public_key_data,
      )
      Licensing::GhesKeypair.expects(:get_by_business_id).with(@business.id.to_s).returns(existing_ghes_keypair).once

      ghes_license = create(
        :licensing_ghes_license,
        business: @business,
        metered: true,
        advanced_security_enabled: true,
        seats: 5,
      )
      generator = Licensing::GhesLicense::LicenseKeyGenerator.new(ghes_license)
      generator.generate!

      validate_license_key(generator.license_key, ghes_license)
    end

    test "uses the existing ghes_keypair when it already exists" do
      customer = Enterprise::Crypto::Customer.generate(@business.name, "test@example.com", Licensing::GhesLicense::LicenseKeyGenerator.customer_vault)
      existing_ghes_keypair = Licensing::GhesKeypair.new(
        business_id: @business.id.to_s,
        secret_key_data: customer.secret_key_data,
        public_key_data: customer.public_key_data,
      )
      Licensing::GhesKeypair.expects(:get_by_business_id).with(@business.id.to_s).returns(existing_ghes_keypair).once

      ghes_license = create(:licensing_ghes_license, business_id: @business.id)
      generator = Licensing::GhesLicense::LicenseKeyGenerator.new(ghes_license)
      generator.generate!

      validate_license_key(generator.license_key, ghes_license)
    end

    test "creates a new ghes_keypair when it does not exist" do
      Licensing::GhesKeypair.expects(:get_by_business_id).with(@business.id.to_s).returns(nil).once
      Licensing::GhesKeypair.any_instance.stubs(:save!).once

      ghes_license = create(:licensing_ghes_license, business_id: @business.id)
      generator = Licensing::GhesLicense::LicenseKeyGenerator.new(ghes_license)
      generator.generate!

      validate_license_key(generator.license_key, ghes_license)
    end

    test "creates a new ghes_keypair when the customer name on the existing one does not match the business.name anymore" do
      customer = Enterprise::Crypto::Customer.generate(@business.name, "test@example.com", Licensing::GhesLicense::LicenseKeyGenerator.customer_vault)
      existing_ghes_keypair = Licensing::GhesKeypair.new(
        business_id: @business.id.to_s,
        secret_key_data: customer.secret_key_data,
        public_key_data: customer.public_key_data,
      )
      Licensing::GhesKeypair.expects(:get_by_business_id).with(@business.id.to_s).returns(existing_ghes_keypair).once
      Licensing::GhesKeypair.any_instance.stubs(:save!).once

      @business.update(name: "new name")
      ghes_license = create(:licensing_ghes_license, business_id: @business.id)
      generator = Licensing::GhesLicense::LicenseKeyGenerator.new(ghes_license)
      generator.generate!

      validate_license_key(generator.license_key, ghes_license)
    end
  end

  def validate_license_key(license_key, ghes_license)
    license = Enterprise::Crypto::License.load(license_key)
    assert_equal ghes_license.reference_number, license.metadata["reference_number"]
    assert_equal ghes_license.metered, license.metered?
    assert_equal ghes_license.business.name, license.company
    assert_equal ghes_license.seats, license.seats
    assert_equal ghes_license.advanced_security_enabled, license.advanced_security_enabled?
    assert_equal ghes_license.advanced_security_seats, license.advanced_security_seats
    assert_same_time ghes_license.expires_at, license.expire_at
  end
end
