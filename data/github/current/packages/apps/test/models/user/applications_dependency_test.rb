# typed: true
# frozen_string_literal: true

require "test_helper"

class UserApplicationsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @oauth_app = create(:oauth_application, user: @user)
    @integration = create(:integration, owner: @user)
    @default_limit = GitHub::ApplicationsCreationLimit::DEFAULT_MAX_APPLICATIONS_CREATION_LIMIT
  end

  context "Applications creation limits" do
    test "it returns a default max value" do
      assert_equal @default_limit, @user.applications_creation_limit(application_type: OauthApplication)
      assert_equal @default_limit, @user.applications_creation_limit(application_type: Integration)
    end

    test "it supports custom limits" do
      @user.set_custom_applications_limit(application_type: OauthApplication, limit: 10)
      assert_equal 10, @user.applications_creation_limit(application_type: OauthApplication)

      assert_equal @default_limit, @user.applications_creation_limit(application_type: Integration)
      @user.set_custom_applications_limit(application_type: Integration, limit: 25)
      assert_equal 25, @user.applications_creation_limit(application_type: Integration)

      @user.set_custom_applications_limit(application_type: Integration, limit: "15")
      assert_equal 15, @user.applications_creation_limit(application_type: Integration)
    end

    test "setting invalid limits" do
      assert_raises ArgumentError do
        @user.set_custom_applications_limit(application_type: Integration, limit: "nan")
      end

      assert_raises ArgumentError do
        @user.set_custom_applications_limit(application_type: Integration, limit: -1)
      end
    end

    test "#reached_applications_creation_limit?", skip_enterprise: true do
      refute @user.reached_applications_creation_limit?(application_type: Integration)
      refute @user.reached_applications_creation_limit?(application_type: OauthApplication)

      assert_predicate @user.integrations, :any?
      @user.set_custom_applications_limit(application_type: Integration, limit: 1)
      assert @user.reached_applications_creation_limit?(application_type: Integration)
      refute @user.reached_applications_creation_limit?(application_type: OauthApplication)

      assert_predicate @user.oauth_applications, :any?
      @user.set_custom_applications_limit(application_type: OauthApplication, limit: 1)
      assert @user.reached_applications_creation_limit?(application_type: OauthApplication)
    end

    test "#reached_applications_creation_limit? is false on enterprise" do
      @user.set_custom_applications_limit(application_type: Integration, limit: 0)
      refute @user.reached_applications_creation_limit?(application_type: Integration)
    end if GitHub.enterprise?

    test "#reached_applications_creation_limit? is false for proxima synced apps owners when MT mode FF is enabled" do
      GitHub.flipper[:ignore_app_creation_limit].enable
      first_party_apps_owner = GitHub::MachinistHelpers.make_first_party_apps_owner
      make_proxima_third_party_apps_owner = GitHub::MachinistHelpers.make_proxima_third_party_apps_owner

      first_party_apps_owner.set_custom_applications_limit(application_type: Integration, limit: 0)
      make_proxima_third_party_apps_owner.set_custom_applications_limit(application_type: Integration, limit: 0)

      refute first_party_apps_owner.reached_applications_creation_limit?(application_type: Integration)
      refute make_proxima_third_party_apps_owner.reached_applications_creation_limit?(application_type: Integration)
    end if GitHub.multi_tenant_enterprise?

    test "#reached_applications_creation_limit? is true for proxima synced apps owners when MT mode and FF is disabled" do
      GitHub.flipper[:ignore_app_creation_limit].disable
      first_party_apps_owner = GitHub::MachinistHelpers.make_first_party_apps_owner
      make_proxima_third_party_apps_owner = GitHub::MachinistHelpers.make_proxima_third_party_apps_owner

      first_party_apps_owner.set_custom_applications_limit(application_type: Integration, limit: 0)
      make_proxima_third_party_apps_owner.set_custom_applications_limit(application_type: Integration, limit: 0)

      assert first_party_apps_owner.reached_applications_creation_limit?(application_type: Integration)
      assert make_proxima_third_party_apps_owner.reached_applications_creation_limit?(application_type: Integration)
    end if GitHub.multi_tenant_enterprise?

    test "#reached_applications_creation_limit? is true for proxima synced apps owners when non-MT mode and FF is enabled" do
      GitHub.flipper[:ignore_app_creation_limit].enable
      first_party_apps_owner = GitHub::MachinistHelpers.make_first_party_apps_owner
      make_proxima_third_party_apps_owner = GitHub::MachinistHelpers.make_proxima_third_party_apps_owner

      first_party_apps_owner.set_custom_applications_limit(application_type: Integration, limit: 0)
      make_proxima_third_party_apps_owner.set_custom_applications_limit(application_type: Integration, limit: 0)

      assert first_party_apps_owner.reached_applications_creation_limit?(application_type: Integration)
      assert make_proxima_third_party_apps_owner.reached_applications_creation_limit?(application_type: Integration)
    end unless GitHub.multi_tenant_enterprise? || GitHub.enterprise?
  end
end
