# typed: true
# frozen_string_literal: true

require "test_helper"

class SamlProviderSetupFlowTest < GitHub::TestCase
  fixtures do
    @business = create :business
    @org = create :organization
    @valid_cert = Rails.root.join("test/fixtures/misc/saml/idp.crt").read
  end

  context "initialisation" do
    test "creates instance for Business target" do
      flow = SamlProviderSetupFlow.new @business
      assert flow.tmp_provider
      refute flow.recovery_secret
      refute_predicate flow, :pending?
    end

    test "creates instance for Organization target" do
      flow = SamlProviderSetupFlow.new @org
      assert flow.tmp_provider
      refute flow.recovery_secret
      refute_predicate flow, :pending?
    end

    test "raises ArgumentError if target is invalid" do
      assert_raises ArgumentError do
        SamlProviderSetupFlow.new create(:user)
      end
    end
  end

  context "#new_setup" do
    test "stores recovery secret for Business target" do
      flow = SamlProviderSetupFlow.new @business
      saml_params = {
        sso_url: "http://example.com",
        idp_certificate: @valid_cert,
        signature_method: T.must(Platform::Enums::SamlSignatureAlgorithm.values["RSA_SHA256"]).value,
        digest_method: T.must(Platform::Enums::SamlDigestAlgorithm.values["SHA256"]).value,
      }
      flow.new_setup saml_params
      assert flow.recovery_secret
      assert_predicate flow, :pending?
    end

    test "does not store recovery secret for Business target when input is invalid" do
      flow = SamlProviderSetupFlow.new @business
      saml_params = {
        sso_url: "",
        idp_certificate: @valid_cert,
        signature_method: T.must(Platform::Enums::SamlSignatureAlgorithm.values["RSA_SHA256"]).value,
        digest_method: T.must(Platform::Enums::SamlDigestAlgorithm.values["SHA256"]).value,
      }
      flow.new_setup saml_params
      refute flow.recovery_secret
      refute_predicate flow, :pending?
    end

    test "stores recovery secret for Organization target" do
      flow = SamlProviderSetupFlow.new @org
      saml_params = {
        sso_url: "http://example.com",
        idp_certificate: @valid_cert,
        signature_method: T.must(Platform::Enums::SamlSignatureAlgorithm.values["RSA_SHA256"]).value,
        digest_method: T.must(Platform::Enums::SamlDigestAlgorithm.values["SHA256"]).value,
      }
      flow.new_setup saml_params
      assert flow.recovery_secret
      assert_predicate flow, :pending?
    end

    test "does not store recovery secret for Organization target when input is invalid" do
      flow = SamlProviderSetupFlow.new @org
      saml_params = {
        sso_url: "",
        idp_certificate: @valid_cert,
        signature_method: T.must(Platform::Enums::SamlSignatureAlgorithm.values["RSA_SHA256"]).value,
        digest_method: T.must(Platform::Enums::SamlDigestAlgorithm.values["SHA256"]).value,
      }
      flow.new_setup saml_params
      refute flow.recovery_secret
      refute_predicate flow, :pending?
    end
  end

  context "#clear_kv_values" do
    test "clears GitHub.kv values for pending flow with Business target" do
      flow = SamlProviderSetupFlow.new @business
      saml_params = {
        sso_url: "http://example.com",
        idp_certificate: @valid_cert,
        signature_method: T.must(Platform::Enums::SamlSignatureAlgorithm.values["RSA_SHA256"]).value,
        digest_method: T.must(Platform::Enums::SamlDigestAlgorithm.values["SHA256"]).value,
      }
      flow.new_setup saml_params
      assert_predicate flow, :pending?
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert GitHub.kv.get("saml_provider_setup_recovery_secret:business:#{@business.id}").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv

      flow.clear_kv_values
      # rubocop:todo GitHub/DoNotUseGlobalKv
      refute GitHub.kv.get("saml_provider_setup_recovery_secret:business:#{@business.id}").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end

    test "clears GitHub.kv values for pending flow with Organizationn target" do
      flow = SamlProviderSetupFlow.new @org
      saml_params = {
        sso_url: "http://example.com",
        idp_certificate: @valid_cert,
        signature_method: T.must(Platform::Enums::SamlSignatureAlgorithm.values["RSA_SHA256"]).value,
        digest_method: T.must(Platform::Enums::SamlDigestAlgorithm.values["SHA256"]).value,
      }
      flow.new_setup saml_params
      assert_predicate flow, :pending?
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert GitHub.kv.get("saml_provider_setup_recovery_secret:organization:#{@org.id}").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv

      flow.clear_kv_values
      # rubocop:todo GitHub/DoNotUseGlobalKv
      refute GitHub.kv.get("saml_provider_setup_recovery_secret:organization:#{@org.id}").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end
  end
end
