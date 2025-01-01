# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessSamlProviderTypeDependencyTest < GitHub::TestCase
  context "SamlProvider#find_provider_type" do
    test "return unknown when issuer is not set in provider" do
      provider = create(:business_saml_provider, issuer: nil)
      assert_equal :unknown, provider.find_provider_type
    end

    test "return azure_ad when issuer is azure ad prod" do
      provider = create(:business_saml_provider, issuer: "https://sts.windows.net/43d69bd9-8e34-4cd8-8f73-96f42031c239/")
      assert_equal :azure_ad, provider.find_provider_type
    end

    test "return azure_ad when issuer is azure ad ppe" do
      provider = create(:business_saml_provider, issuer: "https://sts.windows-ppe.net/43d69bd9-8e34-4cd8-8f73-96f42031c239/")
      assert_equal :azure_ad, provider.find_provider_type
    end

    test "return okta when issuer is okta" do
      provider = create(:business_saml_provider, issuer: "http://www.okta.com/exkxbygpwmMat2rzs0h7")
      assert_equal :okta, provider.find_provider_type
    end

    test "return unknown when issuer is not known type" do
      provider = create(:business_saml_provider)
      assert_equal :unknown, provider.find_provider_type
    end
  end
end
