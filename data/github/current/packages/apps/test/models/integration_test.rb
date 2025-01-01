# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  fixtures do
    @github = make_trusted_oauth_apps_owner

    @user = create(:user)
    @integration = create :integration, :with_active_hook, owner: @user
    @other_integration = create(:integration, :with_active_hook)

    enterprise_installation = create :enterprise_installation
    @connect_integration, @connect_integration_secret = enterprise_installation.create_github_app

    GitHub.flipper[:decrease_abuse_limits_multiplier].disable
    GitHub.flipper[:disable_abuse_limits_multiplier].disable
    GitHub.flipper[:increase_abuse_limits_multiplier].disable
    GitHub.flipper[:increase_abuse_limits_multiplier_high].disable
    GitHub.flipper[:enterprise_owned_app_management].disable
    GitHub.flipper[:fake_internal_integration_state].disable
  end

  test "removes trailing and leading spaces from name" do
    int = create(:integration, name: " leading space ")

    assert_equal "leading space", int.name
  end

  test "requires a valid hex color code for background color" do
    integration = Integration.new(bgcolor: "ff")
    refute_predicate integration, :valid?
    assert_predicate integration.errors[:bgcolor], :any?, "should require a valid hex color code"
  end

  test "it validates pinned_api_version" do
    GitHub.stubs(:api_versions).returns(["2020-01-01"])
    integration = build :integration
    integration.pinned_api_version = "bad"
    refute integration.valid?
    assert_equal "Pinned api version is invalid", integration.errors.full_messages.to_sentence
    integration.pinned_api_version = "2020-01-01"
    assert integration.valid?
  end

  test "strips pound sign from bgcolor before validation" do
    app = build(:integration, bgcolor: "#ff00ff")
    assert_predicate app, :valid?
    assert_equal "ff00ff", app.bgcolor
  end

  context "#identicon_hash" do
    test "returns an unchanging string" do
      hash = @integration.identicon_hash
      assert_instance_of String, hash
      if GitHub.fips_mode?
        assert_equal 64, hash.length
      else
        assert_equal 40, hash.length
      end
      assert_equal hash, @integration.identicon_hash
    end
  end

  context "#identicon" do
    test "returns an Identicon using the app's identicon hash" do
      identicon = @integration.identicon
      assert_instance_of Identicon, identicon
      assert_equal identicon.hash, @integration.identicon_hash
    end
  end

  context "owner" do
    test "is required" do
      integration = build(:integration, owner: nil)
      refute integration.valid?
      assert integration.errors[:owner].any?
    end

    test "allows valid owner_types" do
      user = create(:user)

      integration = build(:integration, owner: user)
      assert integration.valid?
      refute integration.errors[:owner].any?

      integration.update(owner: create(:organization))
      assert integration.valid?
      refute integration.errors[:owner].any?

      integration.update(owner: create(:business))
      assert integration.valid?
      refute integration.errors[:owner].any?
    end

    test "does not allow invalid owner_types" do
      integration = build(:integration, owner_type: "Repository", owner_id: 1234)
      refute integration.valid?
      assert integration.errors[:owner_type].any?
    end

    test "#user_owned? returns false when owned by a Business" do
      integration_business = build(:integration, owner_type: "Business", owner_id: 1234, owner: create(:business))
      refute integration_business.user_owned?
    end

    test "#user_owned? returns false when owned by an Organization" do
      integration_org = build(:integration, owner: create(:organization))
      refute integration_org.user_owned?
    end

    test "#user_owned? return true when owned by a User" do
      assert @integration.user_owned?
    end

    test "#organization_owned? returns false when owned by a Business" do
      integration_business = build(:integration, owner_type: "Business", owner_id: 1234, owner: create(:business))
      refute integration_business.organization_owned?
    end

    test "#organization_owned? returns false when owned by a User" do
      refute @integration.organization_owned?
    end

    test "#organization_owned? return true when owned by an Organization" do
      integration_org = build(:integration, owner: create(:organization))
      assert integration_org.organization_owned?
    end
  end

  test "fingerprint is the same if no fingerprint attributes change" do
    original_fingerprint = @integration.synchronization_fingerprint
    @integration.bgcolor = "bbb"
    assert_equal original_fingerprint, @integration.synchronization_fingerprint
  end

  test "fingerprint changes when attributes change" do
    %w(name key description).each_with_index do |attribute, index|
      # Timecop is used here to ensure that the updated_at changes during the tests
      Timecop.travel(index.minutes.from_now) do
        original_fingerprint = @integration.synchronization_fingerprint
        @integration.send(:"#{attribute}=", attribute.to_s)
        @integration.save!
        refute_equal original_fingerprint, @integration.synchronization_fingerprint, "expected #{attribute} to change fingerprint"
      end
    end

    original_fingerprint = @integration.synchronization_fingerprint
    @integration.device_flow_enabled = !@integration.device_flow_enabled
    @integration.save!
    refute_equal original_fingerprint, @integration.synchronization_fingerprint, "expected device_flow_enabled to change fingerprint"

    original_fingerprint = @integration.synchronization_fingerprint
    @integration.application_callback_urls.create!(url: "http://foo-test.com")
    @integration.save!
    refute_equal original_fingerprint, @integration.synchronization_fingerprint, "expected callback_urls to change fingerprint"
  end

  test "fingerprint changes when app ownership changes" do
    integration = create :integration, owner: @user
    original_fingerprint = integration.synchronization_fingerprint

    org = create :organization, login: "target-org", admin: @user
    integration.transfer_ownership_to(org, requester: @admin, responder: @admin, entry_point: :test_case)
    assert_equal org, integration.reload.owner

    refute_equal original_fingerprint, integration.synchronization_fingerprint, "expected device_flow_enabled to change fingerprint"
  end

  test "fingerprint changes when client_secrets changes" do
    client_secret = @integration.client_secrets.create!(secret: "initial_secret", creator: @user)
    original_fingerprint = @integration.synchronization_fingerprint

    # This should change the fingerprint
    client_secret.update!(secret: "new_secret")
    @integration.reload

    refute_equal original_fingerprint, @integration.fingerprint, "Fingerprint did not change when client_secret was updated"
  end

  test "fingeprint changes when public_keys change" do
    public_key = @integration.public_keys.create!(public_pem: Sham.ssh_public_key, creator: @user)
    original_fingerprint = @integration.synchronization_fingerprint

    # This should change the fingerprint
    public_key.update!(public_pem: Sham.ssh_public_key)
    @integration.reload

    refute_equal original_fingerprint, @integration.fingerprint, "Fingerprint did not change when public_key was updated"
  end

  test "disallows reserved words for routes as slugs" do
    refute_empty Integration::RESERVED_SLUGS

    Integration::RESERVED_SLUGS.each do |slug|
      integration = Integration.new(name: slug)

      refute_predicate integration, :valid?
      assert_equal slug, integration.slug
      assert_includes integration.errors[:name], "is a reserved word and cannot be used"
    end
  end

  test "disallows emojis in name" do
    integration = Integration.new(name: "aa🐹", owner: @integration.owner)

    refute_predicate integration, :valid?
    assert_predicate integration.errors[:name], :any?
  end

  test "supports emoji for description" do
    integration = create(:integration, description: "we ❤️ emojis")

    assert_multibyte_tracked_changes(integration, :description)
  end

  test "allows names that match another User if Integration was created first" do
    integration = create(:integration, name: "hubble")
    create(:user, login: "hubble")

    assert_predicate integration, :valid?
  end

  test "allows names that match another Organization if Integration was created first" do
    integration = create(:integration, name: "orghubble")
    create(:organization, login: "orghubble")

    assert_predicate integration, :valid?
  end

  test "allows names that match a Business if Integration was created first" do
    integration = create(:integration, name: "evil corp")
    create(:business, name: "evil corp")

    assert_predicate integration, :valid?
  end

  test "disallows names that match another existing Users handle" do
    rando = create(:user)
    user = create(:user)

    integration = build(:integration, name: rando.login, owner: user)

    refute_predicate integration, :valid?
    assert_includes integration.errors[:name], "is reserved for the account @#{rando.login}"
  end

  test "allows names that match owning users handle" do
    user = create(:user)

    integration = build(:integration, name: user.login, owner: user)

    assert_predicate integration, :valid?
  end

  test "allows names that match owning organizations handle" do
    org = create(:organization)

    integration = build(:integration, name: org.login, owner: org)

    assert_predicate integration, :valid?
  end

  test "allows names that match the business that owns the app owner" do
    business = create(:business, name: "TheBiz")
    business_owned_org = create(:business_plus_org).tap { |org| business.add_organization(org) }
    business_owned_org.reload

    integration = build(:integration, name: business.name, owner: business_owned_org)

    assert_predicate integration, :valid?
  end

  test "disallows names that match an Organizations handle" do
    org = create(:organization)
    user = create(:user)

    integration = build(:integration, name: org.login, owner: user)

    refute_predicate integration, :valid?
    assert_includes integration.errors[:name], "is reserved for the account @#{org.login}"
  end

  test "allows names that match an Organization's handle when overriden on enterprise", enterprise_only: true do
    org = create(:organization)
    user = create(:user)

    integration = build(:integration, name: org.login, owner: user, skip_slug_owner_check: true)

    assert_predicate integration, :valid?
  end

  test "disallows names that match an Organization's handle when overriden on dotcom", skip_enterprise: true do
    org = create(:organization)
    user = create(:user)

    integration = build(:integration, name: org.login, owner: user, skip_slug_owner_check: true)

    refute_predicate integration, :valid?
  end

  test "allows org admins to use names of Organizations they own" do
    user = create(:user)
    org = create(:organization)
    org.add_admin(user)

    integration = build(:integration, name: org.login, owner: user)

    assert_predicate integration, :valid?
  end

  test "allows organizations to user their own names, regardless of name case" do
    org = create(:organization, login: "ALLCAPS")
    integration = build(:integration, name: org.login, owner: org)

    assert_predicate integration, :valid?
  end

  test "disallows names that match an unaffiliated Business' slug" do
    business = create(:business)
    rando = create(:user)

    integration = build(:integration, name: business.slug, owner: rando)

    refute_predicate integration, :valid?
    assert_includes integration.errors[:name], "is reserved for the account #{business.slug}"
  end

  test "allows business admins to use names of Businesses they admin" do
    business = create(:business)
    admin = business.owners.first

    integration = build(:integration, name: business.slug, owner: admin)

    assert_predicate integration, :valid?
  end

  test "disallows business members (non-admins) to use names of Businesses they belong to" do
    business = create(:business)
    organization = create(:organization)
    business.add_organization(organization)
    user = create(:user)
    organization.add_member(user, adder: organization.admin)

    integration = build(:integration, name: business.slug, owner: user)

    refute_predicate integration, :valid?
  end

  test "allows names that match owning Business' slug" do
    business = create(:business)

    integration = build(:integration, name: business.slug, owner: business)

    assert_predicate integration, :valid?
  end

  test "allows names that match owning Business' slug regardless of case" do
    business = create(:business)

    integration = build(:enterprise_owned_integration, name: business.slug.upcase, owner: business)

    assert_predicate integration, :valid?
  end

  test "disallows some names including 'GitHub' or 'Gist' for non-employee user" do
    rando = create(:user)

    ["Github for the People", "gists are for lovers"].each do |name|
      integration = build(:integration, name: name, owner: rando)

      refute_predicate integration, :valid?
      assert_includes integration.errors[:name], "should not begin with 'GitHub' or 'Gist'"
    end

    ["Security by GitHub", "Marketplace from GitHub"].each do |name|
      integration = build(:integration, name: name, owner: rando)

      refute_predicate integration, :valid?
      assert_includes integration.errors[:name], "should not imply the integration is from GitHub"
    end
  end

  test "disallows some names including 'GitHub' or 'Gist' for non-github org" do
    random_org = create(:organization)

    ["Gist-worthy App", "github/github on GitHub"].each do |name|
      integration = build(:integration, name: name, owner: random_org)

      refute_predicate integration, :valid?
      assert_includes integration.errors[:name], "should not begin with 'GitHub' or 'Gist'"
    end

    ["Integrations by GitHub", "cool app from GitHub"].each do |name|
      integration = build(:integration, name: name, owner: random_org)

      refute_predicate integration, :valid?
      assert_includes integration.errors[:name], "should not imply the integration is from GitHub"
    end
  end

  test "disallows some names including special character variations of 'GitHub' or 'Gist' for non-github org" do
    random_org = create(:organization)

    ["ɡGist-worthy App", "github/github on ɡGitHub"].each do |name|
      integration = build(:integration, name: name, owner: random_org)

      refute_predicate integration, :valid?
      assert_includes integration.errors[:name], "should not generate slugs that begin with 'GitHub' or 'Gist'"
    end

    ["Integrations by ɡGitHub", "cool app from ɡGitHub"].each do |name|
      integration = build(:integration, name: name, owner: random_org)

      refute_predicate integration, :valid?
      assert_includes integration.errors[:name], "should not generate slugs that imply the integration is from GitHub"
    end
  end

  test "allows name including 'GitHub' for Dotcom site admin", skip_enterprise: true  do
    site_admin = create(:staff_admin_user)
    assert_predicate site_admin, :site_admin?

    integration = build(:integration, name: "github gist", owner: site_admin)
    assert_predicate integration, :valid?
  end

  test "disallows name including 'GitHub' for site_admin on Enterprise", enterprise_only: true do
    site_admin = create(:staff_admin_user)
    assert_predicate site_admin, :site_admin?
    refute_predicate site_admin, :employee?

    integration = build(:integration, name: "github gist", owner: site_admin)
    refute_predicate integration, :valid?
  end

  test "allows name including 'GitHub' for github org" do
    integration = build(:integration, name: "github gist", owner: GitHub.trusted_oauth_apps_owner)

    assert_predicate integration, :valid?
  end

  test "allows name including GitHub for existing Enterprise connect Apps" do
    enterprise_installation = create(:enterprise_installation)
    integration, secret = enterprise_installation.create_github_app

    # Make sure we run the validation for names starting with 'GitHub'
    integration.skip_restrict_names_with_github_validation = false

    # Update any field to test that the 'GitHub Enterprise' name is still valid
    integration.description = "irrelevant"

    assert_predicate integration, :valid?
  end

  context "URL in name validations" do
    test "does not allow names containing http urls" do
      integration = build(:integration, name: "Download here http://spammy.com")

      refute_predicate integration, :valid?
      assert_predicate integration.errors[:name], :any?
      assert_includes integration.errors[:name], "should not include any URLs"
    end

    test "does not allow names containing https urls" do
      integration = build(:integration, name: "Download here https://spammy.com")

      refute_predicate integration, :valid?
      assert_predicate integration.errors[:name], :any?
      assert_includes integration.errors[:name], "should not include any URLs"
    end
  end

  test "requires a valid hook when the hook url is nil" do
    integration = build(:integration, :with_hook)
    integration.hook.url = nil

    refute integration.save
    refute integration.valid?
    assert integration.errors[:hook].any?
  end

  test "requires valid url" do
    integration = build(:integration, url: nil)
    integration.valid?
    assert integration.errors[:url].any?

    integration.url = "ftp://foo.com"
    integration.valid?
    assert integration.errors[:url].any?

    integration.url = "https://some_attacker_domain%2523.gist.github.com/auth/github/callback"
    integration.valid?
    assert integration.errors[:url].any?

    integration.url = "http://foo.com"
    integration.valid?
    refute integration.errors[:url].any?

    integration.url = "https://foo.com"
    integration.valid?
    refute integration.errors[:url].any?
  end

  test "url host must not contain reserved characters" do
    url = "http://foo.com"
    integration = build(:integration, owner: @user, url: url)
    assert integration.valid?
    # The following is borrowed from a list of characters Addressable::URI  does
    # not allow in hosts. It is not necessarily complete, but provides a
    # reasonable baseline for validating that our use of Addressable::URI is
    # working.
    reserved_characters = %w(< > { })
    reserved_characters.each do |character|
      integration.url = "http://fo#{character}o.com"
      refute integration.valid?, "Invalid reserved character found to be valid: #{character}"
      assert integration.errors[:url].any?
    end
  end

  test "url host must not be blank" do
    url = "http://foo.com"
    integration = build(:integration, owner: @user, url: url)
    assert integration.valid?

    # A triple slash is generally a typo, but it is parsed as an absolute url
    # with a blank host and a path of /foo.com
    integration.url = "http:///foo.com"
    refute integration.valid?, "Blank host not allowed"
    assert integration.errors[:url].any?
  end

  test "url userinfo must not contain whitespace or control characters" do
    url = "http://foo.com"
    integration = build(:integration, owner: @user, url: url)
    assert integration.valid?
    whitespace_characters = " \t\n\0".split("")
    whitespace_characters.each do |character|
      integration.url = "http://user:pass#{character}word@foo.com"
      refute integration.valid?, "Invalid whitespace or control character found to be valid: \\x#{character.ord.to_s(16)}"
      assert integration.errors[:url].any?
    end
  end

  test "url must not contain leading/trailing whitespace" do
    url = "http://foo.com"
    integration = build(:integration, owner: @user, url: url)
    assert integration.valid?

    integration.url = "http://foo.com "
    refute integration.valid?, "Leading and trailing whitespace are not allowed"
    assert integration.errors[:url].any?
  end

  test "url can be a templated URL if app has Proxima sync and FF enabled" do
    url = "https://{hostname}/callback"
    integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })
    GitHub.flipper[:templatize_integration_url].enable(integration)
    integration.url = url

    assert_predicate integration, :valid?
  end

  test "url cannot be a templated URL if app has Proxima sync enabled and FF disabled" do
    url = "https://{hostname}/callback"
    integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })
    GitHub.flipper[:templatize_integration_url].disable(integration)
    integration.url = url

    refute_predicate integration, :valid?
  end

  test "url cannot be a templated URL if app does not have Proxima sync enabled" do
    url = "https://{hostname}/callback"
    integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: false }, options: { owner: @user })
    GitHub.flipper[:templatize_integration_url].enable(integration)
    integration.url = url

    refute_predicate integration, :valid?
  end

  test "url returns nil if the value is nil" do
    integration = build(:integration, owner: @user, url: nil)

    assert_nil integration.url
  end

  test "url is interpolated if app has Proxima sync and FF enabled" do
    url = "https://{hostname}/callback"
    integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })
    GitHub.flipper[:templatize_integration_url].enable(integration)
    integration.url = url

    assert_equal "#{GitHub.url}/callback", integration.url
  end

  test "url is not interpolated if app has Proxima sync disabled" do
    url = "https://{hostname}/callback"
    integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: false }, options: { owner: @user })
    GitHub.flipper[:templatize_integration_url].enable(integration)
    integration.url = url

    assert_equal url, integration.url
    refute_equal "#{GitHub.url}/callback", integration.url
  end

  context "application_callback_urls" do
    test "can have a maximum of 10" do
      (0..Integration::MAX_APPLICATION_CALLBACK_URLS).each do |index|
        @integration.application_callback_urls.build(url: "https://example.com/#{index}/callback")
      end

      refute_predicate @integration, :valid?
      assert_same_elements ["has too many callback urls (maximum is 10)"], @integration.errors.messages[:application_callback_urls]
    end

    test "are required if request_oauth_on_install is enabled" do
      integration = build(:integration, request_oauth_on_install: true)

      refute_predicate integration, :valid?
      assert_same_elements ["at least one callback URL is required"], integration.errors[:application_callback_urls]
    end
  end

  test "request_oauth_on_install is false by default" do
    integration = build(:integration, owner: @user)

    refute_predicate integration, :request_oauth_on_install?
  end

  test "request_oauth_on_install can be true" do
    integration = build(:integration, owner: @user, request_oauth_on_install: true)

    assert_predicate integration, :request_oauth_on_install?
  end

  test "can_request_oauth_on_install? is true when the boolean is true" do
    integration = create(:integration, owner: @user, application_callback_urls_attributes: [{ url: "http://example.com" }], request_oauth_on_install: true)
    assert_predicate integration, :can_request_oauth_on_install?
  end

  test "can_request_oauth_on_install? is false when there aren't any callback urls" do
    integration = build(:integration, owner: @user, request_oauth_on_install: true)

    assert_predicate integration.application_callback_urls, :none?
    refute_predicate integration, :can_request_oauth_on_install?
  end

  test "setup_url must use a non-blacklisted scheme" do
    setup_url = "http://foo.com/setup"
    integration = build(:integration, owner: @user, setup_url: setup_url)

    assert integration.valid?
    IntegrationUrl::BLOCKED_SCHEMES.each do |scheme|
      integration.setup_url = "#{scheme}://foo.com/setup"
      refute integration.valid?
      assert integration.errors[:setup_url].any?
    end
  end

  test "setup_url can be an empty string" do
    setup_url = ""
    integration = build(:integration, owner: @user, setup_url: setup_url)

    assert integration.valid?
  end

  test "setup_url can be a templated URL if app has Proxima sync enabled" do
    setup_url = "https://{hostname}/callback"
    integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })
    integration.setup_url = setup_url

    assert_predicate integration, :valid?
  end

  test "setup_url cannot be a templated URL if app does not have Proxima sync enabled" do
    setup_url = "https://{hostname}/callback"
    integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: false }, options: { owner: @user })
    integration.setup_url = setup_url

    refute_predicate integration, :valid?
  end

  test "setup_url returns nil if the value is nil" do
    integration = build(:integration, owner: @user, setup_url: nil)

    assert_nil integration.setup_url
  end

  test "setup_url is interpolated if app has Proxima sync enabled" do
    setup_url = "https://{hostname}/callback"
    integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })
    integration.setup_url = setup_url

    assert_equal "#{GitHub.url}/callback", integration.setup_url
  end

  test "setup_url is not interpolated if app has Proxima sync disabled" do
    setup_url = "https://{hostname}/callback"
    integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: false }, options: { owner: @user })
    integration.setup_url = setup_url

    assert_equal setup_url, integration.setup_url
    refute_equal "#{GitHub.url}/callback", integration.setup_url
  end

  test "setup_on_update is false by default" do
    integration = build(:integration, owner: @user)

    refute_predicate integration, :setup_on_update?
  end

  test "setup_on_update is false when setup_url is not provided" do
    integration = create(:integration, owner: @user, setup_on_update: true)

    refute_predicate integration, :setup_on_update?
  end

  test "setup_on_update can be true when setup_url is present" do
    integration = create(:integration, owner: @user, setup_url: "https://example.com", setup_on_update: true)

    assert_predicate integration, :setup_on_update?
  end

  test "setup_on_update can be true when setup_url is blank but can_request_oauth_on_install? is true" do
    integration = create(:integration,
                        owner: @user,
                        setup_url: "",
                        application_callback_urls_attributes: [{ url: "https://example.com/callback" }],
                        setup_on_update: true,
                        request_oauth_on_install: true,
                       )

    integration.valid? # triggers after_validation callbacks.
    assert_predicate integration, :request_oauth_on_install?
    refute_predicate integration.application_callback_urls.map(&:url), :empty?
    assert_predicate integration, :setup_on_update?
  end

  test "device_flow_enabled is false by default" do
    integration = build(:integration, owner: @user)

    refute_predicate integration, :device_flow_enabled?
  end

  test "device_flow_enabled can be true" do
    integration = build(:integration, owner: @user, device_flow_enabled: true)

    assert_predicate integration, :device_flow_enabled?
  end

  test "doesn't allow unsupported events" do
    integration = build(:integration, :with_hook, default_events: %w(foo issues))

    refute_predicate integration, :valid?
    assert_includes integration.errors[:default_events], "unsupported: foo"

    integration = create(:integration, :with_hook)
    assert_predicate integration, :valid?

    integration.default_events = %w(foo issues)
    integration.save

    refute_predicate integration, :valid?
    assert_includes integration.errors[:default_events], "unsupported: foo"
  end

  test "doesn't allow events without the corresponding permission" do
    integration = build(:integration,
      :with_hook,
      default_events: %w(issues),
      default_permissions: { "statuses" => :write },
    )

    refute integration.valid?
    assert_includes integration.errors[:default_events], "are not supported by permissions: issues"

    integration = create(:integration, :with_hook)
    integration.update(
      default_events: %w(issues),
      default_permissions: { "statuses" => :write },
    )

    refute_predicate integration, :valid?
    assert_includes integration.errors[:default_events], "are not supported by permissions: issues"
  end

  test "doesn't allow single file permissions without a single file name" do
    integration = build(:integration,
      default_permissions: { "single_file" => :read },
    )

    refute_predicate integration, :valid?
    assert_includes integration.errors[:single_file_name], "path is required."
  end

  test "doesn't allow a single file without single file permissions" do
    integration = build(:integration,
      single_file_paths: [".travis.yml"],
    )

    refute_predicate integration, :valid?
    assert_includes integration.errors[:default_permissions], "access to single file is required."
  end

  test "requires a unique name", feature_disabled: :owner_scoped_github_apps do
    create(:integration, name: "super ci")

    integration = Integration.new(name: "super ci")
    integration.valid?

    assert integration.errors[:name].any?
  end

  test "requires a unique name and owner", feature_enabled: :owner_scoped_github_apps do
    create(:integration, name: "super ci", owner: @user)

    integration = Integration.new(name: "super ci", owner: @user)
    integration.valid?

    assert integration.errors[:name].any?
  end

  test "name must contain at least one alphanumeric character" do
    integration = Integration.new(name: "微信抢红包实例")
    integration.valid?

    refute integration.slug.present?
    assert integration.errors[:name].any?
  end

  test "requires a unique slug", feature_disabled: :owner_scoped_github_apps do
    integration = create(:integration, name: "super ci")

    other_integration = Integration.new(name: "super: ci")
    other_integration.valid?

    assert integration.slug, other_integration.slug
    assert other_integration.errors[:name].any?
  end

  test "requires a unique slug and owner", feature_enabled: :owner_scoped_github_apps do
    integration = create(:integration, name: "super ci", owner: @user)

    other_integration = Integration.new(name: "super: ci", owner: @user)
    other_integration.valid?

    assert integration.slug, other_integration.slug
    assert other_integration.errors[:name].any?
  end

  test "requires a unique key" do
    integration = build(:integration, key: @integration.key)
    refute integration.valid?
    assert integration.errors[:key].any?
  end

  context "suspension" do
    context "#suspend" do
      test "returns false if app does not have danger zone capability" do
        integration = create_privileged_app_with_capabilities(capabilities: { danger_zone_permitted: false })
        admin = create(:staff_admin_user)

        refute integration.suspend(actor: admin, reason: "testing")
        integration.reload
        assert_nil integration.suspended_reason
        assert_nil integration.user_suspended_by
        assert_nil integration.suspended_at
      end

      test "returns true if integration is already suspended" do
        admin = create(:staff_admin_user)
        @integration.suspend(actor: admin, reason: "test")
        assert @integration.suspended?

        assert @integration.suspend(actor: admin, reason: "test once more")
        @integration.reload
        assert_equal "test", @integration.suspended_reason
      end

      test "returns false if actor is not a site admin" do
        non_admin = create(:user)

        refute @integration.suspend(actor: non_admin, reason: "testing")
      end

      test "returns false if reason is not provided" do
        admin = create(:staff_admin_user)

        refute @integration.suspend(actor: admin, reason: nil)
        @integration.reload
        refute @integration.suspended?
      end

      test "returns false if reason blank" do
        admin = create(:staff_admin_user)

        refute @integration.suspend(actor: admin, reason: "")
        @integration.reload
        refute @integration.suspended?
      end

      test "returns true if suspension is successful" do
        admin = create(:staff_admin_user)

        assert @integration.suspend(actor: admin, reason: "test")
        assert_equal admin, @integration.user_suspended_by
        refute_nil @integration.suspended_at
        assert_equal "test", @integration.suspended_reason
      end
    end

    context "#unsuspend" do
      test "returns true if integration is not currently suspended" do
        admin = create(:staff_admin_user)
        refute @integration.suspended?

        assert @integration.unsuspend(actor: admin)
      end

      test "returns false if actor is not a site admin" do
        admin = create(:staff_admin_user)
        @integration.suspend(actor: admin, reason: "test")
        assert @integration.suspended?
        non_admin = create(:user)

        refute @integration.unsuspend(actor: non_admin)
      end

      test "returns true if unsuspension is successful" do
        admin = create(:staff_admin_user)
        @integration.suspend(actor: admin, reason: "test")
        assert @integration.suspended?

        assert @integration.unsuspend(actor: admin)
        assert_nil @integration.user_suspended_by
        assert_nil @integration.suspended_at
        assert_nil @integration.suspended_reason
      end
    end

    context ".suspend_all_for_owner" do
      test "returns false if actor is not a site admin" do
        non_admin = create(:user)

        refute Integration.suspend_all_for_owner(actor: non_admin, owner: @user, reason: "testing")
      end

      test "returns false if reason is not provided" do
        admin = create(:staff_admin_user)

        refute Integration.suspend_all_for_owner(actor: admin, owner: @user, reason: "")
        refute @integration.reload.suspended?
      end

      test "returns true if suspension is successful" do
        integration = create(:integration, owner: @user)
        admin = create(:staff_admin_user)

        assert Integration.suspend_all_for_owner(actor: admin, owner: @user, reason: "testing")

        assert @integration.reload.suspended?
        assert_equal admin, @integration.user_suspended_by
        assert_equal "testing", @integration.suspended_reason
        refute_nil @integration.suspended_at

        assert integration.reload.suspended?
        assert_equal admin, integration.user_suspended_by
        assert_equal "testing", integration.suspended_reason
        refute_nil integration.suspended_at
      end

      test "skips apps which don't have danger zone capability" do
        integration = create_privileged_app_with_capabilities(capabilities: { danger_zone_permitted: false }, options: { owner: @user })
        admin = create(:staff_admin_user)
        assert_equal integration.owner, @integration.owner

        assert Integration.suspend_all_for_owner(actor: admin, owner: @user, reason: "testing")
        refute integration.reload.suspended?
        assert @integration.reload.suspended?
      end

      test "does not suspend apps for other owners" do
        integration = create(:integration)
        admin = create(:staff_admin_user)
        refute_equal integration.owner, @integration.owner

        assert Integration.suspend_all_for_owner(actor: admin, owner: @user, reason: "testing")
        refute integration.reload.suspended?
        assert @integration.reload.suspended?
      end

      test "suspends apps for a business owner" do
        admin = create(:staff_admin_user)
        business = create(:business, id: @user.id)
        integration = create(:enterprise_owned_integration, owner: business)

        assert Integration.suspend_all_for_owner(actor: admin, owner: business, reason: "testing")
        assert integration.reload.suspended?
        refute @integration.reload.suspended?
      end

      test "does not suspend apps for a business with the same id as a user owner" do
        admin = create(:staff_admin_user)
        business = create(:business, id: @user.id)
        integration = create(:enterprise_owned_integration, owner: business)

        assert Integration.suspend_all_for_owner(actor: admin, owner: @user, reason: "testing")
        assert @integration.reload.suspended?
        refute integration.reload.suspended?
      end

      test "instruments each suspension" do
        integration = create(:integration)
        owner = integration.owner
        admin = create(:staff_admin_user)

        events = subscribe "integration.suspend"
        expected_payload = {
          integration: integration.name,
          app: integration.name,
          integration_id: integration.id,
          app_id: integration.id,
          name: integration.name,
          slug: integration.slug,
          org: owner.to_s,
          org_id: owner.id,
          suspended_reason: "testing",
        }

        Integration.suspend_all_for_owner(actor: admin, owner: owner, reason: "testing")

        assert event = events.pop, "expected an instrument suspension event"
        assert_equal "integration.suspend", event.name
        assert_same_hash expected_payload, event.payload
      end
    end

    context ".unsuspend_all_for_owner" do
      test "returns false if actor is not a site admin" do
        admin = create(:staff_admin_user)
        non_admin = create(:user)
        @integration.suspend(actor: admin, reason: "test")

        refute Integration.unsuspend_all_for_owner(actor: non_admin, owner: @user)
        assert @integration.reload.suspended?
      end

      test "returns true if unsuspension is successful" do
        admin = create(:staff_admin_user)
        @integration.suspend(actor: admin, reason: "test")

        assert Integration.unsuspend_all_for_owner(actor: admin, owner: @user)
        refute @integration.reload.suspended?
        assert_nil @integration.user_suspended_by
        assert_nil @integration.suspended_reason
        assert_nil @integration.suspended_at
      end

      test "unsuspends apps for a business owner" do
        admin = create(:staff_admin_user)
        business = create(:business, id: @user.id)
        integration = create(:enterprise_owned_integration, owner: business)
        integration.suspend(actor: admin, reason: "test")
        @integration.suspend(actor: admin, reason: "test")

        assert Integration.unsuspend_all_for_owner(actor: admin, owner: business)
        refute integration.reload.suspended?
        assert @integration.reload.suspended?
      end

      test "does not unsuspend apps for other owners" do
        admin = create(:staff_admin_user)
        integration = create(:integration)
        integration.suspend(actor: admin, reason: "test")
        @integration.suspend(actor: admin, reason: "test")
        refute_equal integration.owner, @integration.owner

        assert Integration.unsuspend_all_for_owner(actor: admin, owner: @user)
        refute @integration.reload.suspended?
        assert integration.reload.suspended?
      end

      test "instruments each unsuspension" do
        integration = create(:integration)
        owner = integration.owner
        admin = create(:staff_admin_user)

        integration.suspend(actor: admin, reason: "test")

        events = subscribe "integration.unsuspend"
        expected_payload = {
          integration: integration.name,
          app: integration.name,
          integration_id: integration.id,
          app_id: integration.id,
          name: integration.name,
          slug: integration.slug,
          org: owner.to_s,
          org_id: owner.id
        }

        Integration.unsuspend_all_for_owner(actor: admin, owner: owner)

        assert event = events.pop, "expected an instrument unsuspension event"
        assert_equal "integration.unsuspend", event.name
        assert_same_hash expected_payload, event.payload
      end
    end
  end

  if GitHub.enterprise?
    test "allows integrations to be registered when seat count limit is reached" do

      # create the user before we exhaust the license seats
      owner = create :user

      GitHub::Enterprise.license_reset!
      GitHub::Enterprise.license.stubs(:reached_seat_limit?).returns(true)
      GitHub::Enterprise.license.stubs(:seats_available).returns(0)
      assert_predicate GitHub::Enterprise.license, :reached_seat_limit?, "should have reached the seat limit"
      assert_predicate GitHub::Enterprise.license.seats_available, :zero?, "should have zero seats"

      integration = create(:integration, owner: owner)

      assert integration.save
      assert_predicate integration, :valid?, "should be a valid Integration record"
    end
  end

  test "has a key and no secret" do
    assert @integration.key
    assert_equal 0, @integration.client_secrets.count
    assert_equal @integration, Integration.find_by(key: @integration.key)
  end

  test "has a hashed client secret" do
    found = Integration.find_by(key: @integration.key)
    assert_equal 0, T.must(found).client_secrets.count

    client_secret = @integration.generate_client_secret(creator: @user)
    assert_equal Digest::SHA256.base64digest(client_secret.secret), client_secret.secret_hash
    assert_equal client_secret.secret.last(8), client_secret.secret_last_eight
  end


  test "instruments generating a client secret" do
    events = subscribe "integration.generate_client_secret"
    @integration.generate_client_secret(creator: @user)
    expected_payload = {
      integration: @integration.name,
      app: @integration.name,
      integration_id: @integration.id,
      app_id: @integration.id,
      name: @integration.name,
      slug: @integration.slug,
      user: @integration.owner.to_s,
      user_id: @integration.owner.id,
    }

    assert event = events.pop, "not instrumented"
    assert_equal "integration.generate_client_secret", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments removing a client secret" do
    events = subscribe "integration.remove_client_secret"
    secret1 = @integration.generate_client_secret(creator: @user)
    secret2 = @integration.generate_client_secret(creator: @user)

    secret1.destroy

    expected_payload = {
      integration: @integration.name,
      app: @integration.name,
      integration_id: @integration.id,
      app_id: @integration.id,
      name: @integration.name,
      slug: @integration.slug,
      user: @integration.owner.to_s,
      user_id: @integration.owner.id,
    }

    assert event = events.pop, "not instrumented"
    assert_equal "integration.remove_client_secret", event.name
    assert_equal expected_payload, event.payload
  end

  test "has a maximum number of client secrets" do
    IntegrationClientSecret.stub_const(:MAX_SECRETS, 2) do
      assert_equal 0, @integration.client_secrets.count
      refute_predicate @integration, :max_client_secrets_reached?
      @integration.generate_client_secret(creator: @user)
      assert_equal 1, @integration.client_secrets.count
      refute_predicate @integration, :max_client_secrets_reached?
      @integration.client_secrets.create(creator: @integration.user)
      assert_predicate @integration, :max_client_secrets_reached?
    end
  end

  test "validates plain text client secret" do
    secret = @integration.generate_client_secret(creator: @integration.user)
    assert @integration.validate_client_secret(secret.secret)
    refute @integration.validate_client_secret(secret.secret_hash)
    refute @integration.validate_client_secret(nil)
    refute @integration.validate_client_secret("")
  end

  test "opts new integrations in to user token expiration" do
    integration = build(:integration)
    integration.save!

    assert integration.user_token_expiration_enabled?
  end

  test "allows user to opt out of user token expiration via user_token_expiration_enabled" do
    integration = build(:integration, user_token_expiration_enabled: "0")
    integration.save!

    refute integration.user_token_expiration_enabled?
  end

  test "generates a key that matches Integration::KEY_PATTERN_V1 with feature flag disabled" do
    GitHub.flipper[:globally_unique_client_ids].disable
    @integration = Integration.new
    assert_match Integration::KEY_PATTERN_V1, @integration.key
  end

  test "generates a key that matches Integration::KEY_PATTERN_V2 with feature flag enabled" do
    GitHub.flipper[:globally_unique_client_ids].enable
    integration = Integration.new(owner: @integration.owner)
    assert_match Integration::KEY_PATTERN_V2, integration.key
  end

  test "generates a key that matches Integration::KEY_PATTERN_V2 with feature flag enabled for a specific user" do
    user = create(:user)
    GitHub.flipper[:globally_unique_client_ids].disable
    GitHub.flipper[:globally_unique_client_ids].enable(user)

    integration = Integration.new(owner: user)
    assert_match Integration::KEY_PATTERN_V2, integration.key

    integration = Integration.new
    assert_match Integration::KEY_PATTERN_V1, integration.key
  end

  context ".client_id identification helpers" do
    test "client_id_type returns symbol of type matching the string format" do
      v1_string = "Iv1.1234567890abcdef"
      assert_equal :v1, Integration.client_id_type(v1_string)

      v2_string = "Iv2deb567890abdexxxf"
      assert_equal :v2, Integration.client_id_type(v2_string)
    end

    test "client_id_type returns :none if string format is not client id" do
      v1_string = "Iv1.1234567890abczef"
      assert_equal :none, Integration.client_id_type(v1_string)

      v2_string = "Iv2.%b567890abdexxxf"
      assert_equal :none, Integration.client_id_type(v2_string)
    end

    test "client_id? returns true if string format is client id" do
      v1_string = "Iv1.1234567890abcdef"
      assert Integration.client_id?(v1_string)

      v2_string = "Iv2deb567890abdexxxf"
      assert Integration.client_id?(v2_string)

      invalid_string = "Iv2.zb567890abdexxxf"
      refute Integration.client_id?(invalid_string)
    end
  end

  test "integrations can be renamed and keep the same slug" do
    integration = create(:integration, name: "super ci")

    integration.name = "super: ci"
    integration.valid?

    refute integration.errors[:name].any?
  end

  test "generates the slug automatically" do
    integration = create :integration, name: "Hubot: The second coming"
    assert_equal "hubot-the-second-coming", integration.slug
  end

  test "integrations can be created with a custom slug" do
    integration = create(:integration, name: "super ci", skip_generate_slug: true, slug: "super-ci-test")
    assert_equal "super-ci-test", integration.slug
  end

  test "does not allow the slug to be longer than bot slug" do
    name = "a#{'a' * Bot::MAX_SLUG_LENGTH}"

    integration = Integration.new(name: name)
    integration.valid?

    assert integration.errors[:name].any?
  end

  test "does not allow underscores in the slug" do
    integration = Integration.new name: "Hubot_The_Second_Coming"
    integration.valid?

    assert integration.errors[:name].any?
  end

  test "generates the bot's slug to match the integration slug" do
    integration = create :integration, name: "Hubot: The second coming"
    assert_equal integration.slug, integration.bot.slug
  end

  test "generates the alias's slug to match the integration slug" do
    GitHub.flipper[:owner_scoped_github_apps].disable
    integration = create :integration, name: "Hubot: The second coming"
    assert_equal integration.slug, integration.alias.slug
  end

  test "does not generate the alias when the flag is enabled" do
    GitHub.flipper[:owner_scoped_github_apps].enable
    integration = create :integration, name: "Hubot: The second coming"
    integration.reload

    assert_nil integration.alias
  end

  test "sets the bot login based on the app name when :owner_scoped_github_apps feature is diabled" do
    GitHub.flipper[:owner_scoped_github_apps].disable
    integration = create :integration, name: "Hubot: The second coming"

    assert_equal "hubot-the-second-coming[bot]", integration.bot.login
  end

  test "generates the bot login automatically when :owner_scoped_github_apps feature is enabled" do
    GitHub.flipper[:owner_scoped_github_apps].enable
    integration = create :integration, name: "Hubot: The second coming"

    refute_equal "hubot-the-second-coming[bot]", integration.bot.login
  end

  test "updates the integration and bot slugs when the integration is renamed" do
    integration = create :integration, name: "Hubot: The second coming"
    integration.update(name: "Hubot: The third coming")

    assert_equal "hubot-the-third-coming", integration.slug
    assert_equal "hubot-the-third-coming", integration.bot.slug
  end

  # This will not be the end behavior, if an integration has a alias and they change
  # the name of the app, they'll lose the alias.
  #
  # But until we ship this fully this is the expected behavior.
  test "updates the integration and alias's slugs when the integration is renamed" do
    GitHub.flipper[:owner_scoped_github_apps].disable
    integration = create :integration, name: "Hubot: The second coming"
    integration.update(name: "Hubot: The third coming")

    assert_equal "hubot-the-third-coming", integration.slug
    assert_equal "hubot-the-third-coming", integration.alias.slug
  end

  # We're making it to the end behavior from above!
  test "loses the alias's slugs when the integration is renamed" do
    GitHub.flipper[:owner_scoped_github_apps].disable
    integration = create :integration, name: "Hubot: The second coming"
    assert_equal "hubot-the-second-coming", integration.alias.slug

    GitHub.flipper[:owner_scoped_github_apps].enable
    integration.update(name: "Hubot: The third coming")
    integration.reload

    assert_equal "hubot-the-third-coming", integration.slug
    assert_nil integration.alias
  end

  test "reverts the slug name when the validation fails" do
    invalid_name = "a#{'a' * Bot::MAX_SLUG_LENGTH}"

    integration = create :integration, name: "Hubot: The second coming"
    integration.update(name: invalid_name)

    assert_equal "hubot-the-second-coming", integration.slug
  end

  test "adds new permissions" do
    @integration.update(default_permissions: { "metadata" => :read, "statuses" => :read })
    @integration.update(default_permissions: { "metadata" => :read, "statuses" => :read, "contents" => :read })

    expected = { "statuses" => :read, "contents" => :read, "metadata" => :read }
    assert_equal expected, @integration.reload.default_permissions
    assert_equal 3, @integration.versions.count
  end

  test "removes old permissions" do
    @integration.update(default_permissions: { "metadata" => :read, "statuses" => :read })
    @integration.update(default_permissions: { "metadata" => :read, "contents" => :read })

    expected = { "metadata" => :read, "contents" => :read }
    @integration.reload
    assert_equal expected, @integration.default_permissions
  end

  test "updates permissions" do
    @integration.update(default_permissions: { "metadata" => :read, "statuses" => :read })

    expected = { "metadata" => :read, "statuses" => :read }
    assert_equal expected, @integration.reload.default_permissions

    @integration.update(default_permissions: { "metadata" => :read, "statuses" => :write })
    @integration.reload

    expected = { "metadata" => :read, "statuses" => :write }
    assert_equal expected, @integration.default_permissions
  end

  test "does not add metadata permissions when non-Repository resources are passed as defaults" do
    owner = create(:organization, login: "owning-org")
    integration = create(:integration, owner: owner, default_permissions: { "members" => :read })

    assert_includes integration.default_permissions.keys, "members"
    refute_includes integration.default_permissions.keys, "metadata"
  end

  test "adds metadata permissions when passed as defaults" do
    owner = create(:organization, login: "owning-org")
    integration = create(:integration, owner: owner, default_permissions: { "issues" => :read, "metadata" => :read })

    assert_equal %w[issues metadata], integration.default_permissions.keys
  end

  test "adds metadata permissions when passed as the only default" do
    owner = create(:organization, login: "owning-org")
    integration = create(:integration, owner: owner, default_permissions: { "metadata" => :read })

    assert_equal ["metadata"], integration.default_permissions.keys
  end

  test "adds metadata permissions when at least one Repository resource is passed as a default" do
    owner = create(:organization, login: "owning-org")
    integration = create(:integration, owner: owner, default_permissions: { "contents" => :read })

    assert_includes integration.default_permissions.keys, "contents"
    assert_includes integration.default_permissions.keys, "metadata"
  end

  test "is invalid when invalid permissions actions are passed" do
    integration = build(
      :integration,
      default_permissions: { "metadata" => :read, "emails" => "monalisa@github.com" },
    )

    refute_predicate integration, :valid?
    assert_predicate integration.errors[:permission], :any?, "integration requires valid permission actions"

    expected_error = ["'emails' has an invalid action: 'monalisa@github.com'."]
    assert_equal expected_error, integration.errors[:permission]
  end

  context "templated callback_url" do
    test "url can be a templated URL if app has Proxima sync enabled" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })

      url = "https://{hostname}/callback"
      app.application_callback_urls.create(url: url)

      assert_predicate app, :valid?
    end

    test "url cannot be a templated URL if app does not have Proxima sync enabled" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: false }, options: { owner: @user })

      url = "https://{hostname}/callback"
      app.application_callback_urls.create(url: url)

      refute_predicate app, :valid?
    end

    test "#callback_url returns interpolated url" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })

      url = "https://{hostname}/callback"
      app.application_callback_urls.create(url: url)

      assert_equal "https://#{GitHub::host_name_with_tenant}/callback", app.callback_url
    end

    test "#raw_callback_url returns non-interpolated url" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })

      url = "https://{hostname}/callback"
      app.application_callback_urls.create(url: url)

      assert_equal url, app.raw_callback_url
    end
  end

  context "#callback_url_direct_match?" do
    test "returns false if not direct match" do
      integration = create(:integration, application_callback_urls_attributes: [{ url: "https://example.com/auth/callback" }])
      refute integration.callback_url_direct_match?("https://www.foobar.com")
    end

    test "returns true if direct match" do
      integration = create(:integration, application_callback_urls_attributes: [{ url: "https://example.com/auth/callback" }])
      assert integration.callback_url_direct_match?("https://example.com/auth/callback")
    end

    test "handles templated urls" do
      integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })

      url = "https://{hostname}/callback"
      application_callback_url = integration.application_callback_urls.create(url: url)

      assert integration.callback_url_direct_match?("#{GitHub.url}/callback")
    end
  end

  test "#canonical_avatar_url is nil when not in Proxima", skip_in_multitenant_mode: true do
    refute ProximaAppSynchronization.synchronized?(@integration)
    refute @integration.canonical_avatar_url
  end

  context "#default_events" do
    test "accepts events" do
      @integration.update(
        default_events: %w(issues),
        default_permissions: { "issues" => :read },
      )
      assert @integration.valid?
    end

    test "adds new events" do
      @integration.update(
        default_events: %w(issues),
        default_permissions: { "issues" => :read },
      )
      @integration.update(
        default_events: %w(issues pull_request),
        default_permissions: { "issues" => :read, "pull_requests" => :read },
      )

      assert_same_elements %w(issues pull_request), @integration.reload.default_events
    end

    test "removes old events" do
      @integration.update(
        default_events: %w(issues),
        default_permissions: { "issues" => :read, "pull_requests" => :read },
      )

      @integration.update(
        default_events: %w(pull_request),
        default_permissions: { "issues" => :read, "pull_requests" => :read },
      )

      assert_same_elements %w(pull_request), @integration.reload.default_events
      assert_equal 3, @integration.versions.count
    end

    test "raises an error when trying to directly mutate events" do
      @integration.default_events = %w(issues)

      assert_raises FrozenError do
        @integration.default_events << "pull_request"
      end
    end

    test "persists the events collection on save" do
      @integration.update(
        default_events: %w(issues pull_request),
        default_permissions: { "issues" => :read, "pull_requests" => :read },
      )
      @integration.reload

      @integration.update(
        default_events: %w(issues),
        default_permissions: { "issues" => :read, "pull_requests" => :read },
      )

      assert_equal %w(issues), @integration.reload.default_events

      @integration.save!

      assert_equal 1, @integration.default_event_records.count
    end
  end

  test "accesses owner" do
    assert_equal @user, @integration.reload.owner
  end

  context "#generate_key" do
    test "records who requested the key" do
      key = @integration.generate_key(creator: @user)
      assert_equal @user, key.creator
    end

    test "generates a new key each time, keeping keys" do
      key1 = @integration.generate_key(creator: @user)
      assert_includes @integration.public_keys.reload, key1

      key2 = @integration.generate_key(creator: @user)
      assert_includes @integration.public_keys.reload, key2
      refute_equal key1.id, key2.id

      assert IntegrationKey.exists?(key1.id)
    end
  end

  context "#slug" do
    test "returns the bot's slug" do
      assert_equal @integration.bot.slug, @integration.slug
    end
  end

  context "#to_param" do
    test "uses the integration's slug" do
      assert_equal @integration.slug, @integration.to_param
    end
  end

  context "#can_delete?" do
    test "returns false when marketplace listing has subscribers and ff is enabled" do
      listing = create(:marketplace_listing, listable: @integration)
      plan = create(:marketplace_listing_plan, :published, listing: listing)
      create(:billing_subscription_item, subscribable: plan)
      GitHub.flipper[:marketplace_allow_deleting_apps_with_no_active_subscriptions].enable

      refute @integration.can_delete?
    end

    test "returns true when marketplace listing has subscribers and ff is disabled" do
      listing = create(:marketplace_listing, listable: @integration)
      plan = create(:marketplace_listing_plan, :published, listing: listing)
      GitHub.flipper[:marketplace_allow_deleting_apps_with_no_active_subscriptions].disable

      assert @integration.can_delete?
    end

    test "returns true when marketplace listing has no subscribers and ff is enabled" do
      listing = create(:marketplace_listing, listable: @integration)
      plan = create(:marketplace_listing_plan, :published, listing: listing)
      GitHub.flipper[:marketplace_allow_deleting_apps_with_no_active_subscriptions].enable

      assert @integration.can_delete?
    end

    test "returns true when marketplace listing has no active subscriptions and ff is enabled" do
      listing = create(:marketplace_listing, listable: @integration)
      plan = create(:marketplace_listing_plan, :published, listing: listing)
      GitHub.flipper[:marketplace_allow_deleting_apps_with_no_active_subscriptions].enable

      assert @integration.can_delete?
    end

    test "returns true when marketplace listing has no subscribers" do
      listing = create(:marketplace_listing, listable: @integration)
      create(:marketplace_listing_plan, :published, listing: listing)

      assert @integration.can_delete?
    end

    test "returns true when integration has no marketplace listing" do
      refute @integration.marketplace_listing

      assert @integration.can_delete?
    end
  end

  context "#public_app_path" do
    test "returns a path where the app is showed", feature_disabled: :owner_scoped_github_apps do
      app = create(:integration, name: "Test App", owner: create(:user, name: "test-username"))
      prefix = GitHub.enterprise? ? "/github-apps" : "/apps"

      assert_equal "#{prefix}/test-app", app.public_app_path
    end

    test "returns empty without an slug", feature_disabled: :owner_scoped_github_apps do
      app = build(:integration, name: "Test App", owner: create(:user, name: "test-username"), slug: "")
      assert_equal "", app.public_app_path
    end

    context "with owner scoping enabled", feature_enabled: :owner_scoped_github_apps do
      test "the path includes the owner slug" do
        app = create(:integration, name: "Test App", owner: create(:user, name: "test-username"))
        prefix = GitHub.enterprise? ? "/github-apps" : "/apps"

        assert_equal "#{prefix}/test-username/test-app", app.public_app_path
      end

      test "the path includes the business slug when owned by a business" do
        app = create(:enterprise_owned_integration, name: "Test App", owner: create(:business, name: "The Biz"))
        prefix = GitHub.enterprise? ? "/github-apps" : "/apps"

        assert_equal "#{prefix}/businesses/the-biz/test-app", app.public_app_path
      end

      if GitHub.multi_tenant_enterprise?
        test "the path includes references third-party for a synced app" do
          app = create(:synchronized_integration, name: "Test App")
          prefix = GitHub.enterprise? ? "/github-apps" : "/apps"

          assert_equal "#{prefix}/external-app/test-app", app.public_app_path
        end

        test "does not raise when the integration has no slug" do
          app = build(:synchronized_integration, name: "Test App", slug: "")

          assert_nothing_raised do
            assert_equal "", app.public_app_path
          end
        end
      end
    end
  end

  context "#async_public_app_path" do
    prefix = GitHub.enterprise? ? "/github-apps" : "/apps"

    test "returns a path where the app is showed", feature_disabled: :owner_scoped_github_apps do
      app = create(:integration, name: "Test App", owner: create(:user, name: "test-username"))

      app_path = app.async_public_app_path

      assert_kind_of Promise, app_path
      assert_equal "#{prefix}/test-app", app_path.sync
    end

    test "returns empty without an slug", feature_disabled: :owner_scoped_github_apps do
      app = build(:integration, name: "Test App", owner: create(:user, name: "test-username"), slug: "")

      app_path = app.async_public_app_path

      assert_kind_of Promise, app_path
      assert_equal "", app_path.sync
    end

    context "with owner scoping enabled", feature_enabled: :owner_scoped_github_apps do
      test "the path includes the owner slug" do
        app = create(:integration, name: "Test App", owner: create(:user, name: "test-username"))

        app_path = app.async_public_app_path

        assert_kind_of Promise, app_path
        assert_equal "#{prefix}/test-username/test-app", app_path.sync
      end

      test "the path includes the business slug when owned by a business" do
        app = create(:integration, name: "Test App", owner: create(:business, name: "The Biz"))

        app_path = app.async_public_app_path

        assert_kind_of Promise, app_path
        assert_equal "#{prefix}/businesses/the-biz/test-app", app_path.sync
      end

      if GitHub.multi_tenant_enterprise?
        test "the path includes references third-party for a synced app" do
          app = create(:synchronized_integration, name: "Test App")

          app_path = app.async_public_app_path

          assert_kind_of Promise, app_path
          assert_equal "#{prefix}/external-app/test-app", app_path.sync
        end

        test "does not raise when the integration has no slug" do
          app = build(:synchronized_integration, name: "Test App", slug: "")

          assert_nothing_raised do
            app_path = app.async_public_app_path

            assert_kind_of Promise, app_path
            assert_equal "", app_path.sync
          end
        end
      end
    end
  end

  context "#can_transfer_ownership?" do
    test "returns true when integration is public" do
      assert @integration.public_visibility?
      assert @integration.can_transfer_ownership?
    end

    test "returns true when integration is private but there is no installation" do
      @integration.make_private

      assert @integration.private_visibility?
      assert @integration.can_transfer_ownership?
    end

    test "returns false when integration is private and there is an installation", feature_enabled: :block_private_installed_app_ownership_transfer do
      @integration.make_private
      @integration.install_on(@integration.owner, repositories: [], installer: @user, entry_point: :test_case)

      assert @integration.private_visibility?
      refute @integration.can_transfer_ownership?
    end

    test "returns true when integration is private and there is an installation and flag is not enabled", feature_disabled: :block_private_installed_app_ownership_transfer do
      @integration.make_private
      @integration.install_on(@integration.owner, repositories: [], installer: @user, entry_point: :test_case)

      assert @integration.private_visibility?
      assert @integration.can_transfer_ownership?
    end
  end

  context "#transfer_ownership_to" do
    test "transfers ownership" do
      @org = create :organization, login: "target-org", admin: @user
      @integration.transfer_ownership_to(@org, requester: @admin, responder: @admin, entry_point: :test_case)
      assert_equal @org, @integration.reload.owner
    end

    test "transfers ownership with marketplace listing" do
      integration = create(:integration)
      previous_owner = integration.owner

      category1 = create(:marketplace_category)
      category2 = create(:marketplace_category)
      language = create(:language_name)
      listing = create(
        :marketplace_listing,
        listable:              integration,
        primary_category_id:   category1.id,
        secondary_category_id: category2.id,
        categories:            [category1, category2],
        languages:             [language],
      )

      org = create :organization, login: "target-org", admin: @user
      result = integration.transfer_ownership_to(org, requester: @admin, responder: @admin, entry_point: :test_case)
      refute_equal previous_owner, integration.reload.owner
      assert_equal org, integration.owner
      assert_equal org, listing.listable.owner
    end

    test "deletes pending transfer" do
      @org = create :organization, login: "target-org", admin: @user
      xfer = IntegrationTransfer.start(
        requester: @user,
        integration: @integration,
        target: @org,
      )
      assert xfer

      @integration.transfer_ownership_to(@org, requester: @user, responder: @user, entry_point: :test_case)
      assert_equal @org, @integration.reload.owner
      refute IntegrationTransfer.where(id: xfer.id).exists?
    end

    test "regenerates hook associated to integration" do
      @org = create :organization, login: "target-org", admin: @user
      IntegrationTransfer.start(
        requester: @user,
        integration: @integration,
        target: @org,
      )

      hook_id = @integration.hook.id

      @integration.transfer_ownership_to(@org, requester: @user, responder: @user, entry_point: :test_case)
      @integration.reload
      refute_equal hook_id, @integration.hook.id
    end

    test "regenerated hook is configured with appropriate config and events" do
      @org = create :organization, login: "target-org", admin: @user
      IntegrationTransfer.start(
        requester: @user,
        integration: @integration,
        target: @org,
      )
      @integration.hook.add_events("repository")

      config = @integration.hook.config
      events = @integration.hook.events
      refute_empty events
      refute_empty config

      @integration.transfer_ownership_to(@org, requester: @user, responder: @user, entry_point: :test_case)
      @integration.reload

      assert_equal config["content_type"], @integration.hook.config["content_type"]
      assert_equal config["url"], @integration.hook.config["url"]
      assert_equal events, @integration.hook.events
    end

    test "removes App management permissions" do
      org = create(:organization, login: "originating-org")
      manager = create(:user, login: "our-app-manager")
      other_manager = create(:user, login: "other-app-manager")
      org.add_member(manager)
      org.add_member(other_manager)

      integration = create(:integration, owner: org)

      target_org = create(:organization, login: "target-org")

      [manager, other_manager].each do |actor|
        assert_predicate ::Permissions::Granter.grant(
          action: :manage_app,
          actor_id: actor.id,
          subject_id: integration.id,
          entry_point: :test_case
        ), :success?
      end

      integration.transfer_ownership_to(target_org, requester: manager, responder: target_org.admins.first, entry_point: :test_case)

      permissions = [manager, other_manager].map do |actor|
        [
          actor,
          ::Permissions::Enforcer.authorize(
            action: :manage_app,
            actor: actor,
            subject: integration,
          ).allow?,
        ]
      end

      assert_equal [[manager, false], [other_manager, false]], permissions
    end
  end

  context "#transfer_ownership_to with EMUs apps", skip_enterprise: true, feature_enabled: :block_emu_transfers_to_non_emu_target do
    test "can't transfer ownership to a regular user" do
      GitHub.flipper[:integration_installable_on_with_emus_check].enable
      emu = create(:emu)
      emu_integration = create(:integration, owner: emu)

      transfer = emu_integration.transfer_ownership_to(@user, requester: emu, responder: emu, entry_point: :test_case)

      refute transfer
      assert_equal emu, emu_integration.reload.owner
    end

    test "can't transfer ownership to a regular organization" do
      GitHub.flipper[:integration_installable_on_with_emus_check].enable
      emu = create(:emu)
      emu_integration = create(:integration, owner: emu)

      transfer = emu_integration.transfer_ownership_to(create(:organization), requester: emu, responder: emu, entry_point: :test_case)

      refute transfer
      assert_equal emu, emu_integration.reload.owner
    end

    test "can't transfer ownership to an EMU from another enterprise" do
      GitHub.flipper[:integration_installable_on_with_emus_check].enable
      emu = create(:emu)
      emu_integration = create(:integration, owner: emu)
      emu_another_enterprise = create(:emu)

      transfer = emu_integration.transfer_ownership_to(emu_another_enterprise, requester: emu, responder: emu, entry_point: :test_case)

      refute transfer
      assert_equal emu, emu_integration.reload.owner
    end

    test "can transfer ownership to a another EMU for the same Enterprise" do
      GitHub.flipper[:integration_installable_on_with_emus_check].enable
      emu = create(:emu)
      another_emu_same_enterprise = create(:emu, business: emu.enterprise_managed_business)
      emu_integration = create(:integration, owner: emu)

      transfer = emu_integration.transfer_ownership_to(another_emu_same_enterprise, requester: emu, responder: emu, entry_point: :test_case)

      assert transfer
      assert_equal another_emu_same_enterprise, emu_integration.reload.owner
    end

    test "can't transfer ownership to an org from another enterprise" do
      GitHub.flipper[:integration_installable_on_with_emus_check].enable
      emu = create(:emu)
      enterprise_org = create(:organization, business: emu.enterprise_managed_business)
      emu_integration = create(:integration, owner: emu)

      transfer = emu_integration.transfer_ownership_to(enterprise_org, requester: emu, responder: emu, entry_point: :test_case)

      assert transfer
      assert_equal enterprise_org, emu_integration.reload.owner
    end

    test "can transfer ownership to an org on same enterprise" do
      GitHub.flipper[:integration_installable_on_with_emus_check].enable
      emu = create(:emu)
      another_enterprise_org = create(:organization, business: emu.enterprise_managed_business)
      emu_integration = create(:integration, owner: emu)

      transfer = emu_integration.transfer_ownership_to(another_enterprise_org, requester: emu, responder: emu, entry_point: :test_case)

      assert transfer
      assert_equal another_enterprise_org, emu_integration.reload.owner
    end
  end

  context "#body" do
    test "returns the Integration description" do
      assert_equal @integration.description, @integration.body
    end
  end

  context "#abuse_limits_multiplier" do
    test "returns increased multiplier for github actions" do
      launch_app = create(:launch_integration)
      assert_equal 4, launch_app.abuse_limits_multiplier
    end

    test "returns increased multiplier for dependabot" do
      dependabot_app = create(:dependabot_integration)
      assert_equal 4, dependabot_app.abuse_limits_multiplier
    end

    test "returns 1 as multiplier for untrusted github apps" do
      assert_equal 1, @integration.abuse_limits_multiplier
    end

    test "it can be decreased by feature flags" do
      launch_app = create(:launch_integration)
      other_app = create_privileged_app_with_capabilities(
        capabilities: { abuse_limit_multiplier: true },
      )

      assert_equal 4, launch_app.abuse_limits_multiplier, "It defaults to 4"
      GitHub.flipper[:decrease_abuse_limits_multiplier].enable(launch_app)

      assert_equal 2, launch_app.abuse_limits_multiplier, "it can be cut in half"
      GitHub.flipper[:disable_abuse_limits_multiplier].enable(launch_app)
      assert_equal 1, launch_app.abuse_limits_multiplier, "it can be turned off entirely"

      assert_equal 4, other_app.abuse_limits_multiplier, "other apps are unaffected"

      GitHub.flipper[:decrease_abuse_limits_multiplier].disable(launch_app)
      assert_equal 1, launch_app.abuse_limits_multiplier, "disable_... flag works without decrease_... flag"
      GitHub.flipper[:disable_abuse_limits_multiplier].disable(launch_app)
      assert_equal 4, launch_app.abuse_limits_multiplier, "flags can be properly turned off"
    end

    test "it can be increased by feature flags" do
      launch_app = create(:launch_integration)
      other_app = create_privileged_app_with_capabilities(
        capabilities: { abuse_limit_multiplier: true },
      )

      assert_equal 4, launch_app.abuse_limits_multiplier, "It defaults to 4"

      GitHub.flipper[:increase_abuse_limits_multiplier].enable(launch_app)
      assert_equal 6, launch_app.abuse_limits_multiplier, "it can be increased"

      GitHub.flipper[:increase_abuse_limits_multiplier].disable(launch_app)
      GitHub.flipper[:increase_abuse_limits_multiplier_high].enable(launch_app)
      assert_equal 7.5, launch_app.abuse_limits_multiplier, "it can be increased to the highest multiplier"

      assert_equal 4, other_app.abuse_limits_multiplier, "other apps are unaffected"
    end
  end

  context "#can_set_loopback_webhook?" do
    test "returns true for github actions" do
      launch_app = create(:launch_integration)
      assert launch_app.can_set_loopback_webhook?
    end

    test "returns false for untrusted github apps" do
      refute @integration.can_set_loopback_webhook?
    end
  end

  context "#github_owned?" do
    test "returns false if not owned by trusted_oauth_apps_owner" do
      refute_equal GitHub.trusted_oauth_apps_owner, @integration.owner
      refute_predicate @integration, :github_owned?
    end

    test "returns true if owned by trusted_oauth_apps_owner" do
      github_owned_integration = create :integration, :with_active_hook, owner: @github

      assert_equal github_owned_integration.owner, GitHub.trusted_oauth_apps_owner
      assert_predicate github_owned_integration, :github_owned?
    end
  end

  context "#enterprise_owned?" do
    test "returns false if not owned by enterprise" do
      integration = create(:integration, owner: create(:organization))

      refute_predicate integration, :enterprise_owned?
    end

    test "returns true if owned by enterprise" do
      integration = create(:enterprise_owned_integration, owner: create(:business))

      assert_predicate integration, :enterprise_owned?
    end
  end

  context "#connect_app?" do
    test "returns false if not associated with an enterprise installation" do
      assert_nil EnterpriseInstallation.for_github_app(@integration)
      refute_predicate @integration, :connect_app?
    end

    test "returns true if associated with an enterprise installation" do
      refute_nil EnterpriseInstallation.for_github_app(@connect_integration)
      assert_predicate @connect_integration, :connect_app?
    end
  end

  context "#strict_callback_url_validation?" do
    test "returns true if there is more than one callback url" do
      integration = create(:integration, application_callback_urls_attributes: [
        { url: "https://example.com/callback" },
        { url: "https://admin.example.com/auth/github/callback" }
      ])

      assert_predicate integration, :strict_callback_url_validation?
    end

    test "returns false if there is one callback url" do
      integration = create(:integration, application_callback_urls_attributes: [{ url: "https://example.com/auth/callback" }])

      assert_equal 1, integration.application_callback_urls.count
      refute_predicate @integration, :strict_callback_url_validation?
    end

    test "returns false if there are no callback urls" do
      assert_empty @integration.application_callback_urls.map(&:url)
      refute_predicate @integration, :strict_callback_url_validation?
    end
  end

  context "#repository_installation_required?" do
    test "returns false if the app does not have any permissions" do
      integration = create(:integration)

      assert_empty integration.default_permissions
      refute integration.repository_installation_required?(@user), "expected #{@user} to not require repositories for its installation"
    end

    test "returns false if the app does not have any repository permissions" do
      integration = create(:integration, default_permissions: { "members" => :read })
      refute integration.repository_installation_required?(@user), "expected #{@user} to not require repositories for its installation"
    end

    test "returns false if the app has repo permissions, but they aren't relevant to the target" do
      business    = create(:business)
      integration = create(:integration, default_permissions: { "metadata" => :read })

      refute integration.repository_installation_required?(business), "expected #{business} to not require repositories for its installation"
    end

    test "returns true if the app has repo permissions, and they are relevant to the target" do
      integration = create(:integration, default_permissions: { "metadata" => :read })
      assert integration.repository_installation_required?(@user), "expected #{@user} to require repositories for its installation"
    end
  end

  context "instrumentation" do
    test "creation" do
      events = subscribe "integration.create"

      integration = create :integration, :with_instrumentation, name: "Hubot: The second coming"

      expected_payload = {
        integration: integration.name,
        app: integration.name,
        integration_id: integration.id,
        app_id: integration.id,
        name: integration.name,
        slug: integration.slug,
        org: integration.owner.to_s,
        org_id: integration.owner.id,
      }

      assert event = events.pop, "expected an instrument creation event"

      assert_equal "integration.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "deletion" do
      events = subscribe "integration.destroy"

      integration = create :integration, name: "Hubot: The second coming"

      expected_payload = {
        integration: integration.name,
        app: integration.name,
        integration_id: integration.id,
        app_id: integration.id,
        name: integration.name,
        slug: integration.slug,
        org: integration.owner.to_s,
        org_id: integration.owner.id,
      }

      integration.destroy

      assert event = events.pop, "expected an instrument deletion event"
      assert_equal "integration.destroy", event.name
      assert_equal expected_payload, event.payload
    end

    test "suspension" do
      integration = create :integration, name: "Bad App"

      events = subscribe "integration.suspend"
      expected_payload = {
        integration: integration.name,
        app: integration.name,
        integration_id: integration.id,
        app_id: integration.id,
        name: integration.name,
        slug: integration.slug,
        org: integration.owner.to_s,
        org_id: integration.owner.id,
        suspended_reason: "bad behavior",
      }

      integration.suspend(actor: create(:staff_admin_user), reason: "bad behavior")

      assert event = events.pop, "expected an instrument suspension event"
      assert_equal "integration.suspend", event.name
      assert_equal expected_payload, event.payload
    end

    test "unsuspension" do
      integration = create :integration, name: "Innocent App"
      integration.suspend(actor: create(:staff_admin_user), reason: "bad behavior")

      events = subscribe "integration.unsuspend"
      expected_payload = {
        integration: integration.name,
        app: integration.name,
        integration_id: integration.id,
        app_id: integration.id,
        name: integration.name,
        slug: integration.slug,
        org: integration.owner.to_s,
        org_id: integration.owner.id
      }

      integration.unsuspend(actor: create(:staff_admin_user))

      assert event = events.pop, "expected an instrument unsuspension event"
      assert_equal "integration.unsuspend", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "#can_send_callback_requests?" do
    test "returns false if there is no callback_url" do
      integration = create(:integration)
      assert_predicate integration.application_callback_urls, :none?

      refute integration.can_send_callback_requests?
    end

    test "returns true if there is a callback_url" do
      integration = create(:integration, application_callback_urls_attributes: [{ url: "http://example.com/callback" }])
      assert_predicate integration, :can_send_callback_requests?
    end
  end

  context "#access_for_code" do
    test "cannot redeem missing code" do
      assert_nil @integration.access_for_code("monkey")
    end

    test "cannot redeem zero code" do
      assert_nil @integration.access_for_code(0)
    end

    test "cannot redeem expired code" do
      Timecop.freeze do
        access = @integration.grant(@user, entry_point: :test_case)
        expired_time = (OauthAccess::CODE_EXPIRY + 1.minute).from_now
        Timecop.freeze(expired_time) do
          assert_nil @integration.access_for_code(access.code)
        end
      end
    end

    test "can redeem non-expired code" do
      Timecop.freeze do
        access = @integration.grant(@user, entry_point: :test_case)
        non_expired_time = (OauthAccess::CODE_EXPIRY - 1.minute).from_now
        Timecop.freeze(non_expired_time) do
          assert_equal access, @integration.access_for_code(access.code)
        end
      end
    end
  end

  #############################################################
  # Looking for #grant and its other various interpretations? #
  # We've moved it test/models/oauth_access/provider_test.rb  #
  #############################################################

  context "public scope" do
    test "includes public integration" do
      integration = create(:integration, visibility: :public_visibility)

      assert_includes Integration.public, integration
    end

    test "excludes private integration" do
      integration = create(:integration, visibility: :private_visibility)

      refute_includes Integration.public, integration
    end
  end

  context "adminable_by scope" do
    test "includes integration owned by given user" do
      assert_includes Integration.adminable_by(@user), @integration
    end

    test "includes integration owned by organization the given user admins" do
      org = create(:organization, admin: @user)
      integration = create(:integration, owner: org)

      assert_includes Integration.adminable_by(@user), integration
    end

    test "excludes integration unrelated to given user" do
      refute_includes Integration.adminable_by(create(:user)), @integration
    end
  end

  context "not_in_marketplace scope" do
    test "includes integration without a Marketplace listing" do
      assert_includes Integration.not_in_marketplace, @integration
    end

    test "excludes integration that has a Marketplace listing" do
      create(:marketplace_listing, listable: @integration)

      refute_includes Integration.not_in_marketplace, @integration
    end
  end

  context "not_for_github_connect scope" do
    test "excludes integrations linked to an EnterpriseInstallation" do
      refute_includes Integration.not_for_github_connect, @connect_integration
    end

    test "includes integrations not linked to an EnterpriseInstallation" do
      assert_includes Integration.not_for_github_connect, @integration, @other_integration
    end
  end

  test ".name_or_slug_like scope" do
    other_integration = create(:integration, name: "other nice beta")
    integration = create(:integration, name: "very nice beta")

    assert_equal [integration], Integration.name_or_slug_like("very nice beta")
    assert_equal [integration], Integration.name_or_slug_like("very-nice-beta")
    assert_equal [integration], Integration.name_or_slug_like("very-nice")
    assert_same_elements [other_integration, integration], Integration.name_or_slug_like("nice beta")
    assert_equal [], Integration.name_or_slug_like("not nice beta")
  end

  context "versions" do
    test "has a version on creation" do
      integration = create(:integration)
      assert_predicate integration.latest_version, :present?
      assert_equal 1, integration.latest_version.number
    end

    test "has single_file_paths if set on the integration" do
      integration_with_single_file_paths = create(:integration,
        default_permissions: { "single_file" => :read },
        single_file_paths: [".travis.yml"],
      )

      version = integration_with_single_file_paths.latest_version

      assert_equal %w(.travis.yml), version.single_file_paths
    end

    test "latest version is deemed by the number" do
      older_version  = create(:integration_version, integration: @integration)
      latest_version = create(:integration_version, integration: @integration)

      older_version.update(updated_at: Time.zone.now + 5.minutes)

      assert_equal latest_version, @integration.latest_version
      assert_operator latest_version.number, :>, older_version.number
    end

    test "has many versions" do
      version2       = create(:integration_version, integration: @integration)
      other_version1 = create(:integration_version, integration: @other_integration)

      assert versions = @integration.versions
      assert_equal 2, versions.count

      assert_includes versions, version2
      refute_includes versions, other_version1
    end

    test "#with_latest_version scope loads the latest_version association" do
      create(:integration_version, integration: @integration)

      integration = Integration.with_latest_version.first!
      assert_predicate integration.association(:latest_version), :loaded?
    end

    test "versions are destroyed on integration deletion" do
      integration_id = @integration.id
      assert IntegrationVersion.where(integration_id: integration_id).any?, "expected the integration to have versions"

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @integration.destroy }
      assert IntegrationVersion.where(integration_id: integration_id).none?, "expected all of the versions to be deleted"
    end
  end

  context "pending installation requests" do
    test "are destroyed on integration deletion" do
      org = create(:organization)
      owner = org.admins.first
      request = IntegrationInstallationRequest.create!(
        requester: owner,
        integration: @integration,
        target: org,
      )
      refute_equal 0, IntegrationInstallationRequest.where(integration_id: @integration.id).count

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @integration.destroy }
      assert_equal 0, IntegrationInstallationRequest.where(integration_id: @integration.id).count
    end
  end

  test ".created_by_count" do
    user = create(:user)
    assert_equal 0, Integration.created_by_count(user)
    2.times { create(:integration, owner: user) }
    assert_equal 2, Integration.created_by_count(user)
  end

  context ".from_owner_and_slug!" do
    test "raises RecordNotFound when the integration does not exist" do
      irrelevant = create(:user)

      assert_raises ActiveRecord::RecordNotFound do
        Integration.from_owner_and_slug!(viewer: irrelevant, slug: "app-that-does-not-exist")
      end
    end

    test "returns the integration when only the slug is passed if the integration has an alias when the feature is disabled" do
      GitHub.flipper[:owner_scoped_github_apps].disable
      integration = create(:integration)
      refute_nil integration.alias

      assert_equal integration, Integration.from_owner_and_slug!(viewer: integration.owner, slug: integration.slug)
    end

    test "returns the integration when only the slug is passed if the integration has an alias when the feature is enabled" do
      GitHub.flipper[:owner_scoped_github_apps].disable # IntegrationAlias records are only created when the feature is disabled
      integration = create(:integration)
      refute_nil integration.alias

      GitHub.flipper[:owner_scoped_github_apps].enable

      assert_equal integration, Integration.from_owner_and_slug!(viewer: integration.owner, slug: integration.slug)
    end

    test "returns the correct integration when multiple apps have previously been the canonical owner of a slug" do
      GitHub.flipper[:owner_scoped_github_apps].disable # Apps are globally unique by slug only at this point

      irrelevant = create(:user)
      integration_one = create(:integration, slug: "canonical-app")
      integration_two = create(:integration)

      integration_one.update(name: "Non Canonical App")
      assert_equal "non-canonical-app", T.must(IntegrationAlias.find_by(integration_id: integration_one.id)).slug

      integration_two.update(name: "Canonical App")
      assert_equal "canonical-app", T.must(IntegrationAlias.find_by(integration_id: integration_two.id)).slug

      GitHub.flipper[:owner_scoped_github_apps].enable # Apps are now unique by owner _and_ slug

      # Aliases are now deleted when apps are updated because we're in a world
      # of unique by slug and owner, rather than just slug. If you change the
      # name of you app after this point, you lose your old canonical, globally
      # unique, slug.
      integration_one.update(name: "Canonical App")

      assert_equal integration_two, Integration.from_owner_and_slug!(viewer: irrelevant, slug: "canonical-app")
    end

    test "raises RecordNotFound for integrations that are incapable of user installation" do
      GitHub.flipper[:owner_scoped_github_apps].disable # IntegrationAlias records are only created when the feature is disabled

      irrelevant = create(:user)
      non_user_installable = create_privileged_app_with_capabilities(
        capabilities: { user_installable: false }
      )
      refute Apps::Privileged.capable?(:user_installable, app: non_user_installable)
      refute_nil non_user_installable.alias

      GitHub.flipper[:owner_scoped_github_apps].enable

      assert_raises ActiveRecord::RecordNotFound do
        Integration.from_owner_and_slug!(viewer: irrelevant, slug: non_user_installable.slug)
      end
    end

    test "returns the relevant integration when slug and user_login is passed if the feature is enabled" do
      viewer = create(:user)
      GitHub.flipper[:owner_scoped_github_apps].enable(viewer)

      integration = create(:integration)

      assert_equal integration, Integration.from_owner_and_slug!(viewer: viewer, slug: integration.slug, user_login: integration.owner.login)
    end

    test "returns the relevant integration when slug and business_slug is passed if the feature is enabled" do
      viewer = create(:user)
      GitHub.flipper[:owner_scoped_github_apps].enable(viewer)

      business = create(:business)
      integration = create(:enterprise_owned_integration, owner: business)

      assert_equal integration, Integration.from_owner_and_slug!(viewer: viewer, slug: integration.slug, business_slug: business.slug)
    end

    test "raises RecordNotFound when slug and user_login is passed if the feature is disabled" do
      viewer = create(:user)
      GitHub.flipper[:owner_scoped_github_apps].disable(viewer)

      integration = create(:integration)

      assert_raises ActiveRecord::RecordNotFound do
        Integration.from_owner_and_slug!(viewer: viewer, slug: integration.slug, user_login: integration.owner.login)
      end
    end

    test "raises RecordNotFound when slug and business_slug is passed if the feature is disabled" do
      viewer = create(:user)
      GitHub.flipper[:owner_scoped_github_apps].disable(viewer)

      business = create(:business)
      integration = create(:enterprise_owned_integration, owner: business)

      assert_raises ActiveRecord::RecordNotFound do
        Integration.from_owner_and_slug!(viewer: viewer, slug: integration.slug, business_slug: business.slug)
      end
    end
  end

  context ".find_external_app" do
    test "raises not found the app cannot be found" do
      assert_raises ActiveRecord::RecordNotFound do
        Integration.find_external_app!(slug: "no-app-here")
      end
    end

    test "raises not found when the integration is not a synchronized app" do
      assert_raises ActiveRecord::RecordNotFound do
        Integration.find_external_app!(slug: @integration.slug)
      end
    end

    test "raises when not in Proxima" do
      assert_raises ActiveRecord::RecordNotFound do
        synced = create(:github_owned_integration, name: "some-first-party-app")
        create(:proxima_app_synchronization, local_app: synced)

        assert_equal synced, Integration.find_external_app!(slug: synced.slug)
      end
    end

    if GitHub.multi_tenant_enterprise?
      test "finds first party apps" do
        first_party_app = create(:github_owned_integration, name: "some-first-party-app")
        create(:proxima_app_synchronization, local_app: first_party_app)

        assert_equal first_party_app, Integration.find_external_app!(slug: first_party_app.slug)
      end

      test "finds third party apps" do
        third_party_app = create(:integration, owner: make_proxima_third_party_apps_owner, name: "some-third-party-app")
        create(:proxima_app_synchronization, local_app: third_party_app)

        assert_equal third_party_app, Integration.find_external_app!(slug: third_party_app.slug)
      end
    end
  end

  test "#async_default_permissions returns that latest version's permissions as promise" do
    integration = create(:integration, default_permissions: { "metadata" => :read })
    create(:integration_version, integration: integration, default_permissions: { "metadata" => :read, "issues" => :write })

    integration.reload

    assert_kind_of Promise, integration.async_default_permissions
    assert_equal({ "metadata" => :read, "issues" => :write }, integration.async_default_permissions.sync)
  end

  test "#async_default_events returns that latest version's permissions as promise" do
    integration = create(:integration, default_permissions: { "metadata" => :read })
    create(:integration_version, integration: integration, default_permissions: { "metadata" => :read }, default_events: ["public"])

    integration.reload

    assert_kind_of Promise, integration.async_default_events
    assert_same_elements ["public"], integration.async_default_events.sync
  end

  test "destroys associated integration install triggers when destroyed" do
    app = create(:integration)
    trigger_1 = create(:integration_install_trigger, install_type: :file_added, integration: app)
    trigger_2 = create(:integration_install_trigger, install_type: :file_added, integration: app)

    assert_same_elements [trigger_1, trigger_2], app.integration_install_triggers

    assert_difference "IntegrationInstallTrigger.count", -2 do
      app.destroy
    end
  end

  test "queues up the Bot to be deleted in the background" do
    @integration.destroy_bot_asynchronously = true
    bot = @integration.bot

    assert_enqueued_with job: UserDeleteJob, args: [bot.id, bot.login] do
      assert @integration.destroy
    end
  end

  test "destroys a bot in the foreground by default" do
    assert_difference -> { Bot.count }, -1 do
      assert_no_enqueued_jobs only: UserDeleteJob do
        assert @integration.destroy
      end
    end
  end

  if GitHub.spamminess_check_enabled?
    context "when integration owner is spammy" do
      test "integration can be spammy" do
        spammy_owner = create(:user)
        integration = create(:integration, owner: spammy_owner)
        refute_predicate integration, :spammy?

        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
          spammy_owner.mark_as_spammy
          assert_predicate integration.reload, :spammy?
        end
      end

      test "making spammy an app owner has no impact on apps owned by a Business" do
        spammy_owner = create(:user)
        business = create(:business, id: spammy_owner.id)

        integration = create(:integration, owner: spammy_owner)
        refute_predicate integration, :spammy?

        business_integration = create(:enterprise_owned_integration, owner: business)
        refute_predicate business_integration, :spammy?

        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
          spammy_owner.mark_as_spammy

          assert_predicate integration.reload, :spammy?
          refute_predicate business_integration.reload, :spammy?
        end
      end

      test "making spammy an organization has no impact on apps owned by a Business" do
        spammy_owner = create(:organization)
        business = create(:business, id: spammy_owner.id)

        integration = create(:integration, owner: spammy_owner)
        refute_predicate integration, :spammy?

        business_integration = create(:enterprise_owned_integration, owner: business)
        refute_predicate business_integration, :spammy?

        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
          spammy_owner.mark_as_spammy

          assert_predicate integration.reload, :spammy?
          refute_predicate business_integration.reload, :spammy?
        end
      end

      test "excludes spammy apps only for other viewers" do
        user = create(:user)
        spammy_user = create(:user, spammy: true)

        _app = create(:integration, owner: user)
        spammy_app = create(:integration, owner: spammy_user, user_hidden: true)

        refute_includes Integration.filter_spam_for(nil), spammy_app
        refute_includes Integration.filter_spam_for(user), spammy_app
        assert_includes Integration.filter_spam_for(spammy_user), spammy_app
      end

      test "uses type in filtering" do
        user = create(:user)
        business = create(:business, id: user.id, spammy: true)
        business_spammy_app = create(:integration, owner: business, user_hidden: true)

        refute_includes Integration.filter_spam_for(user), business_spammy_app
      end

      test "hides spammy apps from other users" do
        user = create(:user)
        business = create(:business, id: user.id, spammy: true)
        business_spammy_app = create(:integration, owner: business, user_hidden: true)

        assert business_spammy_app.hide_from_user?(user)
      end
    end
  end

  test "#syncable_to_proxima returns only integrations with available proxima_availability" do
    syncable = create(:integration, proxima_availability: :available)
    not_syncable = create(:integration, proxima_availability: :unavailable)

    assert_equal [syncable], Integration.syncable_to_proxima
  end

  context "#syncable_to_proxima?" do
    test "is not syncable by default" do
      integration = create(:integration)

      assert_equal "unavailable", integration.proxima_availability
      refute Apps::Privileged.capable?(:proxima_first_party_sync, app: integration)
      refute integration.syncable_to_proxima?
    end

    test "is syncable when integration has proxima availability :available" do
      integration = create(:integration, proxima_availability: :available)

      assert_equal "available", integration.proxima_availability
      refute Apps::Privileged.capable?(:proxima_first_party_sync, app: integration)
      assert integration.syncable_to_proxima?
    end

    test "is syncable when integration has proxima_first_party_sync_capability" do
      integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })

      assert_equal "unavailable", integration.proxima_availability
      assert Apps::Privileged.capable?(:proxima_first_party_sync, app: integration)
      assert integration.syncable_to_proxima?
    end
  end
