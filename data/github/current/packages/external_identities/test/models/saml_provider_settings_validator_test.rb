# typed: true
# frozen_string_literal: true

require "test_helper"

class SamlProviderSettingsValidatorTest < GitHub::TestCase
  fixtures do
    @org = create :organization
    @business = create :business
    @business_admin = @business.owners.first
    @valid_cert = Rails.root.join("test/fixtures/misc/saml/okta.pem").read
    @org_provider = Organization::SamlProvider.create(
      organization: @org,
      sso_url: "http://example.com/sso",
      issuer: "http://example.com",
      idp_certificate: @valid_cert,
    )
    @org_provider_test_settings = Organization::SamlProviderTestSettings.create(
      user: @org.admin,
      organization: @org,
      sso_url: "http://example.com/sso",
      issuer: "http://example.com",
      idp_certificate: @valid_cert,
      status: Organization::SamlProviderTestSettings::SUCCESS,
    )
    @business_provider = Business::SamlProvider.create(
      business: @business,
      sso_url: "http://example.com/sso",
      issuer: "http://example.com",
      idp_certificate: @valid_cert,
    )
    @business_provider_test_settings = Business::SamlProviderTestSettings.create(
      user: @business_admin,
      business: @business,
      sso_url: "http://example.com/sso",
      issuer: "http://example.com",
      idp_certificate: @valid_cert,
      status: Business::SamlProviderTestSettings::SUCCESS,
    )
  end

  context "org provider test settings" do
    context "validating sso_url" do
      test "rejects nil" do
        @org_provider_test_settings.sso_url = nil

        refute_predicate @org_provider_test_settings, :valid?
        refute_predicate @org_provider_test_settings.errors[:sso_url], :empty?
      end

      test "rejects invalid URLs" do
        @org_provider_test_settings.sso_url = "not a valid URL"

        refute_predicate @org_provider_test_settings, :valid?
        refute_predicate @org_provider_test_settings.errors[:sso_url], :empty?
      end
    end

    context "validating IdP Certificates" do
      test "rejects nil" do
        @org_provider_test_settings.idp_certificate = nil

        refute_predicate @org_provider_test_settings, :valid?
        refute_predicate @org_provider_test_settings.errors[:idp_certificate], :empty?
      end

      test "rejects invalid certificates" do
        @org_provider_test_settings.idp_certificate = "invalid cert"

        refute_predicate @org_provider_test_settings, :valid?
        refute_predicate @org_provider_test_settings.errors[:idp_certificate], :empty?
      end
    end

    context "validating settings changes when a user is required to 'Test SAML settings' on them" do
      test "always accpept test provider changes (it can't require testing)" do
        @org_provider_test_settings.sso_url = "https://other.example.com"
        assert_predicate @org_provider_test_settings, :valid?
      end

      test "always validates if no configurable properties changed" do
        @org_provider.user_that_must_test_settings = @org.admin
        assert_predicate @org_provider, :valid?
      end

      test "accepts sso_url change with a matching, successful test" do
        @org_provider_test_settings.sso_url = "https://other.example.com/sso"
        @org_provider_test_settings.save!
        @org_provider.user_that_must_test_settings = @org.admin
        @org_provider.sso_url = "https://other.example.com/sso"
        assert_predicate @org_provider, :valid?
      end

      test "accepts issuer change with a matching, successful test" do
        @org_provider_test_settings.issuer = "https://other.example.com"
        @org_provider_test_settings.save!
        @org_provider.user_that_must_test_settings = @org.admin
        @org_provider.issuer = "https://other.example.com"
        assert_predicate @org_provider, :valid?
      end

      test "accepts idp_certificate change with a matching, successful test" do
        @org_provider_test_settings.idp_certificate = Rails.root.join("test/fixtures/misc/saml/azure.pem").read
        @org_provider_test_settings.save!
        @org_provider.user_that_must_test_settings = @org.admin
        @org_provider.idp_certificate = Rails.root.join("test/fixtures/misc/saml/azure.pem").read
        assert_predicate @org_provider, :valid?
      end

      test "does not consider an idp_certificate 'changed' if it only differs on extra whitespace" do
        @org_provider.user_that_must_test_settings = @org.admin
        @org_provider.idp_certificate = Rails.root.join("test/fixtures/misc/saml/okta_with_spaces.pem").read
        assert_predicate @org_provider, :valid?
      end

      test "rejects sso_url change without a matching, successful test" do
        @org_provider.user_that_must_test_settings = @org.admin
        @org_provider.sso_url = "https://other.example.com/sso"

        refute_predicate @org_provider, :valid?
        refute_predicate @org_provider.errors[:sso_url], :empty?
      end

      test "rejects issuer change without a matching, successful test" do
        @org_provider.user_that_must_test_settings = @org.admin
        @org_provider.issuer = "https://other.example.com"

        refute_predicate @org_provider, :valid?
        refute_predicate @org_provider.errors[:issuer], :empty?
      end

      test "rejects idp_certificate change without a matching, successful test" do
        @org_provider.user_that_must_test_settings = @org.admin
        @org_provider.idp_certificate = Rails.root.join("test/fixtures/misc/saml/azure.pem").read

        refute_predicate @org_provider, :valid?
        refute_predicate @org_provider.errors[:idp_certificate], :empty?
      end

      test "rejects changes if their test was not done by required user" do
        @org_provider_test_settings.sso_url = "https://other.example.com/sso"
        @org_provider_test_settings.save!
        @org_provider.user_that_must_test_settings = create(:user)
        @org_provider.sso_url = "https://other.example.com/sso"

        refute_predicate @org_provider, :valid?
        refute_predicate @org_provider.errors[:sso_url], :empty?
      end

      test "rejects changes if their test was not done on the settings' organization" do
        @org_provider_test_settings.sso_url = "https://other.example.com/sso"
        @org_provider_test_settings.organization = create(:organization)
        @org_provider_test_settings.save!
        @org_provider.user_that_must_test_settings = @org.admin
        @org_provider.sso_url = "https://other.example.com/sso"

        refute_predicate @org_provider, :valid?
        refute_predicate @org_provider.errors[:sso_url], :empty?
      end

      test "rejects changes if their test was not successful" do
        @org_provider_test_settings.sso_url = "https://other.example.com/sso"
        @org_provider_test_settings.status = Organization::SamlProviderTestSettings::FAILURE
        @org_provider_test_settings.save!

        @org_provider.user_that_must_test_settings = @org.admin
        @org_provider.sso_url = "https://other.example.com/sso"

        refute_predicate @org_provider, :valid?
        refute_predicate @org_provider.errors[:sso_url], :empty?
      end
    end
  end

  context "business provider test settings" do
    context "validating sso_url" do
      test "rejects nil" do
        @business_provider_test_settings.sso_url = nil

        refute_predicate @business_provider_test_settings, :valid?
        refute_predicate @business_provider_test_settings.errors[:sso_url], :empty?
      end

      test "rejects invalid URLs" do
        @business_provider_test_settings.sso_url = "not a valid URL"

        refute_predicate @business_provider_test_settings, :valid?
        refute_predicate @business_provider_test_settings.errors[:sso_url], :empty?
      end
    end

    context "validating IdP Certificates" do
      test "rejects nil" do
        @business_provider_test_settings.idp_certificate = nil

        refute_predicate @business_provider_test_settings, :valid?
        refute_predicate @business_provider_test_settings.errors[:idp_certificate], :empty?
      end

      test "rejects invalid certificates" do
        @business_provider_test_settings.idp_certificate = "invalid cert"

        refute_predicate @business_provider_test_settings, :valid?
        refute_predicate @business_provider_test_settings.errors[:idp_certificate], :empty?
      end
    end

    context "validating settings changes when a user is required to 'Test SAML settings' on them" do
      test "always accpept test provider changes (it can't require testing)" do
        @business_provider_test_settings.sso_url = "https://other.example.com"
        assert_predicate @business_provider_test_settings, :valid?
      end

      test "always validates if no configurable properties changed" do
        @business_provider.user_that_must_test_settings = @business_admin
        assert_predicate @business_provider, :valid?
      end

      test "accepts sso_url change with a matching, successful test" do
        @business_provider_test_settings.sso_url = "https://other.example.com/sso"
        @business_provider_test_settings.save!
        @business_provider.user_that_must_test_settings = @business_admin
        @business_provider.sso_url = "https://other.example.com/sso"
        assert_predicate @business_provider, :valid?
      end

      test "accepts issuer change with a matching, successful test" do
        @business_provider_test_settings.issuer = "https://other.example.com"
        @business_provider_test_settings.save!
        @business_provider.user_that_must_test_settings = @business_admin
        @business_provider.issuer = "https://other.example.com"
        assert_predicate @business_provider, :valid?
      end

      test "accepts idp_certificate change with a matching, successful test" do
        @business_provider_test_settings.idp_certificate = Rails.root.join("test/fixtures/misc/saml/azure.pem").read
        @business_provider_test_settings.save!
        @business_provider.user_that_must_test_settings = @business_admin
        @business_provider.idp_certificate = Rails.root.join("test/fixtures/misc/saml/azure.pem").read
        assert_predicate @business_provider, :valid?
      end

      test "rejects sso_url change without a matching, successful test" do
        @business_provider.user_that_must_test_settings = @business_admin
        @business_provider.sso_url = "https://other.example.com/sso"

        refute_predicate @business_provider, :valid?
        refute_predicate @business_provider.errors[:sso_url], :empty?
      end

      test "rejects issuer change without a matching, successful test" do
        @business_provider.user_that_must_test_settings = @business_admin
        @business_provider.issuer = "https://other.example.com"

        refute_predicate @business_provider, :valid?
        refute_predicate @business_provider.errors[:issuer], :empty?
      end

      test "rejects idp_certificate change without a matching, successful test" do
        @business_provider.user_that_must_test_settings = @business_admin
        @business_provider.idp_certificate = Rails.root.join("test/fixtures/misc/saml/azure.pem").read

        refute_predicate @business_provider, :valid?
        refute_predicate @business_provider.errors[:idp_certificate], :empty?
      end

      test "rejects changes if their test was not done by required user" do
        @business_provider_test_settings.sso_url = "https://other.example.com/sso"
        @business_provider_test_settings.save!
        @business_provider.user_that_must_test_settings = create(:user)
        @business_provider.sso_url = "https://other.example.com/sso"

        refute_predicate @business_provider, :valid?
        refute_predicate @business_provider.errors[:sso_url], :empty?
      end

      unless GitHub.single_business_environment?
        test "rejects changes if their test was not done on the settings' business" do
          @business_provider_test_settings.sso_url = "https://other.example.com/sso"
          @business_provider_test_settings.business = create(:business)
          @business_provider_test_settings.save!
          @business_provider.user_that_must_test_settings = @business_admin
          @business_provider.sso_url = "https://other.example.com/sso"

          refute_predicate @business_provider, :valid?
          refute_predicate @business_provider.errors[:sso_url], :empty?
        end
      end

      test "rejects changes if their test was not successful" do
        @business_provider_test_settings.sso_url = "https://other.example.com/sso"
        @business_provider_test_settings.status = Business::SamlProviderTestSettings::FAILURE
        @business_provider_test_settings.save!
        @business_provider.user_that_must_test_settings = @business_admin
        @business_provider.sso_url = "https://other.example.com/sso"

        refute_predicate @business_provider, :valid?
        refute_predicate @business_provider.errors[:sso_url], :empty?
      end
    end
  end
end
