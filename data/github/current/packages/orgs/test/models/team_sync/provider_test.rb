# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamSyncProviderTest < GitHub::TestCase
  context ".detect" do
    test "recognizes a SAML Provider configured with Okta" do
      provider = create(:organization_saml_provider, issuer: "http://www.okta.com/exk1alt42ls3GoKdV1d8")

      res = ::TeamSync::Provider.detect(issuer: provider.issuer)
      refute_nil res

      assert_equal "okta", res.type
      assert_equal "exk1alt42ls3GoKdV1d8", res.id
    end

    test "recognizes a SAML Provider configured with AzureAD" do
      provider = create(:organization_saml_provider, issuer: "https://sts.windows.net/a3350e2e-d5fb-4682-b8ed-5cf081a1e841/")

      res = ::TeamSync::Provider.detect(issuer: provider.issuer)
      refute_nil res

      assert_equal "azuread", res.type
      assert_equal "a3350e2e-d5fb-4682-b8ed-5cf081a1e841", res.id
    end

    test "does not recognize a custom SAML Provider configuration" do
      provider = create(:organization_saml_provider, issuer: "http://nullmethod.com/issuer")

      res = ::TeamSync::Provider.detect(issuer: provider.issuer)
      assert_nil res
    end
  end

  context "#supported_for_org?" do
    test "returns true for azuread" do
      provider = ::TeamSync::Provider.new(type: "azuread", id: 123)

      assert_equal true, provider.supported_for_org?(build(:organization))
    end

    test "returns true for okta" do
      provider = ::TeamSync::Provider.new(type: "okta", id: 123)
      org = create(:organization)

      assert_equal true, provider.supported_for_org?(org)
    end

    test "returns false for unknown provider" do
      provider = ::TeamSync::Provider.new(type: "what-even-is-this", id: 123)
      org = create(:organization)

      assert_equal false, provider.supported_for_org?(org)
    end
  end

  context "#supported_for_business?" do
    test "returns true for azuread" do
      provider = ::TeamSync::Provider.new(type: "azuread", id: 123)

      assert_equal true, provider.supported_for_business?(build(:business))
    end

    test "returns true for okta" do
      provider = ::TeamSync::Provider.new(type: "okta", id: 123)
      business = create(:business)

      assert_equal true, provider.supported_for_business?(business)
    end

    test "returns false for unknown provider" do
      provider = ::TeamSync::Provider.new(type: "what-even-is-this", id: 123)
      business = create(:business)

      assert_equal false, provider.supported_for_business?(business)
    end
  end

  context "#okta?" do
    test "returns true when the provider type is 'okta'" do
      provider = ::TeamSync::Provider.new(type: "okta", id: 123)

      assert_predicate provider, :okta?
    end

    test "returns false when the provider type is not 'okta'" do
      provider = ::TeamSync::Provider.new(type: "what-even-is-this", id: 123)

      refute_predicate provider, :okta?
    end
  end
end
