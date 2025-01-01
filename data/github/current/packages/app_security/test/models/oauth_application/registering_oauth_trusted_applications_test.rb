# typed: true
# frozen_string_literal: true

require "test_helper"

class RegisteringOauthTrustedApplicationsTest < GitHub::TestCase
  fixtures do
    @user   = create(:user)
    @user2  = create(:user)
    @user3  = create(:user)
    @app    = create :oauth_application, user: @user
    @access = @app.grant(@user, scope: "user")
    @authed = @app.grant(@user2)

    @github = make_trusted_oauth_apps_owner
  end

  test "register the application with a relative url" do
    app = OauthApplication.register_trusted_application("gist", "foo", "bar", "new-gist")

    assert_equal "https://github.com/new-gist", app.url
    assert_equal "https://github.com/new-gist", app.callback_url
  end

  test "register the application with an absolute url" do
    app = OauthApplication.register_trusted_application("gist", "foo", "bar", "http://gist-test.github.dev")

    assert_equal "http://gist-test.github.dev", app.url
    assert_equal "http://gist-test.github.dev", app.callback_url
  end

  test "register the application with a relative callback" do
    app = OauthApplication.register_trusted_application("gist", "foo", "bar", "new-gist", "new-gist/callback")

    assert_equal "https://github.com/new-gist", app.url
    assert_equal "https://github.com/new-gist/callback", app.callback_url
  end

  test "register the application with an absolute callback" do
    app = OauthApplication.register_trusted_application("gist", "foo", "bar", "http://gist-test.github.dev", "http://gist-test.github.dev/callback")

    assert_equal "http://gist-test.github.dev", app.url
    assert_equal "http://gist-test.github.dev/callback", app.callback_url
  end

  test "updates the attributes when the application already exists" do
    app = OauthApplication.register_trusted_application("gist", "foo", "bar", "gist")

    assert_equal "foo", app.key
    assert_includes app.client_secrets.map(&:secret_hash), IntegrationClientSecret.hash_for("bar")
    assert_equal "https://github.com/gist", app.url
    assert_equal "https://github.com/gist", app.callback_url

    updated = OauthApplication.register_trusted_application("gist", "bar", "foo", "new-gist")

    assert_equal app.id, updated.id
    assert_equal "bar", updated.key
    assert_includes app.client_secrets.reload.map(&:secret_hash), IntegrationClientSecret.hash_for("foo")
    assert_equal "https://github.com/new-gist", updated.url
    assert_equal "https://github.com/new-gist", updated.callback_url
  end

  test "returns the Pages oauth app id" do
    OauthApplication.find_by(id: GitHub.pages_app_id).try(:destroy) if GitHub.pages_app_id
    GitHub.pages_app_id = nil

    app = OauthApplication.register_trusted_application("GitHub Pages", "foo", "bar", "pages")
    assert_equal app.id, GitHub.pages_app_id
  end

  test "does not re-add the same key" do
    app = OauthApplication.register_trusted_application("gist", "client1", "password123", "gist")
    assert_equal app.client_secrets.length, 1

    updated = OauthApplication.register_trusted_application("gist", "client1", "password123", "gist")
    assert_equal updated.client_secrets.length, 1
  end

  test "removes oldest key when max exceeded" do
    OauthApplication.register_trusted_application("gist", "client1", "super-secret1", "gist")
    OauthApplication.register_trusted_application("gist", "client1", "super-secret2", "gist")
    OauthApplication.register_trusted_application("gist", "client1", "super-secret3", "gist")
    OauthApplication.register_trusted_application("gist", "client1", "super-secret4", "gist")
    app = OauthApplication.register_trusted_application("gist", "client1", "super-secret5", "gist")
    assert_equal app.client_secrets.length, 5

    updated = OauthApplication.register_trusted_application("gist", "client6", "super-secret6", "gist")
    assert_equal updated.client_secrets.length, 5

    assert_includes app.client_secrets.reload.map(&:secret_hash), IntegrationClientSecret.hash_for("super-secret2")
    assert_includes app.client_secrets.reload.map(&:secret_hash), IntegrationClientSecret.hash_for("super-secret3")
    assert_includes app.client_secrets.reload.map(&:secret_hash), IntegrationClientSecret.hash_for("super-secret4")
    assert_includes app.client_secrets.reload.map(&:secret_hash), IntegrationClientSecret.hash_for("super-secret5")
    assert_includes app.client_secrets.reload.map(&:secret_hash), IntegrationClientSecret.hash_for("super-secret6")

    refute_includes app.client_secrets.reload.map(&:secret_hash), IntegrationClientSecret.hash_for("super-secret1")
  end

  context "with a pre-hashed secret" do
    test "registers the application with the correct secret" do
      raw_secret = "super-secret-string"
      hashed_secret = OauthApplicationClientSecret.hash_for(raw_secret)
      last_eight = raw_secret.last(8)

      app = OauthApplication.register_hashed_trusted_application("foo", "bar", hashed_secret, last_eight, "foo")
      assert_includes app.client_secrets.reload.map(&:secret_hash), hashed_secret
      assert app.validate_client_secret(raw_secret)
    end
  end
end
