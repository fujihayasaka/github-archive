# typed: true
# frozen_string_literal: true

require "test_helper"

class ApplicationCallbackUrlTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @integration = create(:integration)
    @subject = create(:application_callback_url, application: @integration, url: "https://example.com/auth/callback")
  end

  test "requires a valid url" do
    # invalid without a scheme
    url = build(:application_callback_url, url: "example.com", application: @integration)
    url.valid?
    assert_predicate url.errors[:url], :any?

    # valid with a scheme
    url.url = "http://example.com"
    url.valid?
    refute_predicate url.errors[:url], :any?

    # valid with an unusual scheme
    url.url = "oob://foo.com"
    url.valid?
    refute_predicate url.errors[:url], :any?

    # with invalid unicode characters
    url.url = "http://abc.com?🐹def=org"
    url.valid?
    assert url.errors[:url].any?
  end

  test "requires a valid application" do
    url = build(:application_callback_url, url: "example.com", application: User.new)
    url.valid?
    assert_predicate url.errors[:application_type], :any?

    url.application = @integration
    url.valid?
    refute_predicate url.errors[:application], :any?

    url.application = OauthApplication.new
    url.valid?
    refute_predicate url.errors[:application], :any?
  end

  test "#default? returns false when the model has not been saved" do
    url = build(:application_callback_url, url: "example.com", application: OauthApplication.new)

    refute_predicate url, :persisted?
    refute_predicate url, :default?
  end

  test "#default? returns true when it's the only model in the association" do
    app = create(:oauth_application)

    assert_equal 1, app.application_callback_urls.count
    assert_predicate app.application_callback_urls.first, :default?
  end

  test "#default? returns true when it's the 'first' model in the association" do
    app = create(:oauth_application)
    app.application_callback_urls.create(url: "https://example.com")

    assert_equal 2, app.application_callback_urls.count
    assert_predicate app.application_callback_urls.first, :default?
  end

  test "#default? returns false when it's not the first model in the association" do
    app = create(:oauth_application)
    app.application_callback_urls.create(url: "https://example.com")

    assert_equal 2, app.application_callback_urls.count
    refute_predicate app.application_callback_urls.last, :default?
  end

  test "propagates errors from IntegrationUrlValidator" do
    app = create(:oauth_application)
    app.set_application_callback_urls(["https://example.com/auth/callback", "https://example.com/auth/callback#fragment"])

    refute_predicate app, :valid?
    assert_predicate app.errors[:application_callback_urls], :any?
  end

  context "IntegrationUrlValidator" do
    test "follows strict validation on create" do
      url = "https://github.com/defunkt/jquery-pjax#status-of-this-project"
      subject = build(:application_callback_url, url: url, application: @integration)

      refute_predicate subject, :valid?
      assert_same_elements ["must be a valid URL"], subject.errors[:url]
    end

    # REF: https://github.com/github/ecosystem-apps/issues/1096
    test "follows strict validation on update" do
      @subject.update(url: "https://example.com/#/my-callback")
      refute_predicate @subject, :valid?

      assert_same_elements ["must be a valid URL"], @subject.errors[:url]
    end

    test "must not use a blocked query key" do
      OauthUtil::RESERVED_REDIRECT_URI_QUERY_KEYS.each do |key|
        @subject.url = "https://foo.com?#{key}=bar"
      end

      refute_predicate @subject, :valid?
      assert_predicate @subject.errors[:url], :any?
    end

    test "must use a non-blocked scheme" do
      IntegrationUrl::BLOCKED_SCHEMES.each do |scheme|
        @subject.url = "#{scheme}://foo.com"

        refute_predicate @subject, :valid?
        assert_predicate @subject.errors[:url], :any?
      end
    end

    test "url must be a string" do
      @subject.url = 123

      refute_predicate @subject, :valid?
      assert_predicate @subject.errors[:url], :any?
    end
  end

  context "templated urls" do
    test "url can be a templated URL if app has Proxima sync enabled" do
      app = create_internal_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })

      url = "https://{hostname}/callback"
      application_callback_url = app.application_callback_urls.create(url: url)

      assert_predicate app, :valid?
    end

    test "url cannot be a templated URL if app does not have Proxima sync enabled" do
      app = create_internal_app_with_capabilities(capabilities: { proxima_first_party_sync: false }, options: { owner: @user })

      url = "https://{hostname}/callback"
      application_callback_url = app.application_callback_urls.create(url: url)

      refute_predicate app, :valid?
    end

    test "#raw_url returns non-interpolated url" do
      app = create_internal_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })

      url = "https://{hostname}/callback"
      application_callback_url = app.application_callback_urls.create(url: url)

      assert_equal url, application_callback_url.raw_url
    end
  end
end