end

class IntegrationAsyncInstallationForTest < GitHub::TestCase
  fixtures do
    @integration  = create(:integration, default_permissions: { "contents" => :read })
    @organization = create(:organization)
    @repository   = create(:private_repository, :minimal, owner: @organization)
  end

  test "loads the installation for a repository" do
    installation = @integration.install_on(
      @organization, repositories: [@repository], installer: @organization.admins.first, entry_point: :test_case
    ).installation

    assert_equal installation, @integration.async_installation_for(@repository).sync
  end
end

class IntegrationInstallOnTest < GitHub::TestCase
  fixtures do
    @integration  = create(:integration, default_permissions: { "contents" => :read })
    @org          = create(:organization)
    @private_repo = create(:private_repository, :minimal, owner: @org)
  end

  test "returns a success for a valid installation" do
    result =
      @integration.install_on(@org, repositories: [@private_repo], installer: @org.admins.first, entry_point: :test_case)

    assert result.success?
  end

  test "creates an IntegrationInstallation on the target" do
    assert_difference "@integration.installations.count", 1 do
      result = @integration.install_on(@org, repositories: [@private_repo], installer: @org.admins.first, entry_point: :test_case)

      assert_equal @org, result.installation.target
    end
  end

  test "returns a failure for an invalid installation" do
    result =
      @integration.install_on(@org, repositories: [], installer: @org.admins.first, version: create(:integration_version), entry_point: :test_case)

    assert_predicate result, :failed?

    expected = "The requested version of permissions do not belong to this GitHub App. Please contact an Organization Owner."
    assert_equal expected, result.error
  end

  test "does not create an IntegrationInstallation for an invalid installation" do
    assert_no_difference "@integration.installations.count" do
      @integration.install_on(@org, repositories: [@private_repo], installer: @org.admins.first, version: create(:integration_version), entry_point: :test_case)
    end
  end

  test "uses a default set of permissions" do
    result = @integration.install_on(@org, repositories: [@private_repo], installer: @org.admins.first, entry_point: :test_case)

    assert_able result.installation, :read, @private_repo.resources.contents
  end

  test "uses specified version" do
    version = @integration.versions.create(default_permissions: { "contents" => :write })
    result = @integration.install_on(@org, repositories: [@private_repo], installer: @org.admins.first, version: version, entry_point: :test_case)

    assert_able result.installation, :write, @private_repo.resources.contents
    assert_equal version.id, result.installation.integration_version_id
    assert_equal version.number, result.installation.integration_version_number
  end

  test "uses a default set of event types" do
    integration = create(:integration, :with_active_hook, default_events: %w(issues), default_permissions: { "issues" => :read })
    result = integration.install_on(@org, repositories: [@private_repo], installer: @org.admins.first, entry_point: :test_case)

    assert_same_elements ["issues"], result.installation.events
  end

  test "returns success for businesses" do
    business = create(:business)
    owner    = business.owners.first

    integration = create(:integration, default_permissions: { "enterprise_administration" => :read })

    result = integration.install_on(business, repositories: [], installer: owner, entry_point: :test_case)

    assert_predicate result, :success?
  end

  test "Integration#ghost" do
    assert_equal GhostGitHubApp.instance, Integration.ghost
  end

  test "#ghost" do
    refute @integration.ghost?
  end
