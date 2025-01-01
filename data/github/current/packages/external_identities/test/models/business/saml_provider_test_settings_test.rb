# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessSamlProviderTestSettingsTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  extend EncryptedColumnTestHelper

  test_encrypted_column(:business_saml_provider_test_settings, :encrypted_key) do
    Business.all.each do |business|
      business.destroy
    end
  end

  fixtures do
    @owner = create :user
    @business = create :business, owners: [@owner]
    @business.saml_provider = create :business_saml_provider, business: @business
    @settings = make_business_saml_settings
  end

  context "#sso_url" do
    test "cannot exceed 255 characters" do
      settings = build :business_saml_provider_test_settings, \
        user: @owner, business: @business, sso_url: "https://#{"e" * 300}.ee/hello"
      refute_predicate settings, :valid?
      assert_includes settings.errors[:sso_url], "is too long (maximum is 255 characters)"
    end
  end

  context "#issuer" do
    test "cannot exceed 255 characters" do
      settings = build :business_saml_provider_test_settings, \
        user: @owner, business: @business, issuer: "https://#{"e" * 300}.ee/hello"
      refute_predicate settings, :valid?
      assert_includes settings.errors[:issuer], "is too long (maximum is 255 characters)"
    end
  end

  context ".most_recent_for" do
    test "finds test settings for a given user and business" do
      assert_equal \
        @settings,
        Business::SamlProviderTestSettings.most_recent_for(
          user: @owner,
          business: @business,
        )
    end

    test "finds the latest test settings for a given user and business" do
      Timecop.travel(2.minutes.ago) do
        make_business_saml_settings
      end

      Timecop.travel(1.hour.from_now) do
        latest_settings = make_business_saml_settings
        assert_equal \
          latest_settings,
          Business::SamlProviderTestSettings.most_recent_for(
            user: @owner,
            business: @business,
          )
      end
    end

    test "returns a new instance when nothing is found" do
      settings = Business::SamlProviderTestSettings.most_recent_for(user: nil, business: @business)
      assert_predicate settings, :invalid?
      refute_predicate settings, :persisted?

      settings = Business::SamlProviderTestSettings.most_recent_for(user: @business, business: nil)
      assert_predicate settings, :invalid?
      refute_predicate settings, :persisted?
    end

    test "sets the test result status" do
      make_business_saml_settings

      latest_settings = Business::SamlProviderTestSettings.most_recent_for(
        user: @owner,
        business: @business,
        result: { "status" => Business::SamlProviderTestSettings::SUCCESS, "message" => "some message" },
      )

      assert_equal "some message", latest_settings.message
      assert_predicate latest_settings, :success?
    end
  end

  context "test status" do
    test "knows when a test was successful" do
      settings = make_business_saml_settings
      settings.set_status(status: Business::SamlProviderTestSettings::SUCCESS, message: "irrelevant")

      assert_predicate settings, :success?
      refute_predicate settings, :failure?
    end

    test "knows when a test was a failure" do
      settings = make_business_saml_settings
      settings.set_status(status: "not successful", message: "irrelevant")

      assert_predicate settings, :failure?
      refute_predicate settings, :success?
    end

    test "treats nil as failure" do
      settings = make_business_saml_settings
      settings.set_status(status: nil, message: "irrelevant")

      assert_predicate settings, :failure?
      refute_predicate settings, :success?
    end

    test "recalls the status message" do
      settings = make_business_saml_settings
      settings.set_status(status: "not successful", message: "some message")

      assert_equal "some message", settings.message
    end

    test "stores status on the database (but does not automatically persist)" do
      settings = make_business_saml_settings
      settings.set_status(status: "not successful", message: "some message")

      persisted_settings = Business::SamlProviderTestSettings.find(settings.id)
      assert_nil persisted_settings.status

      settings.save!
      persisted_settings.reload
      assert_equal "not successful", persisted_settings.status
    end

    test "does not store message on the database" do
      settings = make_business_saml_settings
      settings.set_status(status: "not successful", message: "some message")
      persisted_settings = Business::SamlProviderTestSettings.find(settings.id)

      assert_equal "some message", settings.message
      assert_nil persisted_settings.message
    end
  end
end
