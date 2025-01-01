# typed: true
# frozen_string_literal: true

require "test_helper"

class AppDisplayOwnerTest < GitHub::TestCase
  test "is part of an Integration and an OauthApplication" do
    actual_owner = create(:organization, login: "some-app-owner")
    github_app = create(:integration, owner: actual_owner)
    oauth_app = create(:oauth_application, user: actual_owner)

    assert_equal AppDisplayOwner, github_app.display_owner.class
    assert_equal AppDisplayOwner, oauth_app.display_owner.class
  end

  test "returns the actual owner" do
    actual_owner = create(:organization, login: "some-app-owner")
    app = create(:integration, owner: actual_owner)

    assert_equal actual_owner, app.display_owner.actual_owner
  end

  if TestEnv.test_in_multitenancy_mode?
    test "#display_login for synchronized apps, returns the actual app owner's login in mt-mode when the feature flag is disabled" do
      GitHub.flipper[:proxima_display_owner].disable
      # In reality, the owning org wouldn't reside in the same database, but it's
      # good enough for this test.
      dotcom_owner = create(:organization, login: "some-dotcom-app-owner", skip_enterprise_managed_organization: true)
      app = create(:integration, owner: make_proxima_third_party_apps_owner)
      create(:dotcom_app_owner_metadata, dotcom_owner: dotcom_owner, local_app: app)

      assert_equal GitHub.proxima_third_party_apps_owner.display_login, app.display_owner.display_login
    end

    test "#display_login for synchronized apps, returns the third-party app owner's login in mt-mode when the feature flag is enabled" do
      GitHub.flipper[:proxima_display_owner].enable
      # In reality, the owning org wouldn't reside in the same database, but it's
      # good enough for this test.
      dotcom_owner = create(:organization, login: "some-dotcom-app-owner", skip_enterprise_managed_organization: true)
      app = create(:integration, owner: make_proxima_third_party_apps_owner)
      create(:dotcom_app_owner_metadata, dotcom_owner: dotcom_owner, local_app: app)

      assert_equal "some-dotcom-app-owner", app.display_owner.display_login
    end

    test "#url_for_link_to for synchronized apps, returns the actual app owner _object_ in mt-mode when the feature flag is disabled" do
      GitHub.flipper[:proxima_display_owner].disable
      # In reality, the owning org wouldn't reside in the same database, but it's
      # good enough for this test.
      dotcom_owner = create(:organization, login: "some-dotcom-app-owner", skip_enterprise_managed_organization: true)
      app = create(:integration, owner: make_proxima_third_party_apps_owner)
      create(:dotcom_app_owner_metadata, dotcom_owner: dotcom_owner, local_app: app)

      assert_equal GitHub.proxima_third_party_apps_owner, app.display_owner.url_for_link_to
    end

    test "#url_for_link_to for synchronized apps, returns the third-party app owner's URL in mt-mode when the feature flag is enabled" do
      GitHub.flipper[:proxima_display_owner].enable
      # In reality, the owning org wouldn't reside in the same database, but it's
      # good enough for this test.
      dotcom_owner = create(:organization, login: "some-dotcom-app-owner", skip_enterprise_managed_organization: true)
      app = create(:integration, owner: make_proxima_third_party_apps_owner)
      md = create(:dotcom_app_owner_metadata, dotcom_owner: dotcom_owner, local_app: app)

      assert_equal md.url, app.display_owner.url_for_link_to
    end
  else
    test "#display_login returns the actual owner's login on dotcom" do
      actual_owner = create(:organization, login: "some-app-owner")
      app = create(:integration, owner: actual_owner)

      assert_equal "some-app-owner", app.display_owner.display_login
    end
  end

  context "user_path" do
    if TestEnv.test_in_multitenancy_mode?
      test "returns the dotcom owner's URL when synchronized and the feature flag is enabled" do
        GitHub.flipper[:proxima_display_owner].enable
        # In reality, the owning org wouldn't reside in the same database, but it's
        # good enough for this test.
        dotcom_owner = create(:organization, login: "some-dotcom-app-owner", skip_enterprise_managed_organization: true)
        app = create(:integration, owner: make_proxima_third_party_apps_owner)
        md = create(:dotcom_app_owner_metadata, dotcom_owner: dotcom_owner, local_app: app)

        assert_equal md.url, app.display_owner.user_path
      end
    else
      test "returns the user path for user-owned apps" do
        actual_owner = create(:user, login: "some-app-owner")
        app = create(:integration, owner: actual_owner)

        assert_equal "/some-app-owner", app.display_owner.user_path
      end

      test "returns the user path for organization-owned apps" do
        actual_owner = create(:organization, login: "some-app-owner")
        app = create(:integration, owner: actual_owner)

        assert_equal "/some-app-owner", app.display_owner.user_path
      end

      test "returns the enterprise path for business-owned apps" do
        actual_owner = create(:business, name: "Some App Owner")
        app = create(:enterprise_owned_integration, owner: actual_owner)

        assert_equal "/enterprises/some-app-owner", app.display_owner.user_path
      end
    end
  end
end