end

class IntegrationInstalledOnTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration, default_permissions: { "contents" => :read })
    @user = create(:user)
    @org = create(:organization)
    @user_repo = create(:repository, :minimal, owner: @user)
    @org_repo = create(:repository, :minimal, owner: @org)
  end

  test "returns true when the integration is installed on the given user account" do
    result = @integration.install_on(@user,
      repositories: [@user_repo],
      installer: @user,
      entry_point: :test_case,
    )
    assert result.success?

    assert @integration.installed_on?(@user), "Expected integration to be installed"
  end

  test "returns false when the integration is not installed on the given user account" do
    refute @integration.installed_on?(@user), "Expected integration to NOT be installed"
  end

  test "returns true when the integration is installed on the given org account" do
    result = @integration.install_on(@org,
      repositories: [@org_repo],
      installer: @org.admins.first,
      entry_point: :test_case,
    )
    assert result.success?

    assert @integration.installed_on?(@org), "Expected integration to be installed"
  end

  test "returns false when the integration is not installed on the given org account" do
    refute @integration.installed_on?(@org), "Expected integration to NOT be installed"
  end

  test "#installations_on" do
    @integration.install_on(@org,
      repositories: [@org_repo],
      installer: @org.admins.first,
      entry_point: :test_case,
    )

    assert_equal @org.id, @integration.installations_on(@org).first.target.id
    assert_equal 1, @integration.installations_on(@org).count
  end
