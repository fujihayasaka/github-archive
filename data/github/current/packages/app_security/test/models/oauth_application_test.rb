# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

ALPHA_CHARS = "A".upto("Z").to_a + "a".upto("z").to_a
NUMERIC_CHARS = "0".upto("9").to_a
NON_ALPHANUM_SCHEME_CHARS = %w(. + -)
GOOD_SCHEME_CHARS = [*ALPHA_CHARS, *NUMERIC_CHARS, *NON_ALPHANUM_SCHEME_CHARS]
BAD_SCHEME_CHARS = ((0..255).map { |i| i.chr } - GOOD_SCHEME_CHARS)

class OauthApplicationTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user    = create(:user)
    @user2   = create(:user)
    @user3   = create(:user)
    @app     = create :oauth_application, user: @user
    @access  = @app.grant(@user, scope: "user")
    @authed  = @app.grant(@user2)
    @repo    = create(:repository, :minimal, name: "repo", owner: @user)
    @github  = make_trusted_oauth_apps_owner

    @helphub_app = create(
      :oauth_application,
      user_id: GitHub.trusted_oauth_apps_owner,
      name: Apps::Privileged::HelpHub::STAGING_APP_NAME,
    )
    PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :help_hub_staging, app: @helphub_app)
  end

  test "requires user" do
    app = build :oauth_application, user: nil
    refute app.valid?
    assert app.errors[:user_id].any?
  end

  test "it validates pinned_api_version" do
    GitHub.stubs(:api_versions).returns(["2020-01-01"])
    app = build :oauth_application
    app.pinned_api_version = "bad"
    refute app.valid?
    assert_equal "Pinned api version is invalid", app.errors.full_messages.to_sentence
    app.pinned_api_version = "2020-01-01"
    assert app.valid?
  end

  test "disallows long domain" do
    long_domain = "a" * 150
    long_domain = long_domain + ".com"
    app = build :oauth_application, url: "http://" + long_domain
    refute_predicate app, :valid?
    assert_predicate app.errors[:domain], :any?, "should not allow domain longer than 100 characters"
  end

  test "requires a valid hex color code for background color" do
    app = OauthApplication.new(bgcolor: "ff", user: @user)
    refute_predicate app, :valid?
    assert_predicate app.errors[:bgcolor], :any?, "should require a valid hex color code"
  end

  test "strips pound sign from bgcolor before validation" do
    app = build(:oauth_application, bgcolor: "#ff00ff", user: create(:user))
    assert_predicate app, :valid?
    assert_equal "ff00ff", app.bgcolor
  end

  context "when rate limits" do
    test "are on, creation is rate limited per user" do
      enable_content_creation_rate_limiting
      user = create(:user)
      expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]
      limit = 2

      with_cache_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
            limit.times do
              app = build :oauth_application, user: user
              app.save
            end

            app = build :oauth_application, user: user

            refute app.save
            assert_equal expected_errors, app.errors.full_messages
          end
        end
      end
    end

    test "are off, there isn't a rate limit error" do
      disable_content_creation_rate_limiting
      user = create(:user)
      limit = 2

      with_cache_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
            limit.times do
              app = build :oauth_application, user: user
              app.save
            end
            app = build :oauth_application, user: user

            assert app.save

            assert app.valid?
          end
        end
      end
    end
  end

  context "templated callback_url" do
    test "url can be a templated URL if app has Proxima sync enabled" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, type: :oauth_application)

      url = "https://{hostname}/callback"
      app.callback_url = url

      assert_predicate app, :valid?
    end

    test "url cannot be a templated URL if app does not have Proxima sync enabled" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: false }, type: :oauth_application)

      url = "https://{hostname}/callback"
      app.callback_url = url

      refute_predicate app, :valid?
    end

    test "#callback_url returns interpolated url" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, type: :oauth_application)

      url = "https://{hostname}/callback"
      app.callback_url = url

      assert_equal "https://#{GitHub::host_name_with_tenant}/callback", app.callback_url
    end

    test "#raw_callback_url returns non-interpolated url" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, type: :oauth_application)

      url = "https://{hostname}/callback"
      app.callback_url = url

      assert_equal url, app.raw_callback_url
      assert_equal url, app.read_attribute(:callback_url) # ensure that we are writing the templated url to the db
    end
  end

  context "#callback_url_direct_match?" do
    test "returns false if not direct match" do
      app = create(:oauth_application, callback_url: "https://www.foo.com")
      refute app.callback_url_direct_match?("https://www.foobar.com")
    end

    test "returns true if direct match" do
      app = create(:oauth_application, callback_url: "https://www.foo.com")
      assert app.callback_url_direct_match?("https://www.foo.com")
    end

    test "handles templated urls" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, type: :oauth_application)

      url = "https://{hostname}/callback"
      application_callback_url = app.application_callback_urls.create(url: url)

      assert app.callback_url_direct_match?("#{GitHub.url}/callback")
    end
  end

  context "#strict_callback_url_validation?" do
    test "returns false if there are less than 2 callback urls" do
      app = build :oauth_application
      app.set_application_callback_urls("https://foo.com")
      app.save!

      refute_predicate app, :strict_callback_url_validation?
    end

    test "returns true if there is more than one callback url" do
      app = build :oauth_application
      app.set_application_callback_urls("https://foo.com", "https://foobar.com")
      app.save!

      assert_predicate app, :strict_callback_url_validation?
    end
  end

  context "#identicon_hash" do
    test "returns an unchanging string" do
      hash = @app.identicon_hash
      assert_instance_of String, hash
      if GitHub.fips_mode?
        assert_equal 64, hash.length
      else
        assert_equal 40, hash.length
      end
      assert_equal hash, @app.identicon_hash
    end
  end

  context "#identicon" do
    test "returns an Identicon using the app's identicon hash" do
      identicon = @app.identicon
      assert_instance_of Identicon, identicon
      assert_equal identicon.hash, @app.identicon_hash
    end
  end

  context "#preferred_bgcolor" do
    test "returns bgcolor from Marketplace listing if it exists and is approved" do
      app = create(:oauth_application, bgcolor: "ff00ff")
      listing = create(:marketplace_listing, :verified, listable: app, bgcolor: "faeef0")
      assert_equal listing.bgcolor, app.preferred_bgcolor
    end

    test "returns bgcolor from OAuth app when no Marketplace listing but has custom avatar" do
      app = create(:oauth_application, bgcolor: "ff00ff")
      PrimaryAvatar.set(create(:avatar, owner: app, uploader: app.user), app.user)
      assert_equal app.bgcolor, app.preferred_bgcolor
    end

    test "returns background color from identicon when no custom avatar" do
      assert_equal @app.identicon.background_color, @app.preferred_bgcolor
    end

    if TestEnv.test_in_multitenancy_mode?
      test "returns background color from the OAuth app when synchronized" do
        app = create(:oauth_application, bgcolor: "ff00ff") # #ff00ff will never appear as an Identicon background color
        create(:proxima_app_synchronization, local_app: app)

        assert_equal "ff00ff", app.preferred_bgcolor
      end
    end
  end

  context "#owned_or_operated_by_github?" do
    test "returns true if the owner is the trusted_oauth_apps_owner" do
      app = create(:oauth_application, user: @github)

      assert_predicate app, :owned_or_operated_by_github?
    end

    test "returns true if the app has the 'operated_by_github' capability" do
      app = create_privileged_app_with_capabilities(
        capabilities: { operated_by_github: true },
        type: :oauth_application
      )

      refute_equal GitHub.trusted_apps_owner_id, app.user_id

      assert_predicate app, :owned_or_operated_by_github?
    end
  end

  context "third_party_oap_exempt?" do
    test "always exempt when app has organization_oauth_app_policy_exempt capability" do
      app = create_privileged_app_with_capabilities(
        type: :oauth_application,
        capabilities: { organization_oauth_app_policy_exempt: true }
      )

      assert_predicate app, :third_party_oap_exempt?
    end
  end

  test "disallows some names including 'GitHub' or 'Gist' for non-employee user" do
    rando = create(:user)

    ["Gistable", "gith ub"].each do |name|
      app = build(:oauth_application, name: name, user: rando)

      refute_predicate app, :valid?
      assert_includes app.errors[:name], "should not begin with 'GitHub' or 'Gist'"
    end

    ["Taco Tuesday by GitHub", "P A R T Y F R O M G I T H U B"].each do |name|
      app = build(:oauth_application, name: name, user: rando)

      refute_predicate app, :valid?
      assert_includes app.errors[:name], "should not imply the application is from GitHub"
    end
  end

  test "disallows some names including 'GitHub' or 'Gist' for non-github org" do
    random_org = create(:organization)

    ["GitHub Apps", "Gist Time"].each do |name|
      app = build(:oauth_application, name: name, user: random_org)

      refute_predicate app, :valid?
      assert_includes app.errors[:name], "should not begin with 'GitHub' or 'Gist'"
    end

    ["speling erors from github", "Parrots by Github"].each do |name|
      app = build(:oauth_application, name: name, user: random_org)

      refute_predicate app, :valid?
      assert_includes app.errors[:name], "should not imply the application is from GitHub"
    end
  end

  test "allows name including 'GitHub' for site admin", skip_enterprise: true  do
    site_admin = create(:staff_admin_user)
    assert_predicate site_admin, :site_admin?

    app = build(:oauth_application, name: "github gist", user: site_admin)
    assert_predicate app, :valid?
  end

  if GitHub.enterprise?
    test "disallows name including 'github' for site admin on Enterprise" do
      site_admin = create(:staff_admin_user)
      assert_predicate site_admin, :site_admin?
      refute_predicate site_admin, :employee?

      app = build(:oauth_application, name: "github gist", user: site_admin)
      refute_predicate app, :valid?
    end
  end

  test "allows name including 'GitHub' for github org" do
    app = build(:oauth_application, name: "github gist", user: @github)

    assert_predicate app, :valid?
  end

  test "allows name containing but not beginning with 'gist'" do
    rando = create(:user)

    app = build(:oauth_application, name: "registry", user: rando)

    assert_predicate app, :valid?
  end

  test "allows name containing but not beginning with 'github'" do
    rando = create(:user)

    app = build(:oauth_application, name: "LegitHub", user: rando)

    assert_predicate app, :valid?
  end

  test "validates name containing utf8-4byte values" do
    unicode = "😍"
    app = build :oauth_application, \
      name: unicode
    refute_predicate app, :valid?
    assert app.errors[:name].any?
    assert_includes app.errors[:name], "should not contain non unicode characters"
  end

  context "URL in name validations" do
    test "does not allow names containing http urls" do
      app = build(:oauth_application, name: "Download here: http://spammyurl.com/download")

      refute_predicate app, :valid?
      assert_predicate app.errors[:name], :any?
      assert_includes app.errors[:name], "should not include any URLs"
    end

    # Reproduces https://github.com/github/ecosystem-apps/issues/1349
    test "does not allow names containing https urls" do
      name = "$1M\" dollars and you need to login here https://guthib.com to collect the dollar. He also wants to send \"test"
      app = build(:oauth_application, name: name)

      refute_predicate app, :valid?
      assert_predicate app.errors[:name], :any?
      assert_includes app.errors[:name], "should not include any URLs"
    end
  end

  test "requires valid url" do
    app = build :oauth_application, url: nil, domain: "abc"
    app.valid?
    assert_nil app.domain
    assert app.errors[:url].any?

    app.url = "ftp://foo.com"
    app.valid?
    assert_equal "foo.com", app.domain
    assert app.errors[:url].any?

    app.url = "http://foo.com"
    app.valid?
    assert_equal "foo.com", app.domain
    refute app.errors[:url].any?

    app.url = "https://foo.com"
    app.valid?
    assert_equal "foo.com", app.domain
    refute app.errors[:url].any?
  end

  test "requires valid callback_url" do
    app = build :oauth_application, callback_url: "foo.com"
    app.user_id = app.user.id
    app.valid?
    assert app.errors[:callback_url].any?

    app.callback_url = "http://foo.com"
    app.valid?
    refute app.errors[:callback_url].any?

    app.callback_url = "oob://foo.com"
    app.valid?
    refute app.errors[:callback_url].any?

    app.callback_url = "http://abc.com?🐹def=org"
    app.valid?
    assert app.errors[:callback_url].any?
  end

  test "setting callback_url updates the callback_urls array" do
    url = "http://foo.com"
    app = build :oauth_application, callback_url: url
    assert_same_elements [url], app.application_callback_urls.map(&:url)
  end

  test "setting callback_url updates the application_callback_urls" do
    url = "http://foo.com"
    app = create(:oauth_application, callback_url: url)
    assert_equal [url], app.application_callback_urls.pluck(:url)
  end

  test "setting callback_url updates callback_uri" do
    url1 = "http://foo.com"
    url2 = "http://foo2.com"
    app = build :oauth_application, callback_url: url1
    assert_equal url1, app.callback_uri.to_s
    app.callback_url = url2
    assert_equal url2, app.callback_uri.to_s
  end

  test "setting appplication_callback_urls updates callback_url" do
    url1 = "http://foo.com"
    url2 = "http://foo2.com"
    app = build :oauth_application, callback_url: url1
    app.set_application_callback_urls(url2)
    assert_equal app.application_callback_urls.first.url, url2
  end

  test "setting application_callback_urls array updates callback_uri" do
    url1 = "http://foo.com"
    url2 = "http://foo2.com"
    app = build :oauth_application, callback_url: url1
    assert_equal url1, app.callback_uri.to_s
    app.set_application_callback_urls(url2)
    assert_equal url2, app.callback_uri.to_s
  end

  test "callback_url prefers the first url in application_callback_urls" do
    url = "http://foo.com"
    app = OauthApplication.new
    app.set_application_callback_urls(url)
    assert_equal url, app.callback_url
  end

  test "setting application_callback_urls de-dupes" do
    url = "http://foo.com"
    app = OauthApplication.new
    app.set_application_callback_urls([url, url])
    assert_equal url, app.callback_url
    assert_same_elements [url], app.application_callback_urls.map(&:url)
  end

  test "blank application_callback_urls defaults to url" do
    url = "http://foo.com"
    app = OauthApplication.new url: url
    ["", nil, [""]].each do |u|
      app.set_application_callback_urls(u)
      assert_equal url, app.callback_url, "setting callback_urls = #{u}"
      assert_equal [url], app.application_callback_urls.map(&:url)
    end
  end

  test "setting the url updates the application_callback_urls" do
    url = "http://foo.com"
    app = build :oauth_application, url: url, callback_url: nil
    assert_equal url, app.callback_url
    assert_same_elements [url], app.application_callback_urls.map(&:url)
  end

  test "callback_url and application url must use a non-blacklisted scheme" do
    url = "http://foo.com"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?
    IntegrationUrl::BLOCKED_SCHEMES.each do |scheme|
      app.callback_url = "#{scheme}://foo.com"
      app.url = "#{scheme}://foo.com"
      refute app.valid?
      assert app.errors[:callback_url].any?
      assert app.errors[:url].any?
    end
  end

  test "An application with a singular callback_url can contain a reserved query key" do
    url = "http://foo.com?code=test"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?
  end

  test "An application with multiple callback_urls cannot contain a reserved query key" do
    urls = %q(
      http://foo.com
      http://foo.com?code=test
    )
    app = build :oauth_application, user: @user, url: urls.first, callback_url: urls
    refute app.valid?
    assert app.errors[:url].any?
  end

  test "An application with a singular callback_url can contain a fragment" do
    url = "http://foo.com#some_fragment"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?
  end

  test "An application with multiple callback_urls cannot contain a fragment" do
    urls = %q(
      http://foo.com
      url = "http://foo.com#some_fragment"
    )
    app = build :oauth_application, user: @user, url: urls.first, callback_url: urls
    refute app.valid?
    assert app.errors[:url].any?
  end

  test "callback_url can use a scheme that uses any characters allowed by the RFC " do
    url = "http://foo.com"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?
    GOOD_SCHEME_CHARS.each do |character|
      app.callback_url = "test-#{character}://foo.com"
      assert app.valid?, "Valid character found to be invalid: #{character}"
    end
  end

  test "application url scheme is limited to http(s)" do
    url = "http://foo.com"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?
    # While these are all valid scheme characters, only http(s) are allowed
    GOOD_SCHEME_CHARS.each do |character|
      app.url = "test-#{character}://foo.com"
      refute app.valid?, "Valid character found to be invalid: #{character}"
      assert app.errors[:url].any?
    end

    %w(http https).each do |scheme|
      app.url = "#{scheme}://foo.com"
      assert app.valid?, "Valid character found to be invalid: #{scheme}"
    end
  end

  test "callback_url scheme must begin with a letter" do
    url = "http://foo.com"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?
    allowed_secondary_characters = GOOD_SCHEME_CHARS - ALPHA_CHARS
    allowed_secondary_characters.each do |character|
      app.callback_url = "#{character}test://foo.com"
      app.url = "#{character}test://foo.com"
      refute app.valid?, "Invalid character found to be valid: #{character}"
      assert app.errors[:callback_url].any?
      assert app.errors[:url].any?
    end
  end

  test "callback_url and application url scheme must not contain characters not allowed by the RFC" do
    url = "http://foo.com"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?
    BAD_SCHEME_CHARS.each do |character|
      test_url = "test-#{character}://foo.com".dup.force_encoding("UTF-8")
      app.callback_url = test_url
      app.url = test_url

      refute app.valid?, "Invalid character found to be valid: #{character}"
      assert app.errors[:callback_url].any?
      assert app.errors[:url].any?
    end
  end

  test "callback_url and application url host must not contain whitespace or control characters" do
    url = "http://foo.com"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?
    whitespace_characters = " \t\n\0".split("")
    whitespace_characters.each do |character|
      app.callback_url = "http://fo#{character}o.com"
      app.url = "http://fo#{character}o.com"
      refute app.valid?, "Invalid whitespace or control character found to be valid: \\x#{character.ord.to_s(16)}"
      assert app.errors[:callback_url].any?
      assert app.errors[:url].any?
    end
  end

  test "callback_url and application url host must not contain reserved characters" do
    url = "http://foo.com"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?
    # The following is borrowed from a list of characters Addressable::URI  does
    # not allow in hosts. It is not necessarily complete, but provides a
    # reasonable baseline for validating that our use of Addressable::URI is
    # working.
    reserved_characters = %w(< > { })
    reserved_characters.each do |character|
      app.callback_url = "http://fo#{character}o.com"
      app.url = "http://fo#{character}o.com"
      refute app.valid?, "Invalid reserved character found to be valid: #{character}"
      assert app.errors[:callback_url].any?
      assert app.errors[:url].any?
    end
  end

  test "callback_url and application url host must not be blank if http(s)" do
    url = "http://foo.com"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?

    # A triple slash is generally a typo, but it is parsed as an absolute url
    # with a blank host and a path of /foo.com
    app.callback_url = "http:///foo.com"
    app.url = "http:///foo.com"
    assert app.callback_uri.absolute?
    assert_equal "/foo.com", app.callback_uri.path
    assert_predicate app.callback_uri.host, :blank?
    refute app.valid?, "Blank host not allowed"
    assert app.errors[:callback_url].any?
    assert app.errors[:url].any?
  end

  test "callback_url host can be empty if custom scheme" do
    url = "http://foo.com"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?

    # Custom schemes will often leave the host empty since there is no host
    # associated with their application.
    app.callback_url = "test-scheme:///foo.com"
    assert app.callback_uri.absolute?
    # assert_equal "/foo.com", app.callback_uri.path
    assert_equal "", app.callback_uri.host
    assert app.valid?, "Empty host with a custom URI is allowed"
  end

  test "callback_url host must not be nil if custom scheme" do
    url = "http://foo.com"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?

    # A URL without the "://" component is interpretted as having a nil host
    # and should never be needed by an OAuth application.
    app.callback_url = "test-scheme:/foo.com"
    assert app.callback_uri.absolute?
    assert_equal "/foo.com", app.callback_uri.path
    assert_nil app.callback_uri.host
    refute app.valid?, "Nil host with a custom URI is not allowed"
    assert app.errors[:callback_url].any?
  end

  test "callback_url and application url userinfo must not contain whitespace or control characters" do
    url = "http://foo.com"
    app = build :oauth_application, user: @user, url: url, callback_url: nil
    assert app.valid?
    whitespace_characters = " \t\n\0".split("")
    whitespace_characters.each do |character|
      app.callback_url = "http://user:pass#{character}word@foo.com"
      app.url = "http://user:pass#{character}word@foo.com"
      refute app.valid?, "Invalid whitespace or control character found to be valid: \\x#{character.ord.to_s(16)}"
      assert app.errors[:callback_url].any?
      assert app.errors[:url].any?
    end
  end

  test "callback_url and application url must not contain leading/trailing whitespace" do
    url = "http://foo.com"
    app = build :oauth_application, user: @user, url: url, callback_url: url
    assert app.valid?

    app.callback_url = " http://foo.com"
    app.url = "http://foo.com "
    refute app.valid?, "Leading and trailing whitespace are not allowed"
    assert app.errors[:callback_url].any?
    assert app.errors[:url].any?
  end

  test "requires unique key" do
    app = build :oauth_application, user: @user, key: @app.key
    refute app.valid?
    assert app.errors[:key].any?
  end

  test "accesses user" do
    assert_equal @user, @app.reload.user
  end

  test "is valid" do
    assert @app.valid?
  end

  context "fingerprint changes when attributes change" do
    test "fingerprint changes when name changes" do
      original_fingerprint = @app.synchronization_fingerprint
      @app.update(name: "foo")
      refute_equal original_fingerprint, @app.reload.synchronization_fingerprint
    end

    test "fingerprint changes when description changes" do
      original_fingerprint = @app.synchronization_fingerprint
      @app.update(description: "foo")
      refute_equal original_fingerprint, @app.reload.synchronization_fingerprint
    end

    test "fingerprint changes when key changes" do
      original_fingerprint = @app.synchronization_fingerprint
      @app.update(key: "foo")
      refute_equal original_fingerprint, @app.reload.synchronization_fingerprint
    end

    test "fingerprint changes when url changes" do
      original_fingerprint = @app.synchronization_fingerprint
      @app.update(url: "http://foo-test.com")
      refute_equal original_fingerprint, @app.reload.synchronization_fingerprint
    end

    test "fingerprint changes when device flow enabled changes" do
      original_fingerprint = @app.synchronization_fingerprint
      @app.update(device_flow_enabled: !@app.device_flow_enabled)
      refute_equal original_fingerprint, @app.synchronization_fingerprint
    end

    test "fingerprint changes when callback url changes" do
      original_fingerprint = @app.synchronization_fingerprint
      @app.set_application_callback_urls("http://foo-test.com")
      refute_equal original_fingerprint, @app.synchronization_fingerprint
    end

    test "fingerprint changes when app ownership changes" do
      app = create :oauth_application, user: @user
      original_fingerprint = app.synchronization_fingerprint

      app.transfer_ownership_to(@org, requester: @admin, responder: @admin)

      assert_equal @org, app.reload.user
      refute_equal original_fingerprint, app.synchronization_fingerprint
    end
  end

  test "has a key and no secret" do
    found = OauthApplication.find_by_key(@app.key)
    assert_equal @app, found
    assert_equal @app.key, found.key
  end

  test "has a maximum number of client secrets" do
    OauthApplicationClientSecret.stub_const(:MAX_SECRETS, 2) do
      assert_equal 0, @app.client_secrets.count
      refute_predicate @app, :max_client_secrets_reached?
      @app.client_secrets.create(creator: @app.user)
      assert_equal 1, @app.client_secrets.count
      refute_predicate @app, :max_client_secrets_reached?
      @app.client_secrets.create(creator: @app.user)
      assert_equal 2, @app.client_secrets.count
      assert_predicate @app, :max_client_secrets_reached?
    end
  end

  test "has a hashed client secret" do
    found = OauthApplication.find_by_key(@app.key)
    assert_equal 0, found.client_secrets.count
    secret = found.generate_client_secret(creator: @user)
    assert_equal 1, found.client_secrets.count
    client_secret = found.client_secrets.first
    assert_equal Digest::SHA256.base64digest(secret.secret), client_secret.secret_hash
    assert_equal secret.secret.last(8), client_secret.secret_last_eight
  end

  test "instruments generating a client secret" do
    events = subscribe "oauth_application.generate_client_secret"
    @app.generate_client_secret(creator: @user)
    expected_payload = {
      oauth_application: @app.name,
      oauth_application_id: @app.id,
      user: @user.login,
      user_id: @user.id,
      state: 0,
      rate_limit: 5000,
      application_url: @app.url,
      callback_url: @app.callback_url,
    }

    assert event = events.pop, "not instrumented"
    assert_equal "oauth_application.generate_client_secret", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments removing a client secret" do
    events = subscribe "oauth_application.remove_client_secret"
    secret1 = @app.generate_client_secret(creator: @user)
    secret2 = @app.generate_client_secret(creator: @user)

    secret1.destroy

    expected_payload = {
      oauth_application: @app.name,
      oauth_application_id: @app.id,
      user: @user.login,
      user_id: @user.id,
      state: 0,
      rate_limit: 5000,
      application_url: @app.url,
      callback_url: @app.callback_url,
    }

    assert event = events.pop, "not instrumented"
    assert_equal "oauth_application.remove_client_secret", event.name
    assert_equal expected_payload, event.payload
  end

  test "does not instrument removing a client secret when the app is destroyed" do
    events = subscribe "oauth_application.remove_client_secret"
    secret1 = @app.generate_client_secret(creator: @user)
    secret2 = @app.generate_client_secret(creator: @user)

    @app.destroy

    assert_empty events
  end

  test "validates plain text client secret" do
    secret = @app.generate_client_secret(creator: @app.user)
    assert @app.validate_client_secret(secret.secret)
    refute @app.validate_client_secret(secret.secret_hash)
    refute @app.validate_client_secret(nil)
    refute @app.validate_client_secret("")
  end

  test "granting access to a user" do
    access = @app.grant(@user3)
    assert_equal @user3, access.user
    assert_equal @app, access.application
    assert_nil access.hashed_token
    assert_nil access.token_last_eight
    assert access.code
  end

  if GitHub.email_verification_enabled?
    test "unverified user cannot be granted access" do
      User.any_instance.stubs(:must_verify_email?).returns(true)
      assert_raises ActiveRecord::RecordInvalid do
        refute @app.grant(@user3)
      end
    end
  end

  test "grant creates new access with new scope and doesn't change scope of old access" do
    assert_same_elements %w(user), @access.scopes
    access2 = @app.grant @user, scope: "user, repo"
    refute_equal @access, access2
    assert_same_elements %w(repo user), access2.scopes
    assert_same_elements %w(user), @access.reload.scopes
  end

  test "grants creates new acccess with empty scope and doesn't change scope of old access" do
    assert_same_elements %w(user), @access.scopes
    access2 = @app.grant @user
    refute_equal @access, access2
    assert_same_elements [], access2.scopes
    assert_same_elements %w(user), @access.reload.scopes
  end

  test ".blockable_client_apps scope returns first-party oauth client apps as configured in the internal apps registry" do
    blockable_app = create_privileged_app_with_capabilities(
      type: :oauth_application,
      capabilities: {
        blockable_first_party_client: true,
      }
    )

    assert_includes OauthApplication.blockable_client_apps, blockable_app
  end

  context "#blockable_client_app?" do
    test "returns true for blockable client app" do
      make_trusted_oauth_apps_owner
      app = create(:blockable_oauth_app)
      assert_predicate app, :blockable_client_app?
    end

    test "returns false for non-blockable client app" do
      app = create(:oauth_application)
      refute_predicate app, :blockable_client_app?
    end
  end

  context "granting Organization::CredentialAuthorization records" do
    test "grants authorizations orgs that have an active external session" do
      external_identity_session = create(:external_identity_session)

      organization = external_identity_session.external_identity.provider.organization
      session      = external_identity_session.user_session
      user         = session.user

      access = @app.grant(user, user_session: session)
      refute_nil Organization::CredentialAuthorization.find_by(organization: organization, credential: access, actor: user)
    end

    test "skips for internal helphub app" do
      external_identity_session = create(:external_identity_session)

      organization = external_identity_session.external_identity.provider.organization
      session      = external_identity_session.user_session
      user         = session.user

      access = @helphub_app.grant(user, user_session: session)
      assert access.valid?
      assert_nil Organization::CredentialAuthorization.find_by(organization: organization, credential: access, actor: user)
    end

    test "requires a user session" do
      external_identity_session = create(:external_identity_session)

      organization = external_identity_session.external_identity.provider.organization
      user = external_identity_session.user_session.user

      access = @app.grant(user)
      assert_nil Organization::CredentialAuthorization.find_by(organization: organization, credential: access, actor: user)
    end

    test "requires the user session and the user to be the same" do
      external_identity_session = create(:external_identity_session)

      organization = external_identity_session.external_identity.provider.organization
      session = external_identity_session.user_session

      access = @app.grant(@user, user_session: session)
      assert_nil Organization::CredentialAuthorization.find_by(organization: organization, credential: access, actor: @user)
    end
  end

  test "#async_revoke_tokens" do
    assert @app.accesses.any?

    assert_difference "@app.accesses.count", -2 do
      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs { @app.async_revoke_tokens(entry_point: :test_case) }
      # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    end

    refute @app.accesses.any?
  end

  test "access_for_code resets the code" do
    access = @app.access_for_code(@access.code)
    @access.reload
    assert_equal @access, access
    assert_nil @access.code
  end

  test "cannot redeem missing code" do
    assert_nil @app.access_for_code("monkey")
  end

  test "cannot redeem zero code" do
    assert_nil @app.access_for_code(0)
  end

  test "cannot redeem expired code" do
    Timecop.freeze do
      access = @app.grant(@user, scope: "user")
      expired_time = (OauthAccess::CODE_EXPIRY + 1.minute).from_now
      Timecop.freeze(expired_time) do
        assert_nil @app.access_for_code(access.code)
      end
    end
  end

  test "can redeem non-expired code" do
    Timecop.freeze do
      access = @app.grant(@user, scope: "user")
      non_expired_time = (OauthAccess::CODE_EXPIRY - 1.minute).from_now
      Timecop.freeze(non_expired_time) do
        assert_equal access, @app.access_for_code(access.code)
      end
    end
  end

  test "defaults rate limit to GitHub default" do
    app = create :oauth_application, user: @user
    assert_equal GitHub.api_default_rate_limit, app.rate_limit
  end

  test "can have its own rate limit" do
    app = create :oauth_application, user: @user, rate_limit: 20000
    assert_equal 20000, app.rate_limit
  end

  test "can set a temporary rate limit increase" do
    app = create :oauth_application, user: @user
    app.set_temporary_rate_limit 12500, 3.hours
    app.reload
    assert_equal 12500, app.temporary_rate_limit
    assert_equal 12500, app.rate_limit
    assert_predicate app, :using_temporary_rate_limit?
  end

  test "can change a temporary rate limit" do
    app = create :oauth_application, user: @user
    app.set_temporary_rate_limit 12500, 1.hour
    app.reload
    assert_equal 12500, app.temporary_rate_limit
    assert_equal 12500, app.rate_limit

    app.set_temporary_rate_limit 25000, 1.hour
    app.reload
    assert_equal 25000, app.temporary_rate_limit
    assert_equal 25000, app.rate_limit
  end

  test "defaults a temporary rate limit increase duration to 3 days" do
    Timecop.freeze do
      app = create :oauth_application, user: @user
      app.set_temporary_rate_limit 12500
      app.reload
      assert_equal 12500, app.rate_limit
      assert_predicate app, :using_temporary_rate_limit?
      assert_equal 3, app.temporary_rate_limit_expires_at.utc.to_date - Time.now.utc.to_date
    end
  end

  test "isn't using a temporary rate limit by default" do
    assert_equal false, @app.using_temporary_rate_limit?
  end

  test "knows when its using a temporary rate limit" do
    app = create :oauth_application, user: @user
    app.set_temporary_rate_limit 12500
    app.reload
    assert_equal true, app.using_temporary_rate_limit?
  end

  context "adminable_by scope" do
    test "includes app owned by given user" do
      app = create(:oauth_application, user: @user)

      assert_includes OauthApplication.adminable_by(@user), app
    end

    test "includes app owned by organization the given user admins" do
      org = create(:organization, admin: @user)
      app = create(:oauth_application, user: org)

      assert_includes OauthApplication.adminable_by(@user), app
    end

    test "excludes app unrelated to given user" do
      app = create :oauth_application

      refute_includes OauthApplication.adminable_by(create(:user)), app
    end
  end

  context "not_in_marketplace scope" do
    test "includes app without a Marketplace listing" do
      assert_includes OauthApplication.not_in_marketplace, @app
    end

    test "excludes app that has a Marketplace listing" do
      create(:marketplace_listing, listable: @app)

      refute_includes OauthApplication.not_in_marketplace, @app
    end
  end

  test "can be suspended" do
    @app.state = :suspended
    assert_predicate @app, :suspended?
  end

  test "is not suspended by default" do
    refute_predicate @app, :suspended?
  end

  context "#can_delete?" do
    test "returns false when marketplace listing has subscribers and ff is enabled" do
      listing = create(:marketplace_listing, listable: @app)
      plan = create(:marketplace_listing_plan, :published, listing: listing)
      create(:billing_subscription_item, subscribable: plan)
      GitHub.flipper[:marketplace_allow_deleting_apps_with_no_active_subscriptions].enable

      refute @app.can_delete?
    end

    test "returns true when marketplace listing has subscribers and ff is disabled" do
      listing = create(:marketplace_listing, listable: @app)
      plan = create(:marketplace_listing_plan, :published, listing: listing)
      GitHub.flipper[:marketplace_allow_deleting_apps_with_no_active_subscriptions].disable

      assert @app.can_delete?
    end

    test "returns true when marketplace listing has no subscribers and ff is enabled" do
      listing = create(:marketplace_listing, listable: @app)
      plan = create(:marketplace_listing_plan, :published, listing: listing)
      GitHub.flipper[:marketplace_allow_deleting_apps_with_no_active_subscriptions].enable

      assert @app.can_delete?
    end

    test "returns true when marketplace listing has no active subscriptions and ff is enabled" do
      listing = create(:marketplace_listing, listable: @app)
      plan = create(:marketplace_listing_plan, :published, listing: listing)
      GitHub.flipper[:marketplace_allow_deleting_apps_with_no_active_subscriptions].enable

      assert @app.can_delete?
    end

    test "returns true when marketplace listing has cancelled subscriptions and ff is enabled" do
      listing = create(:marketplace_listing, listable: @app)
      plan = create(:marketplace_listing_plan, :published, listing: listing)
      create(:billing_subscription_item, subscribable: plan, quantity: 0)
      GitHub.flipper[:marketplace_allow_deleting_apps_with_no_active_subscriptions].enable

      assert @app.can_delete?
    end

    test "returns true when marketplace listing has no subscribers" do
      listing = create(:marketplace_listing, listable: @app)
      create(:marketplace_listing_plan, :published, listing: listing)

      assert @app.can_delete?
    end

    test "returns true when integration has no marketplace listing" do
      refute @app.marketplace_listing

      assert @app.can_delete?
    end
  end

  context "deletion" do
    test "can initiate asynchronous app deletion" do
      assert_enqueued_with job: OauthApplicationDeleteJob, args: [@app.id] do
        @app.async_destroy
      end
    end

    test "app is not pending deletion by default" do
      refute_predicate @app, :pending_deletion?
    end

    test "app knows if it is pending deletion" do
      @app.async_destroy
      assert_predicate @app, :pending_deletion?
    end

    test "deleting app also deletes keys created by the app" do
      access = @app.grant(@user, scope: "user, repo")

      user_key = @user.public_keys.create_with_verification \
        key: Sham.ssh_public_key,
        verifier: @user,
        oauth_authorization: access.authorization
      refute user_key.new_record?

      deploy_key = @repo.public_keys.create_with_verification \
        key: Sham.ssh_public_key,
        verifier: @user,
        oauth_authorization: access.authorization
      refute deploy_key.new_record?

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @app.destroy }
      refute PublicKey.exists?(user_key.id)
      refute PublicKey.exists?(deploy_key.id)
    end

    test "deleteing app also deletes associated hooks" do
      hook = create :hook, :web, oauth_application: @app

      assert Hook.find_by(id: hook.id)
      @app.destroy
      assert_nil Hook.find_by(id: hook.id)
    end

    test "app deletion job is retried on dirty exit" do
      assert_retry_on_dirty_exit job: OauthApplicationDeleteJob, args: [@app.id]
    end
  end

  context "instruments user owned app" do
    test "creation" do
      events = subscribe "oauth_application.create"
      @app = create :oauth_application, user: @user
      expected_payload = {
        oauth_application: @app.name,
        oauth_application_id: @app.id,
        user: @user.login,
        user_id: @user.id,
        state: 0,
        rate_limit: 5000,
        application_url: @app.url,
        callback_url: @app.callback_url,
      }

      assert event = events.pop, "not instrumented"
      assert_equal "oauth_application.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "revoking tokens" do
      events = subscribe "oauth_application.revoke_tokens"
      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs { @app.async_revoke_tokens(entry_point: :test_case) }
      # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      expected_payload = {
        oauth_application: @app.name,
        oauth_application_id: @app.id,
        user: @user.login,
        user_id: @user.id,
        tokens_revoked: 2,
        state: 0,
        rate_limit: 5000,
        application_url: @app.url,
        callback_url: @app.callback_url,
      }

      assert event = events.pop, "not instrumented"
      assert_equal "oauth_application.revoke_tokens", event.name
      assert_equal expected_payload, event.payload
    end

    test "deletion" do
      events = subscribe "oauth_application.destroy"
      @app.destroy
      expected_payload = {
        oauth_application: @app.name,
        oauth_application_id: @app.id,
        user: @user.login,
        user_id: @user.id,
        state: 0,
        rate_limit: 5000,
        application_url: @app.url,
        callback_url: @app.callback_url,
      }

      assert event = events.pop, "not instrumented"
      assert_equal "oauth_application.destroy", event.name
      assert_equal expected_payload, event.payload
    end

    test "suspension" do
      events = subscribe "oauth_application.suspend"

      assert_predicate @app, :active?
      @app.update(state: :suspended)

      expected_payload = {
        oauth_application: @app.name,
        oauth_application_id: @app.id,
        user: @user.login,
        user_id: @user.id,
        state: OauthApplication.states[:suspended],
        rate_limit: 5000,
        application_url: @app.url,
        callback_url: @app.callback_url,
      }

      assert event = events.pop, "not instrumented"
      assert_equal "oauth_application.suspend", event.name
      assert_equal expected_payload, event.payload
    end

    test "unsuspension" do
      events = subscribe "oauth_application.unsuspend"

      @app.update(state: :suspended)
      @app.reload

      assert_predicate @app, :suspended?
      @app.update(state: :active)

      expected_payload = {
        oauth_application: @app.name,
        oauth_application_id: @app.id,
        user: @user.login,
        user_id: @user.id,
        state: OauthApplication.states[:active],
        rate_limit: 5000,
        application_url: @app.url,
        callback_url: @app.callback_url,
      }

      assert event = events.pop, "not instrumented"
      assert_equal "oauth_application.unsuspend", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "instruments org owned app" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @org     = create(:organization)
      @org_app = create :oauth_application, user: @org
    end

    test "creation" do
      events = subscribe "oauth_application.create"
      @app = create :oauth_application, user: @org
      expected_payload = {
        oauth_application: @app.name,
        oauth_application_id: @app.id,
        org: @org.login,
        org_id: @org.id,
        state: 0,
        rate_limit: 5000,
        application_url: @app.url,
        callback_url: @app.callback_url,
      }

      assert event = events.pop, "not instrumented"
      assert_equal "oauth_application.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "revoking tokens" do
      events = subscribe "oauth_application.revoke_tokens"
      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs { @org_app.async_revoke_tokens(entry_point: :test_case) }
      # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      expected_payload = {
        oauth_application: @org_app.name,
        oauth_application_id: @org_app.id,
        org: @org.login,
        org_id: @org.id,
        tokens_revoked: 0,
        state: 0,
        rate_limit: 5000,
        application_url: @org_app.url,
        callback_url: @org_app.callback_url,
      }

      assert event = events.pop, "not instrumented"
      assert_equal "oauth_application.revoke_tokens", event.name
      assert_equal expected_payload, event.payload
    end

    test "deletion" do
      events = subscribe "oauth_application.destroy"
      @org_app.destroy
      expected_payload = {
        oauth_application: @org_app.name,
        oauth_application_id: @org_app.id,
        org: @org.login,
        org_id: @org.id,
        state: 0,
        rate_limit: 5000,
        application_url: @org_app.url,
        callback_url: @org_app.callback_url,
      }

      assert event = events.pop, "not instrumented"
      assert_equal "oauth_application.destroy", event.name
      assert_equal expected_payload, event.payload
    end
  end

  test ".created_by_count" do
    user = create(:user)
    assert_equal 0, OauthApplication.created_by_count(user)
    2.times { create(:oauth_application, user: user) }
    assert_equal 2, OauthApplication.created_by_count(user)
  end

  context ".find_by_key" do
    # https://github.com/github/ecosystem-apps/issues/1816
    test "returns nil when passed a UTF8/Emoji key" do
      assert_nil OauthApplication.find_by_key("🐸")
    end

    test "returns the correct App when passed an array of keys containing an invalid key" do
      found = OauthApplication.find_by_key([@app.key, "🐸"])
      assert_equal @app, found
      assert_equal @app.key, found.key
    end
  end

  # Looking for preferred_avatar_url tests? They have moved to:
  # packages/app_security/test/models/oauth_application/preferred_avatar_url_test.rb

  context ".tenant_slug_for_avatar" do
    if TestEnv.test_in_multitenancy_mode?
      test "returns tenant in Proxima" do
        assert_equal @user.enterprise_managed_business.slug, @app.tenant_slug_for_avatar
      end
    else
      test "is empty outside Proxima" do
        assert_equal "", @app.tenant_slug_for_avatar
      end
    end
  end

  test "#synacble_to_proxima only includes apps with available proxima_availability" do
    syncable = create(:oauth_application, proxima_availability: :available)
    not_syncable = create(:oauth_application, proxima_availability: :unavailable)

    assert_equal [syncable], OauthApplication.syncable_to_proxima
  end

  context "#syncable_to_proxima?" do
    test "is not syncable by default" do
      app = create(:oauth_application)

      assert_equal "unavailable", app.proxima_availability
      refute Apps::Privileged.capable?(:proxima_first_party_sync, app: app)
      refute app.syncable_to_proxima?
    end

    test "is syncable when app has proxima availability :available" do
      app = create(:oauth_application, proxima_availability: :available)

      assert_equal "available", app.proxima_availability
      refute Apps::Privileged.capable?(:proxima_first_party_sync, app: app)
      assert app.syncable_to_proxima?
    end

    test "is syncable when app is capable of proxima sync" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, type: :oauth_application)

      assert_equal "unavailable", app.proxima_availability
      assert Apps::Privileged.capable?(:proxima_first_party_sync, app: app)
      assert app.syncable_to_proxima?
    end
  end
