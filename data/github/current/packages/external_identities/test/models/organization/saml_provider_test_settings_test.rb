# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationSamlProviderTestSettingsTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "org-owner")
    @org = create(:organization,
      admin: @owner,
      saml_provider: create(:organization_saml_provider),
    )
    @settings = make_settings_for(@owner, @org)
  end

  def make_settings_for(user, org)
    create(:organization_saml_provider_test_settings,
      user: user,
      organization: org,
    )
  end

  context ".most_recent_for" do
    test "finds test settings for a given user and organization" do
      assert_equal @settings, Organization::SamlProviderTestSettings.most_recent_for(
        user: @owner,
        org: @org,
      )
    end

    test "finds the latest test settings for a given user and organization" do
      Timecop.travel(2.minutes.ago) do
        make_settings_for(@owner, @org)
      end

      Timecop.travel(1.hour.from_now) do
        latest_settings = make_settings_for(@owner, @org)
        assert_equal latest_settings, Organization::SamlProviderTestSettings.most_recent_for(
          user: @owner,
          org: @org,
        )
      end
    end

    test "returns a new instance when nothing is found" do
      settings = Organization::SamlProviderTestSettings.most_recent_for(user: nil, org: @org)
      assert_predicate settings, :invalid?
      refute_predicate settings, :persisted?

      settings = Organization::SamlProviderTestSettings.most_recent_for(user: @org, org: nil)
      assert_predicate settings, :invalid?
      refute_predicate settings, :persisted?
    end

    test "sets the test result status" do
      make_settings_for(@owner, @org)

      latest_settings = Organization::SamlProviderTestSettings.most_recent_for(
        user: @owner,
        org: @org,
        result: { "status" => Organization::SamlProviderTestSettings::SUCCESS, "message" => "some message" },
      )

      assert_equal "some message", latest_settings.message
      assert_predicate latest_settings, :success?
    end
  end

  context "test status" do
    test "knows when a test was successful" do
      settings = make_settings_for(@owner, @org)
      settings.set_status(status: Organization::SamlProviderTestSettings::SUCCESS, message: "irrelevant")

      assert_predicate settings, :success?
      refute_predicate settings, :failure?
    end

    test "knows when a test was a failure" do
      settings = make_settings_for(@owner, @org)
      settings.set_status(status: "not successful", message: "irrelevant")

      assert_predicate settings, :failure?
      refute_predicate settings, :success?
    end

    test "treats nil as failure" do
      settings = make_settings_for(@owner, @org)
      settings.set_status(status: nil, message: "irrelevant")

      assert_predicate settings, :failure?
      refute_predicate settings, :success?
    end

    test "recalls the status message" do
      settings = make_settings_for(@owner, @org)
      settings.set_status(status: "not successful", message: "some message")

      assert_equal "some message", settings.message
    end

    test "stores status on the database (but does not automatically persist)" do
      settings = make_settings_for(@owner, @org)
      settings.set_status(status: "not successful", message: "some message")

      persisted_settings = Organization::SamlProviderTestSettings.find(settings.id)
      assert_nil persisted_settings.status

      settings.save!
      persisted_settings.reload
      assert_equal "not successful", persisted_settings.status
    end

    test "does not store message on the database" do
      settings = make_settings_for(@owner, @org)
      settings.set_status(status: "not successful", message: "some message")
      persisted_settings = Organization::SamlProviderTestSettings.find(settings.id)

      assert_equal "some message", settings.message
      assert_nil persisted_settings.message
    end
  end
end