end

class IntegrationEnabledGlobalAppTest < GitHub::TestCase
  test "returns true when the integration is installed globally and global apps are not disabled" do
    integration = create_privileged_app_with_capabilities(capabilities: { installed_globally: true })
    GitHub.flipper[:disabled_global_apps].disable(integration)

    assert integration.enabled_global_app?
  end

  test "returns false when the integration is not installed globally" do
    integration = create_privileged_app_with_capabilities(capabilities: { installed_globally: false })
    GitHub.flipper[:disabled_global_apps].disable(integration)

    refute integration.enabled_global_app?
  end

  test "returns false when global apps are not disabled" do
    integration = create_privileged_app_with_capabilities(capabilities: { installed_globally: true })
    GitHub.flipper[:disabled_global_apps].enable(integration)

    refute integration.enabled_global_app?
  end
end

class IntegrationAdminableByTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @other_user = create(:user)
    @org = create(:organization)
    @admin = @org.admins.first

    @user_integration = create(:integration, owner: @user)
    @org_integration = create(:integration, owner: @org)
  end

  test "returns true if actor is the owner" do
    assert @user_integration.adminable_by?(@user)
    refute @user_integration.adminable_by?(@other_user)
  end

  test "returns true if actor is an admin of the owning org" do
    assert @org_integration.adminable_by?(@admin)
    refute @org_integration.adminable_by?(@user)
  end