end

class TransferOwnershipToTest < GitHub::TestCase
  fixtures do
    @admin = create :user, login: "org-admin"
    @org   = create :organization, login: "target-org", admin: @admin

    team = @org.teams.create(name: "Employees")

    @app = create :oauth_application, \
      user: @admin,
      name: "Code Scanner Pro"
  end

  test "transfers ownership" do
    @app.transfer_ownership_to(@org, requester: @admin, responder: @admin)
    assert_equal @org, @app.reload.user
  end

  test "deletes pending transfer" do
    xfer = OauthApplicationTransfer.start \
      requester: @admin,
      application: @app,
      target: @org
    assert xfer

    @app.transfer_ownership_to(@org, requester: @admin, responder: @admin)
    assert_equal @org, @app.reload.user
    refute OauthApplicationTransfer.where(id: xfer.id).exists?
  end

  test "deletes previous Org Application Policy approvals for app for target org" do
    @org.enable_oauth_application_restrictions
    @org.approve_oauth_application(@app, approver: @admin)
    assert_difference "@app.approvals.count", -1 do
      @app.transfer_ownership_to(@org, requester: @admin, responder: @admin)
    end
    assert_equal @org, @app.reload.user
  end

  context "EMUs apps", skip_enterprise: true, feature_enabled: :block_emu_transfers_to_non_emu_target do
    test "can't transfer ownership to a regular user" do
      GitHub.flipper[:integration_installable_on_with_emus_check].enable
      emu = create(:emu)
      emu_app = create(:oauth_application, user: emu)

      transfer = emu_app.transfer_ownership_to(@admin, requester: emu, responder: @admin)

      refute transfer
      assert_equal emu, emu_app.reload.owner
    end

    test "can't transfer ownership to a regular organization" do
      GitHub.flipper[:integration_installable_on_with_emus_check].enable
      emu = create(:emu)
      emu_app = create(:oauth_application, user: emu)

      transfer = emu_app.transfer_ownership_to(create(:organization), requester: emu, responder: @admin)

      refute transfer
      assert_equal emu, emu_app.reload.owner
    end

    test "can't transfer ownership to an EMU from another enterprise" do
      GitHub.flipper[:integration_installable_on_with_emus_check].enable
      emu = create(:emu)
      emu_app = create(:oauth_application, user: emu)
      emu_another_enterprise = create(:emu)

      transfer = emu_app.transfer_ownership_to(emu_another_enterprise, requester: emu, responder: emu_another_enterprise)

      refute transfer
      assert_equal emu, emu_app.reload.owner
    end

    test "can transfer ownership to a another EMU for the same Enterprise" do
      GitHub.flipper[:integration_installable_on_with_emus_check].enable
      emu = create(:emu)
      another_emu_same_enterprise = create(:emu, business: emu.enterprise_managed_business)
      emu_app = create(:oauth_application, user: emu)

      transfer = emu_app.transfer_ownership_to(another_emu_same_enterprise, requester: emu, responder: another_emu_same_enterprise)

      assert transfer
      assert_equal another_emu_same_enterprise, emu_app.reload.owner
    end

    test "can't transfer ownership to an org from another enterprise" do
      GitHub.flipper[:integration_installable_on_with_emus_check].enable
      emu = create(:emu)
      another_enterprise_org = create(:organization, business: create(:business))
      emu_app = create(:oauth_application, user: emu)

      transfer = emu_app.transfer_ownership_to(another_enterprise_org, requester: emu, responder: another_enterprise_org)

      refute transfer
      assert_equal emu, emu_app.reload.owner
    end

    test "can transfer ownership to an org on same enterprise" do
      GitHub.flipper[:integration_installable_on_with_emus_check].enable
      emu = create(:emu)
      enterprise_org = create(:organization, business: emu.enterprise_managed_business)
      emu_app = create(:oauth_application, user: emu)

      transfer = emu_app.transfer_ownership_to(enterprise_org, requester: emu, responder: enterprise_org)

      assert transfer
      assert_equal enterprise_org, emu_app.reload.owner
    end
  end
end

# Looking for RegisteringOauthTrustedApplicationsTest? Try:
# test/models/oauth_application/registering_oauth_trusted_applications_test.rb

class OAuthApplicationAuditLogSearchingTest < GitHub::TestCase
  setup do
    @user   = create(:user)
    @app    = create(:oauth_application, user: @user, id: 13579)
  end

  test "audit_log_query" do
    query = "(data.oauth_application_id:13579 OR data.application_id:13579)"
    assert_equal query, @app.audit_log_query
  end
end