end

class IntegrationManageableByTest < GitHub::TestCase
  fixtures do
    @bot = create(:bot)
    @other_user = create(:user)
    @org = create(:organization)
    @user = create(:user)
    @org.add_member @user
    @admin = @org.admins.first
    @manager = create(:user)
    @org.add_member @manager

    @user_integration = create(:integration, owner: @user)
    @org_integration = create(:integration, owner: @org)
    ::Permissions::Granter.grant(
      action: :manage_app,
      actor_id: @manager.id,
      subject_id: @org_integration.id,
      entry_point: :test_case
    )
  end

  test "always returns false for Bot actors" do
    refute @user_integration.manageable_by?(@bot)
    refute @org_integration.manageable_by?(@bot)
  end

  test "returns true if actor owns an app" do
    assert @user_integration.manageable_by?(@user)
  end

  test "returns false if actor does not own an app" do
    refute @user_integration.manageable_by?(@other_user)
  end

  test "returns true if actor is an admin of the org that owns an app" do
    assert @org_integration.manageable_by?(@admin)
  end

  test "returns false if actor is only a member of the org that owns an app" do
    refute @org_integration.manageable_by?(@user)
  end

  test "returns true if actor is manager of app owned by an org" do
    assert @org_integration.manageable_by?(@manager)
  end
end

class IntegrationIpAllowlistManageableByTest < GitHub::TestCase
  fixtures do
    @bot = create(:bot)
    @other_user = create(:user)
    @org = create(:organization)
    @user = create(:user)
    @org.add_member @user
    @admin = @org.admins.first
    @manager = create(:user)
    @org.add_member @manager

    @user_integration = create(:integration, owner: @user)
    @org_integration = create(:integration, owner: @org)
    ::Permissions::Granter.grant(
      action: :manage_app,
      actor_id: @manager.id,
      subject_id: @org_integration.id,
      entry_point: :test_case
    )
  end

  test "always returns false for Bot actors" do
    refute @user_integration.ip_allowlist_manageable_by?(@bot)
    refute @org_integration.ip_allowlist_manageable_by?(@bot)
  end

  test "returns true if actor owns an app" do
    assert @user_integration.ip_allowlist_manageable_by?(@user)
  end

  test "returns false if actor does not own an app" do
    refute @user_integration.ip_allowlist_manageable_by?(@other_user)
  end

  test "returns true if actor is an admin of the org that owns an app" do
    assert @org_integration.ip_allowlist_manageable_by?(@admin)
  end

  test "returns false if actor is only a member of the org that owns an app" do
    refute @org_integration.ip_allowlist_manageable_by?(@user)
  end

  test "returns true if actor is manager of app owned by an org" do
    assert @org_integration.ip_allowlist_manageable_by?(@manager)
  end
end

class IntegrationReadableByTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @other_user = create(:user)
    @member = create(:user)
    @org = create(:organization)
    @admin = @org.admins.first
    @org.add_member(@member)

    @user_integration = create(:integration, owner: @user, visibility: :private_visibility)
    @org_integration = create(:integration, owner: @org, visibility: :private_visibility)

    make_trusted_oauth_apps_owner
    launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(launch_app)
    repo = create(:repository, :minimal, owner: @user)
    @launch_app_installation = make_integration_installation(integration: launch_app, repository: repo)
  end

  test "returns true if integration is public" do
    @user_integration.update_attribute :visibility, :public_visibility
    @org_integration.update_attribute :visibility, :public_visibility

    assert @user_integration.readable_by?(@user)
    assert @user_integration.readable_by?(@other_user)
    assert @user_integration.readable_by?(@member)
    assert @user_integration.readable_by?(@launch_app_installation)
    assert @user_integration.readable_by?(nil)

    assert @org_integration.readable_by?(@user)
    assert @org_integration.readable_by?(@admin)
    assert @org_integration.readable_by?(@member)
    assert @org_integration.readable_by?(@launch_app_installation)
    assert @org_integration.readable_by?(nil)
  end

  test "returns true for private org integrations if actor is an org member" do
    assert @org_integration.readable_by?(@admin)
    assert @org_integration.readable_by?(@member)
    refute @org_integration.readable_by?(@user)
    refute @org_integration.readable_by?(nil)
  end

  test "returns true for private user integrations if actor is the owning user" do
    assert @user_integration.readable_by?(@user)
    refute @user_integration.readable_by?(@other_user)
    refute @user_integration.readable_by?(nil)
  end

  test "returns false if actor is GitHub Actions" do
    refute @user_integration.readable_by?(@launch_app_installation)
    refute @org_integration.readable_by?(@launch_app_installation)
  end
end

class IntegrationInstallableByTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @other_user = create(:user)

    @member = create(:user)
    @org = create(:organization)
    @admin = @org.admins.first
    @org.add_member(@member)

    @enterprise = create(:business)
    @enterprise_org = create(:organization)
    @enterprise.add_organization(@enterprise_org)
    @enterprise_owner = @enterprise.owners.first
    @enterprise_org_admin = @enterprise_org.admins.first
    @enterprise_member = create(:user)
    @enterprise_org.add_member(@enterprise_member)

    @user_integration = create(:integration, owner: @user, visibility: :private_visibility)
    @org_integration = create(:integration, owner: @org, visibility: :private_visibility)
    @enterprise_integration = create(:enterprise_owned_integration, owner: @enterprise)
  end

  test "returns false if the user is signed out" do
    refute @user_integration.installable_by?(nil)
    refute @org_integration.installable_by?(nil)

    @user_integration.update_attribute :visibility, :public_visibility
    @org_integration.update_attribute :visibility, :public_visibility

    refute @user_integration.installable_by?(nil)
    refute @org_integration.installable_by?(nil)
  end

  test "returns true if integration is public" do
    @user_integration.update_attribute :visibility, :public_visibility
    @org_integration.update_attribute :visibility, :public_visibility

    assert @user_integration.installable_by?(@user)
    assert @user_integration.installable_by?(@other_user)

    assert @org_integration.installable_by?(@user)
    assert @org_integration.installable_by?(@admin)
    assert @org_integration.installable_by?(@member)
  end

  test "returns true for private org integrations if actor is an org admin" do
    assert @org_integration.installable_by?(@admin)
    refute @org_integration.installable_by?(@member)
    refute @org_integration.installable_by?(@user)
    refute @org_integration.installable_by?(nil)
  end

  test "returns true for private user integrations if actor is the owning user" do
    assert @user_integration.installable_by?(@user)
    refute @user_integration.installable_by?(@other_user)
    refute @user_integration.installable_by?(nil)
  end

  test "returns false if the user can admin any repositories on the target account but the app doesn't ask for repo access" do
    org_repo = create(:private_repository, :minimal, owner: @org)
    repo_admin = create(:user)
    org_repo.add_member(repo_admin, action: :admin)

    assert_empty @org_integration.default_permissions

    assert org_repo.adminable_by? repo_admin
    refute @org_integration.installable_by?(repo_admin), "expected the repo admin to not be able to install the app"
  end

  test "returns true if the user can admin any repositories on the target account" do
    integration = create(:integration, visibility: :private_visibility, owner: @org, default_permissions: { "metadata" => :read })

    org_repo = create(:private_repository, :minimal, owner: @org)
    repo_admin = create(:user)
    org_repo.add_member(repo_admin, action: :admin)

    assert org_repo.adminable_by? repo_admin
    assert integration.installable_by?(repo_admin), "expected the repo admin to be able to install the app"
  end

  test "returns false for internal enterprise integrations for Users in the enterprise" do
    GitHub.flipper[:enterprise_app_installation_management].enable
    assert @enterprise_integration.installable_by?(@enterprise_owner)
    assert @enterprise_integration.installable_by?(@enterprise_org_admin)
    refute @enterprise_integration.installable_by?(@enterprise_member)
    refute @enterprise_integration.installable_by?(@admin)
    refute @enterprise_integration.installable_by?(@user)
    refute @enterprise_integration.installable_by?(nil)
  end
end

class IntegrationInstallableOnByTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration, default_permissions: { "metadata" => :read })
  end

  test "returns a permitted result even if there are workspace repos on the target" do
    repository = create(:repository, :minimal)
    author     = repository.owner

    GitHub.context.push(actor_id: author.id)

    advisory1 = create(:repository_advisory, repository: repository, author: author)
    RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory1, author).tap(&:save!)

    advisory2 = create(:repository_advisory, repository: repository, author: author)
    RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory2, author).tap(&:save!)

    result =
      Integration.stub_const(:BATCH_SIZE, 2) do
        @integration.installable_on_by(target: author, actor: author)
      end

    assert_predicate result, :permitted?
  end

  test "permitted for organization owned integrations with enterprise resources" do
    business = create(:business)
    owner    = business.owners.first
    integration = create(:integration, default_permissions: { Business::Resources.subject_types.first => :read })

    result = integration.installable_on_by(target: business, actor: owner)

    assert_predicate result, :permitted?
  end

  test "permitted for enterprise owned integrations with enterprise resources" do
    GitHub.flipper[:enterprise_owned_app_management].enable
    enterprise = create(:business)
    owner = enterprise.owners.first
    integration = create(:enterprise_owned_integration, owner: enterprise, default_permissions: { Business::Resources.subject_types.first => :read })

    enterprise_org = create(:organization)
    enterprise.add_organization(enterprise_org)
    enterprise_org.reload

    enterprise_org_admin = enterprise_org.admins.first
    enterprise_member = create(:user)
    enterprise_org.add_member(enterprise_member)

    org_result = integration.installable_on_by(target: enterprise_org, actor: enterprise_org_admin)
    assert_predicate org_result, :permitted?

    member_result = integration.installable_on_by(target: enterprise, actor: enterprise_member)
    refute_predicate member_result, :permitted?

    owner_result = integration.installable_on_by(target: enterprise, actor: owner)
    assert_predicate owner_result, :permitted?

    org_admin_result = integration.installable_on_by(target: enterprise, actor: enterprise_org_admin)
    refute_predicate org_admin_result, :permitted?
  end

  test "not permitted for enterprise owned integrations without enterprise resources" do
    GitHub.flipper[:enterprise_owned_app_management].enable
    enterprise = create(:business)
    owner = enterprise.owners.first
    integration = create(:enterprise_owned_integration, owner: enterprise, default_permissions: { Organization::Resources.subject_types.first => :read })

    enterprise_org = create(:organization)
    enterprise.add_organization(enterprise_org)
    enterprise_org.reload

    enterprise_org_admin = enterprise_org.admins.first
    enterprise_member = create(:user)
    enterprise_org.add_member(enterprise_member)

    enterprise_owner_result = integration.installable_on_by(target: enterprise, actor: owner)
    refute_predicate enterprise_owner_result, :permitted?

    org_result = integration.installable_on_by(target: enterprise_org, actor: enterprise_org_admin)
    assert_predicate org_result, :permitted?

    member_result = integration.installable_on_by(target: enterprise, actor: enterprise_member)
    refute_predicate member_result, :permitted?
  end
end

class IntegrationHookTest < GitHub::TestCase
  test "defaults to a web hook" do
    hook = Integration.create!(
      owner: create(:user),
      name: "integration-#{SecureRandom.hex(8)}",
      url: "http://#{Faker::Internet.domain_name}",
      hook_attributes: { url: "https://#{Faker::Internet.domain_name}/github/hook" },
    ).hook

    assert_predicate hook, :webhook?
  end

  test "defaults to a JSON content type" do
    hook = Integration.create!(
      owner: create(:user),
      name: "integration-#{SecureRandom.hex(8)}",
      url: "http://#{Faker::Internet.domain_name}",
      hook_attributes: { url: "https://#{Faker::Internet.domain_name}/github/hook" },
    ).hook

    assert_equal "json", T.must(hook).content_type
  end

  test "supports building by nested attributes" do
    integration = Integration.new hook_attributes: { url: "http://example.com/hook" }
    assert_equal "http://example.com/hook", T.must(integration.hook).url
  end

  test "uses the integration's events" do
    integration = create :integration, :with_active_hook, default_events: %w(pull_request issues),
      default_permissions: { "issues" => :read, "pull_requests" => :read }

    hook = integration.hook
    assert_same_elements %w(pull_request issues), integration.default_events
    assert_same_elements %w(pull_request issues), hook.events
  end

  test "updates its events when the integration's events change" do
    integration = create :integration, :with_active_hook, default_events: %w(pull_request issues),
      default_permissions: { "issues" => :read, "pull_requests" => :read }

    hook = integration.hook
    assert_same_elements %w(pull_request issues), hook.events

    integration.update(
      default_events: %w(issues),
      default_permissions: { "issues" => :read, "pull_requests" => :read },
    )
    integration.reload

    assert_same_elements %w(issues pull_request), hook.reload.events
    assert_same_elements %w(issues), integration.default_events
    assert_same_elements %w(issues), integration.reload.latest_version.default_events
  end

  test "is active by default" do
    integration = create :integration, :with_active_hook, default_events: %w(pull_request issues),
      default_permissions: { "issues" => :read, "pull_requests" => :read }
    assert_predicate integration.hook, :active?
  end

  test "is not suspended by default" do
    integration = build(:integration)
    assert_equal false, integration.suspended?
  end

  test "does not deactivate on update without events" do
    integration = create :integration, :with_active_hook, default_events: %w(),
      default_permissions: { "issues" => :read, "pull_requests" => :read }

    assert_predicate integration.hook, :active?

    integration.update(
      default_events: %w(),
      default_permissions: { "issues" => :read, "pull_requests" => :read },
    )
    integration.reload

    assert_predicate integration.hook, :active?
  end

  test "can set to not active" do
    integration = create(:integration, :with_active_hook)

    assert_predicate integration.hook, :active?

    integration.update(hook_attributes: { active: false })
    integration.reload

    assert_predicate integration.hook, :active?
  end

  context "#subscribable_hook?" do
    test "returns false if the integration does not have a hook" do
      integration = create(:integration)
      refute_predicate integration, :subscribable_hook?
    end

    test "returns false if the hook is not active" do
      integration = create(:integration, :with_hook)
      refute_predicate integration, :subscribable_hook?
    end

    test "returns true when the hook is active" do
      integration = create(:integration, :with_active_hook)
      assert_predicate integration, :subscribable_hook?
    end
  end

  context "#active_and_subscribable?" do
    test "returns false if the integration does not have a hook" do
      integration = create(:integration)
      refute_predicate integration, :active_and_subscribable?
    end

    test "returns false if the hook is not active" do
      integration = create(:integration, :with_hook)
      refute_predicate integration, :active_and_subscribable?
    end

    test "returns false if the integration is suspended" do
      admin = create(:staff_admin_user)
      integration = create(
        :integration,
        :with_active_hook,
        state: :suspended,
        suspended_at: Time.now,
        user_suspended_by_id: admin,
        suspended_reason: "test"
      )

      refute_predicate integration, :active_and_subscribable?
    end

    test "returns true when the integration is not suspended and the hook is active" do
      integration = create(:integration, :with_active_hook)
      assert_predicate integration, :active_and_subscribable?
    end
  end

  context "#installable_on?" do
    test "returns false for enterprises when app does not request enterprise permissions" do
      GitHub.flipper[:enterprise_app_installation_management].enable
      refute create(:integration, default_permissions: { "metadata" => :read }).installable_on?(create(:business))
    end

    test "returns true for enterprises when app requests enterprise permissions" do
      assert create(:integration, default_permissions: { Business::Resources.subject_types.first => :read }).installable_on?(create(:business))
    end
  end

  test "enterprise owned apps with internal visibility are only installable within the enterprise" do
    GitHub.flipper[:enterprise_owned_app_management].enable

    enterprise = create :business
    enterprise_org = create :organization
    enterprise.add_organization(enterprise_org)
    enterprise_org.reload
    enterprise_internal_app = create(:enterprise_owned_integration, owner: enterprise)

    enterprise_owner = enterprise.owners.first
    enterprise_org_admin = enterprise_org.admins.first
    enterprise_member = create(:user)
    enterprise_org.add_member(enterprise_member)
    rando = create(:user)

    assert enterprise_internal_app.installable_on?(enterprise_org)
    refute enterprise_internal_app.installable_on?(enterprise_owner)
    refute enterprise_internal_app.installable_on?(enterprise_org_admin)
    refute enterprise_internal_app.installable_on?(enterprise_member)
    refute enterprise_internal_app.installable_on?(rando)
  end
end

class IntegrationOutdatedInstallationsTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration)
    @installation = make_integration_installation(integration: @integration, target: create(:user))
  end

  test "returns installations if a new version is available" do
    @integration.versions.build
    @integration.save!
    @integration.reload

    refute_equal @integration.latest_version, @installation.version
    assert_includes @integration.outdated_installations, @installation
  end

  test "does not return installation if not out of date" do
    refute_includes @integration.outdated_installations, @installation
  end
end

class EMUIntegrationInstallableByTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration)
    @internal_integration = create_privileged_app_with_capabilities(
      capabilities: {
        installable_on_emus: true
      }
    )

    @emu = create :emu, :owner
    @business = @emu.enterprise_managed_business
    @org_with_business = create :organization, business: @business, admin: @emu
  end

  test "returns false if target is EMU user and integration isn't internal" do
    refute @integration.installable_on?(@emu)
  end

  test "returns true if target is EMU user and integration is internal" do
    assert @internal_integration.installable_on?(@emu)
  end

  test "returns true if target is EMU org" do
    assert @integration.installable_on?(@org_with_business)
    assert @internal_integration.installable_on?(@org_with_business)
  end

  test "returns true if target is EMU business" do
    integration = create(:integration, default_permissions: { "enterprise_administration" => :read })
    internal_integration = create_privileged_app_with_capabilities(
      permissions: { "enterprise_administration" => :read },
      capabilities: {
        installable_on_emus: true
      }
    )
    assert integration.installable_on?(@business)
    assert internal_integration.installable_on?(@business)
  end

  test "returns false if integration is EMU-owned and target isn't on the enterprise" do
    GitHub.flipper[:integration_installable_on_with_emus_check].enable

    emu_owned_integration = create(
      :integration,
      name: "EMU owned integration",
      owner: @org_with_business,
      default_permissions: { "metadata" => :read },
    )

    outside_user = create(:emu, :owner)
    outside_business = outside_user.enterprise_managed_business
    outside_org = create(:enterprise_linked_organization, business: outside_business, admin: outside_user)

    refute emu_owned_integration.installable_on?(outside_org)
  end

  # This test should be removed once :integration_installable_on_with_emus_check is promoted.
  test "returns true if integration is EMU-owned and target isn't on the enterprise when ff is disabled" do
    GitHub.flipper[:integration_installable_on_with_emus_check].disable

    emu_owned_integration = create(
      :integration,
      name: "EMU owned integration",
      owner: @org_with_business,
      default_permissions: { "metadata" => :read },
    )

    outside_user = create(:emu, :owner)
    outside_business = outside_user.enterprise_managed_business
    outside_org = create(:enterprise_linked_organization, business: outside_business, admin: outside_user)

    assert emu_owned_integration.installable_on?(outside_org)
  end

  context "#agent_configured?" do
    test "with no integration agent and no fgp" do
      refute create(:integration).agent_configured?
    end

    test "with integration agent and fgp but no permissions" do
      integration = create(:integration, :with_agent)
      refute integration.agent_configured?
    end

    test "with integration agent disabled" do
      GitHub.flipper[:copilot_extendable].enable
      integration = create(:integration, :with_agent, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
      integration.integration_agent.app_type = "disabled"
      refute integration.agent_configured?
    end

    test "with integration agent and fgp and permissions" do
      GitHub.flipper[:copilot_extendable].enable
      integration = create(:integration, :with_agent, default_permissions: { Integration::CopilotDependency::COPILOT_PERMISSION => "read" })
      integration.integration_agent.app_type = "agent"
      assert integration.agent_configured?
    end
  end
end unless GitHub.single_business_environment?

class MultiTenantIntegrationModelTest < GitHub::TestCase
  fixtures do
    on_multi_tenant_enterprise do
      @integration = create(:integration)
      @user = create :emu
      @business = @user.enterprise_managed_business
    end
  end

  setup do
    on_multi_tenant_enterprise
    GitHub::CurrentTenant.set(@business)
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  context "#canonical_avatar_url" do
    test "returns nil for non-synced integrations" do
      refute ProximaAppSynchronization.synchronized?(@integration)
      refute @integration.canonical_avatar_url
    end

    test "returns the canonical dotcom url for synced integrations" do
      integration = create(:synchronized_integration)
      assert ProximaAppSynchronization.synchronized?(integration)
      assert integration.canonical_avatar_url
    end
  end

  context "#tenant_slug_for_avatar" do
    test "returns company specific entity if `enterprise_managed_business` is nil" do
      assert_equal GitHub.company_specific_entity_acronym, @integration.tenant_slug_for_avatar
    end

    test "return business slug if bot belongs to tenant" do
      @business.user_accounts.create(user_id: @integration.bot.id)
      assert_equal @business.slug, @integration.tenant_slug_for_avatar
    end
  end
end unless GitHub.single_business_environment?
