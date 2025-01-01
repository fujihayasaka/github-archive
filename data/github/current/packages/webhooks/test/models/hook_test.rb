# typed: true
# frozen_string_literal: true

require "test_helper"

class SuperStealthEvent < Hook::Event
  supports_targets Organization
  description "Secret event that only preview users can see"
  feature_flag :preview_hook_events
end

class PartiallyExposedEvent < Hook::Event
  supports_targets Repository, Organization
  description "Secret event that only preview users can see"
  feature_flag :preview_hook_events, actions: [:created]
end

class RepoTestEvent < Hook::Event
  supports_targets Repository
  description "it's a repo event"
end

class BusinessTestEvent < Hook::Event
  supports_targets Business
  description "it's a business event"
end

class HookTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper
  include UnlockedRepositoryCheckTestHelper
  include BackgroundDeletesTestHelpers

  fixtures do
    @user = create(:user)
    @random_user = create(:user)
    @org = create :business_plus_organization, admin: @user
    @business = create :business, owners: [@user], organizations: [@org]
    @repo = create :repository, owner: @user
    @org_repo = create :repository, owner: @org
    @other_repo = create(:repository)
    @oauth_app = create :oauth_application, name: "Janky"
    @oauth_access = create :oauth_access_with_token, user: @user, application: @oauth_app
    @disabled_hook = create :hook, active: false
    @repo_hook = create :hook, :web,
      active: true,
      installation_target: @repo,
      config: { "url" => "http://example.com", "secret" => "donottell" },
      events: %w(push),
      creator: @user
    @org_repo_hook = create :hook, :web,
      installation_target: @org_repo,
      config: { "url" => "http://example.com", "secret" => "donottell" },
      events: %w(push),
      creator: @user
    @org_hook = create :hook, :org,
      installation_target: @org,
      config: { "url" => "http://example.com" },
      events: %w(push),
      creator: @user
    @oauth_org_hook = create :hook, :org,
      installation_target: @org,
      config: { "url" => "http://example.com/oauth" },
      events: %w(push),
      creator: @user,
      oauth_application: @oauth_app
    @business_hook = create :hook,
      installation_target: @business,
      config: { "url" => "http://example.com" },
      events: %w(ping),
      creator: @user
  end

  setup do
    clear_memoized_unlocked_repository_check
  end

  context ":instrumentation" do
    test "triggers an event on hook.create" do
      events = subscribe "hook.create"

      hook = create :hook, :web, creator: @user, oauth_application: @oauth_app, config: { "url" => "http://example.com", "secret" => "password" }
      expected_payload = {
        hook_type: :repo,
        name: "webhook",
        webhook: true,
        config: { "url" => "http://example.com", "secret" => "********", "insecure_ssl" => "0", "content_type" => "form" },
        events: ["push"],
        active: true,
        public_repo: hook.installation_target.public?,
        creator: "Janky on behalf of #{@user}",
        oauth_application: @oauth_app.name,
        oauth_application_id: @oauth_app.id,
        hook_id: hook.id,
        repo: hook.installation_target.name_with_owner,
        repo_id: hook.installation_target_id,
        user: hook.installation_target.owner.login,
        user_id: hook.installation_target.owner_id,
      }

      assert event = events.pop, "not instrumented"
      assert_equal expected_payload, event.payload
    end

    test "does not include :repo keys for org hooks" do
      events = subscribe "hook.ping"

      @org_hook.ping

      assert event = events.pop, "not instrumented"
      refute event.payload.key?(:repo)
      refute event.payload.key?(:repo_id)

      org = @org_hook.installation_target
      assert_equal org.id, event.payload[:org_id]
      assert_equal org.login, event.payload[:org]
    end

    test "only includes :user keys for user owned repo hooks" do
      events = subscribe "hook.ping"

      @repo_hook.ping

      assert event = events.pop, "not instrumented"
      refute event.payload.key?(:org)
      refute event.payload.key?(:org_id)

      assert_equal @user.id, event.payload[:user_id]
      assert_equal @user.login, event.payload[:user]

      repo = @repo_hook.installation_target
      assert_equal repo.id, event.payload[:repo_id]
      assert_equal repo.nwo, event.payload[:repo]
    end

    test "only includes :org keys for org owned repo hooks" do
      events = subscribe "hook.create"

      org_owned_repo = create :repository, owner: @org
      hook = create :hook, :web, installation_target: org_owned_repo
      assert event = events.pop, "not instrumented"

      refute event.payload.key?(:user)
      refute event.payload.key?(:user_id)

      assert_equal @org.id, event.payload[:org_id]
      assert_equal @org.login, event.payload[:org]

      repo = hook.installation_target
      assert_equal repo.id, event.payload[:repo_id]
      assert_equal repo.nwo, event.payload[:repo]
    end

    test "only includes :user keys for user owned sponsors listing hooks" do
      events = subscribe "hook.create"

      sponsors_user = create :user
      user_owned_sponsors_listing = create :sponsors_listing, sponsorable: sponsors_user
      hook = create :hook, :all_events, installation_target: user_owned_sponsors_listing
      assert event = events.pop, "not instrumented"

      refute event.payload.key?(:org)
      refute event.payload.key?(:org_id)

      assert_equal sponsors_user.id, event.payload[:user_id]
      assert_equal sponsors_user.login, event.payload[:user]

      sponsors_listing = hook.installation_target
      assert_equal sponsors_listing.id, event.payload[:sponsors_listing_id]
    end

    test "only includes :org keys for org owned sponsors listing hooks" do
      events = subscribe "hook.create"

      sponsors_org = create :organization
      org_owned_sponsors_listing = create :sponsors_listing, sponsorable: sponsors_org
      hook = create :hook, :all_events, installation_target: org_owned_sponsors_listing
      assert event = events.pop, "not instrumented"

      refute event.payload.key?(:user)
      refute event.payload.key?(:user_id)

      assert_equal sponsors_org.id, event.payload[:org_id]
      assert_equal sponsors_org.login, event.payload[:org]

      sponsors_listing = hook.installation_target
      assert_equal sponsors_listing.id, event.payload[:sponsors_listing_id]
    end

    test "only includes :user keys for user owned integration hooks" do
      events = subscribe "hook.create"

      user_owned_integration = create :integration, :with_instrumentation, :with_active_hook, owner: @user
      assert event = events.pop, "not instrumented"

      refute event.payload.key?(:org)
      refute event.payload.key?(:org_id)

      assert_equal @user.id, event.payload[:user_id]
      assert_equal @user.login, event.payload[:user]

      assert_equal user_owned_integration.id, event.payload[:integration_id]
      assert_equal user_owned_integration.name, event.payload[:integration]
    end

    test "only includes :org keys for org owned integration hooks" do
      events = subscribe "hook.create"

      user_owned_integration = create :integration, :with_instrumentation, :with_active_hook, owner: @org
      assert event = events.pop, "not instrumented"

      refute event.payload.key?(:user)
      refute event.payload.key?(:user_id)

      assert_equal @org.id, event.payload[:org_id]
      assert_equal @org.login, event.payload[:org]

      assert_equal user_owned_integration.id, event.payload[:integration_id]
      assert_equal user_owned_integration.name, event.payload[:integration]
    end

    test "instruments hook.create when a business hook is created" do
      events = subscribe "hook.create"

      hook = create :hook,
        installation_target: @business,
        events: %w(ping),
        creator: @user,
        config: { "url" => "http://example.com", "secret" => "password" }

      expected_payload = {
        name: "webhook",
        oauth_application_id: nil,
        oauth_application: nil,
        creator: @user.login,
        hook_id: hook.id,
        hook_type: :business,
        business: hook.installation_target.slug,
        business_id: hook.installation_target_id,
        webhook: true,
        config: { "url" => "http://example.com", "secret" => "********", "insecure_ssl" => "0", "content_type" => "form" },
        events: ["ping"],
        active: true,
      }

      assert event = events.pop, "A hook.create event was expected"
      assert_equal expected_payload, event.payload
    end

    test "triggers an event on destroy" do
      events = subscribe "hook.destroy"

      @repo_hook.destroy
      assert event = events.pop, "not instrumented"
      assert_equal @repo_hook.id, event.payload[:hook_id]
    end

    test "instruments hook.destroy when a business hook is destroyed" do
      events = subscribe "hook.destroy"
      @business_hook.destroy

      expected_payload = {
        name: "webhook",
        hook_id: @business_hook.id,
        hook_type: :business,
        business: @business_hook.installation_target.slug,
        business_id: @business_hook.installation_target_id,
        webhook: true,
        config: { "insecure_ssl" => "0", "content_type" => "form" },
        events: [],
        active: true,
      }

      assert event = events.pop, "A hook.destroy event was expected"
      assert_equal expected_payload, event.payload
    end

    test "triggers hook.config_changed when updating config" do
      events = subscribe "hook.config_changed"

      @repo_hook.update config: { "url" => "http://example.com/callback/v2" }

      assert event = events.pop, "expected instrumentation event"
      assert_equal @repo_hook.id, event.payload[:hook_id]
      assert_equal({ "url" => "http://example.com", "secret" => "********", "insecure_ssl" => "0", "content_type" => "form" }, event.payload[:config_was])
      assert_equal({ "url" => "http://example.com/callback/v2", "insecure_ssl" => "0", "content_type" => "form" }, event.payload[:config])
    end

    test "instruments hook.config_changed when config changed on a business hook" do
      events = subscribe "hook.config_changed"
      @business_hook.update config:  { "url" => "http://example.com/callback/v2" }

      expected_payload = {
        name: "webhook",
        hook_id: @business_hook.id,
        hook_type: :business,
        business: @business_hook.installation_target.slug,
        business_id: @business_hook.installation_target_id,
        webhook: true,
        config_was: { "url" => "http://example.com", "insecure_ssl" => "0", "content_type" => "form" },
        config: { "url" => "http://example.com/callback/v2", "insecure_ssl" => "0", "content_type" => "form" },
        events: ["ping"],
        active: true,
      }

      assert event = events.pop, "A hook.config_changed event was expected"
      assert_equal expected_payload, event.payload
    end

    test "does NOT trigger hook.config_changed when setting config to same value" do
      events = subscribe "hook.config_changed"

      @repo_hook.update config: { "url" => "http://example.com", "secret" => "donottell" }

      refute events.pop, "expected NO instrumentation event"
    end

    test "triggers hook.events_changed when changing events" do
      events = subscribe "hook.events_changed"

      @repo_hook.update events: %w(*)

      assert event = events.pop, "expected instrumentation event"
      assert_equal @repo_hook.id, event.payload[:hook_id]
      assert_equal %w(push), event.payload[:events_were]
      assert_equal %w(*), event.payload[:events]
    end

    test "does NOT trigger hook.events_changed setting hooks to the same value" do
      events = subscribe "hook.events_changed"

      @repo_hook.update events: %w(push)

      refute events.pop, "expected NO instrumentation event"
    end

    test "does NOT trigger hook.events_changed setting hooks when changing unrelated fields" do
      events = subscribe "hook.events_changed"

      @repo_hook.update url: "http://www.example.com"

      refute events.pop, "expected NO instrumentation event"
    end

    test "triggers hook.active_changed when changing active status" do
      events = subscribe "hook.active_changed"

      @repo_hook.update active: false

      assert event = events.pop, "a hook.active_changed event was expected"
      assert_equal @repo_hook.id, event.payload[:hook_id]
      assert_equal true, event.payload[:active_was]
      assert_equal false, event.payload[:active]
    end

    test "does NOT trigger hook.active_changed when setting status to the same value" do
      events = subscribe "hook.active_changed"

      @repo_hook.update events: true

      refute events.pop, "expected NO instrumentation event"
    end

    test "does NOT trigger hook.active_changed when changing unrelated fields" do
      events = subscribe "hook.active_changed"

      @repo_hook.update url: "http://www.example.com"

      refute events.pop, "expected NO instrumentation event"
    end

    test "fires hook.create event with expected payload when email notification is added" do
      events = subscribe "hook.create"
      hook = create :hook, creator: @user, name: "email", config: { "address" => "email@example.com" }

      assert event = events.pop, "A hook.create event was expected"
      assert event.payload[:name] = "Email"
      assert event.payload[:hook_type] = "repo"
    end
  end

  context ":validations" do
    test "requires name" do
      @repo_hook.name = nil
      refute @repo_hook.valid?
    end

    test "requires a valid name" do
      @repo_hook.name = "irc"
      refute @repo_hook.valid?
      assert_equal "Name can only be set to 'web' or 'email'.", @repo_hook.errors.full_messages.to_sentence

      @repo_hook.name = "web"
      assert @repo_hook.valid?
    end

    test "it validates pinned_api_version" do
      GitHub.stubs(:api_versions).returns(["2020-01-01"])
      @repo_hook.pinned_api_version = "bad"
      refute @repo_hook.valid?
      assert_equal "Pinned api version is invalid", @repo_hook.errors.full_messages.to_sentence
      @repo_hook.pinned_api_version = "2020-01-01"
      assert @repo_hook.valid?
    end

    test "requires installation_target" do
      @repo_hook.installation_target = nil
      refute @repo_hook.valid?
    end

    test "requires a valid installation_target_type" do
      issue = create(:issue)
      @repo_hook.installation_target = issue
      refute_predicate @repo_hook, :valid?
    end

    test "strips whitespace from URLs after validation" do
      @repo_hook.url = "   http://example.com  "
      assert @repo_hook.valid?
      assert_equal "http://example.com", @repo_hook.url
    end

    test "requires a valid URL" do
      @repo_hook.url = "http://example.com:notaport"
      refute @repo_hook.valid?
    end

    test "requires a valid protocol" do
      @repo_hook.url = "theseus.news.cs.nyu.edu"
      refute @repo_hook.valid?
    end

    test "does not allow javascript garbage" do
      @repo_hook.url = 'javascript:(function(a){window.trelloAppKey="optional";window.trelloIdList="optional";var b=a.createElement("script");b.src="https://raw.github.com/danlec/Trello-Bookmarklet/master/trello_bookmarklet.js";a.getElementsByTagName("head")[0].appendChild(b)})(document);'
      refute @repo_hook.valid?
    end

    test "allows templated URLs if app has Proxima sync capability enabled" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })
      app_hook = create :hook, installation_target: app
      app_hook.url = "https://{hostname}/callback"

      assert_predicate app_hook, :valid?
    end

    test "does not allow templated URLs if app does not have Proxima sync capability" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: false }, options: { owner: @user })
      app_hook = create :hook, installation_target: app
      app_hook.url = "https://{hostname}/callback"

      refute_predicate app_hook, :valid?
    end

    test "requires a valid hostname" do
      @repo_hook.url = "https://some_attacker_domain%2523.gist.github.com/auth/github/callback"
      refute @repo_hook.valid?
    end

    test "does not allow run-on strings for secret" do
      @repo_hook.secret = "x" * 2048
      refute @repo_hook.valid?
    end

    test "does not allow un-escaped unicode characters" do
      @repo_hook.url = "https://example.com:port/test\u00A0"
      refute @repo_hook.valid?
    end

    test "does not allow un-escaped spaces" do
      @repo_hook.url = "https://example.com:port/foo bar"
      refute @repo_hook.valid?
    end

    test "does allow escaped unicode characters" do
      @repo_hook.url = "http://example.com/foo%20bar/%E1%BD%84D"
      assert @repo_hook.valid?
      assert_equal "http://example.com/foo%20bar/%E1%BD%84D", @repo_hook.url
    end

    unless GitHub.enterprise?
      ["github.net", "consul", "github.net.", "consul."].each do |domain|
        test "does not allow github internal domain #{domain}" do
          @repo_hook.url = "http://services.#{domain}/hooks"
          refute @repo_hook.valid?
          assert_equal "Url host is not allowed", @repo_hook.errors.full_messages.to_sentence

          @repo_hook.url = "http://#{domain}/hooks"
          refute @repo_hook.valid?
          assert_equal "Url host is not allowed", @repo_hook.errors.full_messages.to_sentence
        end
      end
    end

    ["github.net", "consul", "localhost"].each do |domain|
      test "allows domains that include #{domain} as substring" do
        @repo_hook.url = "http://mycustom#{domain}/hooks"
        assert @repo_hook.valid?
      end
    end

    test "does not allow loopback domains" do
      GitHub.stubs(:allow_webhook_loopback_addresses?).returns(false)
      ["localhost", "github.localhost", "127.0.1.23", "0.128.11.2"].each do |domain|
        @repo_hook.url = "http://#{domain}/hooks"
        refute @repo_hook.valid?
        assert_equal "Url is not supported because it isn't reachable over the public Internet (#{domain})",
        @repo_hook.errors.full_messages.to_sentence
      end
    end

    test "allows loopback domains only in Enterprise, only for the launch app" do
      GitHub.stubs(:allow_webhook_loopback_addresses?).returns(false)
      make_trusted_oauth_apps_owner

      @repo_hook.installation_target = create(:launch_integration)
      @repo_hook.url = "http://localhost/webhook"

      if GitHub.enterprise?
        assert @repo_hook.valid?
      else
        refute @repo_hook.valid?
      end
    end

    test "does not allow loopback domains in Enterprise for a standard integration" do
      GitHub.stubs(:allow_webhook_loopback_addresses?).returns(false)

      @repo_hook.installation_target = create(:integration)
      @repo_hook.url = "http://localhost/webhook"

      refute @repo_hook.valid?
    end

    test "allows non-loopback ipaddresses" do
      ["111.0.0.0", "128.0.1.1", "1.1.1.0"].each do |domain|
        @repo_hook.url = "http://#{domain}/hooks"
        assert @repo_hook.valid?
        assert_empty @repo_hook.errors[:base]
      end
    end

    test "requires https for the marketplace" do
      listing = create(:marketplace_listing)
      @repo_hook.installation_target = listing
      @repo_hook.url = "http://example.com"
      refute @repo_hook.valid?
    end

    test "requires SSL certificates for the marketplace" do
      listing = create(:marketplace_listing)
      @repo_hook.installation_target = listing
      @repo_hook.insecure_ssl = "1"
      @repo_hook.url = "https://example.com"
      refute @repo_hook.valid?
    end

    test "does not allow duplicate hook that shares an event" do
      [first = build(:hook, installation_target: @repo),
        dupe = build(:hook, installation_target: @repo)].each do |hook|

        hook.config = { "url" => "http://example.com" }
        hook.events = %w(push)
        hook.active = true
      end
      dupe.add_events "issues"

      assert first.save

      refute dupe.valid?
      assert_equal 1, dupe.errors[:base].length
      assert_equal "Hook already exists on this repository", dupe.errors[:base].first
    end

    test "does not allow updating a hook such that it becomes a duplicate hook" do
      [first = build(:hook, installation_target: @repo),
        dupe = build(:hook, installation_target: @repo)].each do |hook|

        hook.events = %w(push)
        hook.active = true
      end
      first.url = "http://example.com/first"
      dupe.url = "http://example.com/second"

      assert first.save
      assert dupe.save

      dupe.url = first.url
      refute dupe.valid?
      assert_equal 1, dupe.errors[:base].length
      assert_equal "Hook already exists on this repository", dupe.errors[:base].first
    end

    test "allows hook with different name" do
      [first = build(:hook, installation_target: @repo),
        dupe = build(:hook, installation_target: @repo)].each do |hook|

        hook.config = { "url" => "http://example.com" }
        hook.events = %w(push)
        hook.active = true
      end
      dupe.name = "email"
      dupe.config = { address: "user@github.com" }

      assert first.save
      assert dupe.valid?
    end

    test "allows hook with different events" do
      [first = build(:hook, installation_target: @repo),
        dupe = build(:hook, installation_target: @repo)].each do |hook|

        hook.config = { "url" => "http://example.com" }
        hook.events = %w(push)
        hook.active = true
      end
      dupe.events = %w(issues)

      assert first.save
      assert dupe.valid?
    end

    test "allows same-configured hook if in different repositories" do
      [first = build(:hook, installation_target: @repo),
        dupe = build(:hook, installation_target: @other_repo)].each do |hook|

        hook.config = { "url" => "http://example.com" }
        hook.events = %w(push)
        hook.active = true
      end

      assert first.save
      assert dupe.valid?
    end

    test "allows hook with different config" do
      [first = build(:hook, installation_target: @repo),
        other = build(:hook, installation_target: @repo)].each do |hook|

        hook.config = { "url" => "http://example.com" }
        hook.events = %w(push)
        hook.active = true
      end
      other.config = other.config.merge("content_type" => "json")

      assert first.save
      assert other.valid?
    end

    # Regression test for https://github.com/github/ecosystem-events/issues/1490
    test "does not allow duplicate when config and events are the same, if the hook is active and the dupe is inactive" do
      [first = build(:hook, installation_target: @repo),
        dupe = build(:hook, installation_target: @repo)].each do |hook|

        hook.config = { "url" => "http://example.com" }
        hook.events = %w(push)
        hook.active = true
      end
      dupe.active = false

      assert first.save, first.errors.full_messages.to_sentence

      refute dupe.valid?
      assert_equal 1, dupe.errors[:base].length
      assert_equal "Hook already exists on this repository", dupe.errors[:base].first
    end

    # Regression test for https://github.com/github/ecosystem-events/issues/1490
    test "does not allow duplicate when config and events are the same, if the hook is inactive and the dupe is active" do

      [first = build(:hook, installation_target: @repo),
        dupe = build(:hook, installation_target: @repo)].each do |hook|

        hook.config = { "url" => "http://example.com" }
        hook.events = %w(push)
        hook.active = false
      end
      dupe.active = true

      assert first.save, first.errors.full_messages.to_sentence

      refute dupe.valid?
      assert_equal 1, dupe.errors[:base].length
      assert_equal "Hook already exists on this repository", dupe.errors[:base].first
    end


    test "assigns default value to insecure_ssl at hook creation if unspecified in config and persists to DB" do
      hook = build(:hook, installation_target: @repo)
      hook.config = { "url" => "http://example.com" }
      hook.events = %w(push)
      hook.active = true

      assert hook.save
      hook.reload
      assert_equal({ "url" => "http://example.com", "insecure_ssl" => "0" }, hook.config)
    end

    # Regression test for https://github.com/github/ecosystem-events/issues/1508
    test "does not allow duplicate hook if original hook was created with a config that omitted 'insecure_ssl'" do
      [first = build(:hook, installation_target: @repo),
        other = build(:hook, installation_target: @repo)].each do |hook|

        hook.config = { "url" => "http://example.com" }
        hook.events = %w(push)
        hook.active = true
      end
      other.config = other.config.merge("insecure_ssl" => "0")

      assert first.save

      refute other.valid?
      assert_equal 1, other.errors[:base].length
      assert_equal "Hook already exists on this repository", other.errors[:base].first
    end

    test "allows deactivation with other fields if fields are valid" do
      @repo_hook.url = "https://webhook.com"
      @repo_hook.active = false
      assert @repo_hook.valid?
    end

    test "doesn't allow deactivation with other fields unless fields are valid" do
      @repo_hook.url = "webhook"
      @repo_hook.active = false
      refute @repo_hook.valid?
      assert_match(/To mark this hook as inactive only send the active field or fix the invalid fields/, @repo_hook.errors.full_messages.join(" "))
      @repo_hook.url = "https://webhook.com"
      assert @repo_hook.valid?
    end

    test "doesn't allow activation unless all fields are valid" do
      @repo_hook.url = "webhook"
      @repo_hook.active = true
      refute @repo_hook.valid?
      @repo_hook.url = "https://webhook.com"
      assert @repo_hook.valid?
    end

    test "allows deactivation if the hook is already invalid and only the active field is changing" do
      @repo_hook.url = "webhook"
      @repo_hook.active = true
      @repo_hook.save(validate: false)
      @repo_hook.reload
      assert_equal "webhook", @repo_hook.url
      @repo_hook.active = false
      assert @repo_hook.valid?
    end

  end

  context "GitHub.dogstats" do
    test "increments `hooks.create.org_hook` when an org hook is created" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      create :hook, :web, installation_target: create(:organization)
      assert_equal 1, GitHub.dogstats.increments("hooks.create").length
      assert_includes GitHub.dogstats.increments("hooks.create")[0].tags, "hook_type:org_hook"
    end

    test "increments `hooks.create.repo_hook` when a repo hook is created" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      create :hook, :web, installation_target: create(:repository)
      assert_equal 1, GitHub.dogstats.increments("hooks.create").length
      assert_includes GitHub.dogstats.increments("hooks.create")[0].tags, "hook_type:repo_hook"
    end

    test "increments `hooks.create.business_hook` when a business hook is created" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      create :hook, installation_target: @business, events: %w(ping)
      assert_equal 1, GitHub.dogstats.increments("hooks.create").length
      assert_includes GitHub.dogstats.increments("hooks.create")[0].tags, "hook_type:business_hook"
    end
  end

  context ".allowed_event_types" do
    test "allows all event types" do
      assert_equal %w(*), @org_hook.allowed_event_types - Hook::EventRegistry.event_classes.map(&:event_type)
    end
  end

  context ".editable_by scope" do
    test "returns hooks created by that OAuth app" do
      user_via_oauth_app = User.with_oauth_hashed_token(@oauth_access.hashed_token)
      assert_equal [@oauth_org_hook], @org.hooks.editable_by(user_via_oauth_app)
    end

    test "returns hooks created by a user" do
      assert_equal [@org_hook], @org.hooks.editable_by(@user)
    end

    test "returns hooks that have no known creator" do
      assert_raises(ArgumentError) do
        @org.hooks.editable_by(nil)
      end
    end
  end

  context ".valid_event_type?" do
    test "returns true for event in `Hook::EventRegistry`" do
      assert Hook.valid_event_type?("push")
      assert Hook.valid_event_type?(:push)
    end

    test "returns false for an invalid event" do
      refute Hook.valid_event_type?("fruit_loop")
      refute Hook.valid_event_type?(:fruit_loop)
    end

    test "returns true for the wildcard event" do
      assert Hook.valid_event_type?(Hook::WildcardEvent)
      assert Hook.valid_event_type?(Hook::WildcardEvent.to_sym)
    end
  end

  context "#events=" do
    test "sets the events on the serialize attribute" do
      @repo_hook.events = %w[push issues]
      assert_same_elements %w[push issues], @repo_hook.events
    end

    test "create HookEventSubscription records on save" do
      @repo_hook.events = %w[push issues]
      @repo_hook.save!
      @repo_hook.reload
      assert_same_elements %w[push issues], @repo_hook.subscribed_events
    end

    test "create HookEventSubscription records on save when events are pushed in" do
      @repo_hook.add_events "issues"
      assert_same_elements %w[push issues], @repo_hook.events
      @repo_hook.save!
      @repo_hook.reload
      assert_same_elements %w[push issues], @repo_hook.events
      assert_same_elements %w[push issues], @repo_hook.subscribed_events
    end

    test "remove HookEventSubscription records if removed on save" do
      @repo_hook.events = ["push"]
      @repo_hook.save!
      @repo_hook.reload
      assert_same_elements ["push"], @repo_hook.subscribed_events
      @repo_hook.events = ["issues"]
      @repo_hook.save!
      @repo_hook.reload
      assert_same_elements ["issues"], @repo_hook.subscribed_events
    end

    test "does not allow invalid event names" do
      @repo_hook.events = %w[bogus_event push]
      @repo_hook.save
      @repo_hook.reload
      assert_match(/bogus_event is not a valid event name/, @repo_hook.errors.full_messages.join(" "))
    end

    test "does not change HookEventSubscription records when events aren't changed" do
      assert_same_elements ["push"], @repo_hook.subscribed_events
      @repo_hook.save!
      @repo_hook.reload
      assert_same_elements ["push"], @repo_hook.subscribed_events
    end

    test "deletes all associated HookEventSubscription records when events is set to nil" do
      assert_same_elements ["push"], @repo_hook.subscribed_events
      @repo_hook.events = nil
      @repo_hook.save!
      @repo_hook.reload
      assert_empty @repo_hook.events
      assert_empty @repo_hook.subscribed_events
    end

    test "doesn't raise when the HookEventSubscription is not unique" do
      @repo_hook.event_types.stubs(:find_by_name).returns(false)
      @repo_hook.events = ["ping"]
      assert @repo_hook.save!
    end

    test "doesn't raise when the HookEventSubscription is not database-level unique" do
      @repo_hook.event_types.stubs(:find_by_name).returns(false)
      @repo_hook.event_types.stubs(:create).raises(ActiveRecord::RecordNotUnique.new("Not Unique Stub"))
      @repo_hook.events = ["ping"]
      assert @repo_hook.save!
    end
  end

  context "#name=" do
    test "generates consistent short name" do
      ["Abc-Def", "AbcDef", "Abc Def", "abcdef"].each do |input|
        @repo_hook.name = input
        assert_equal "abcdef", @repo_hook.name
      end
    end
  end

  context "#check_events" do
    test "deactivates hook with only invalid events" do
      @repo_hook.events = %w(fruit_loop_event)
      @repo_hook.active = true
      assert @repo_hook.active
      @repo_hook.check_events
      refute @repo_hook.active
    end

    test "removes duplicate events" do
      @repo_hook.add_events(%w(issue_comment label issue_comment))
      @repo_hook.check_events
      assert_same_elements %w(issue_comment push label), @repo_hook.events
    end

    test "removes invalid events" do
      @repo_hook.add_events(%w(fruit_loop_event issues))
      @repo_hook.check_events
      assert_same_elements %w(push issues), @repo_hook.events
    end

    test "clears existing events if wildcard is added" do
      @repo_hook.add_events(%w(issue_comment))
      @repo_hook.check_events
      assert_equal %w(push issue_comment), @repo_hook.events

      @repo_hook.add_events(Hook::WildcardEvent)
      @repo_hook.check_events
      assert_equal [Hook::WildcardEvent], @repo_hook.events
    end

    test "does not deactivate if an Integration hook has no events" do
      integration = create(:integration, :with_active_hook, default_permissions: { "metadata" => :read, "contents" => :read }, default_events: ["push"])
      assert_predicate integration.hook, :active?

      integration.update(default_permissions: { "metadata" => :read }, default_events: [])
      integration.reload

      assert_predicate integration.hook, :active?
    end
  end

  context "#call?" do
    test "returns true if active and event is included" do
      @repo_hook.active = true
      assert @repo_hook.call?(:push)
    end

    test "returns true if testing and event is included" do
      @repo_hook.active = false
      assert @repo_hook.call?(:push, is_testing: true)
    end

    test "returns false if not active but event is included" do
      @repo_hook.active = false
      refute @repo_hook.call?(:push)
    end

    test "returns false if the event isn't included" do
      @repo_hook.events = [:issue_comment]
      @repo_hook.active = true
      @repo_hook.save!
      @repo_hook.reload
      refute @repo_hook.call?(:push)
      @repo_hook.active = false
      refute @repo_hook.call?(:push)
      refute @repo_hook.call?(:push, is_testing: true)
    end

    test "returns true for an active wildcard event" do
      @repo_hook.events = [Hook::WildcardEvent]
      @repo_hook.active = true
      @repo_hook.save!
      @repo_hook.reload

      assert @repo_hook.call?(:label)
    end
  end

  context "#check_events" do
    test "hooks with no events are marked inactive" do
      hook = Hook.new events: %w(foo), active: true
      hook.valid?
      assert_empty hook.events
      refute hook.active?
    end
  end

  context "#last_status_to_label" do
    test "translates '200' to 'active'" do
      @repo_hook.last_status = 200
      assert_equal :active, @repo_hook.last_status_to_label
    end

    test "translates '422' to 'misconfigured'" do
      @repo_hook.last_status = 422
      assert_equal :misconfigured, @repo_hook.last_status_to_label
    end

    test "translates '504' to 'timeout'" do
      @repo_hook.last_status = 504
      assert_equal :timeout, @repo_hook.last_status_to_label
    end

    test "translates '404' to 'missing'" do
      @repo_hook.last_status = 404
      assert_equal :missing, @repo_hook.last_status_to_label
    end

    test "translates an unkown status to 'unused'" do
      assert_equal :unused, @repo_hook.last_status_to_label
    end
  end

  context "#config" do
    test "sets default values" do
      hook = Hook.new
      assert_empty hook.events
      assert_empty hook.config
    end

    test "returns an empty hash if it was previously set to nil" do
      hook = build :hook, name: "irc", config: nil
      assert_empty hook.config
    end
  end

  context "#hook_within_limit" do
    test "ensures that a single event (like 'push') may only be added up to the `hook_limit`" do
      hook = build(:hook, installation_target: @repo, name: "web", url: "http://foo.com/1")
      hook.events = %w(push)
      hook.active = true

      hook2 = build(:hook, installation_target: @repo, name: "web", url: "http://foo.com/2")
      hook2.events = %w(push)
      hook2.active = true

      hook3 = build(:hook, installation_target: @repo, name: "web", url: "http://foo.com/3")
      hook3.events = %w(pull_request)
      hook3.hook_limit = 2
      hook3.active = true

      hook4 = build(:hook, installation_target: @repo, name: "web", url: "http://foo.com/4")
      hook4.events = %w(pull_request push)
      hook4.hook_limit = 2
      hook4.active = true

      assert hook.save, hook.errors.full_messages.to_sentence
      assert hook2.save, hook2.errors.full_messages.to_sentence
      assert hook3.save, hook3.errors.full_messages.to_sentence
      refute hook4.save, "Expected to fail because there are 3 `push` events"
    end

    test "allows hooks to be re-saved when limit is reached" do
      hook = build(:hook, installation_target: @repo, name: "email", config: { address: "user@github.com" })
      hook.events = %w(issues push)
      hook.active = true

      hook2 = build(:hook, installation_target: @repo, name: "web")
      hook2.events = %w(issue_comment push)
      hook2.active = true

      hook3 = build(:hook, installation_target: @repo, name: "web")
      hook3.events = %w(pull_request push)
      hook3.config = hook.config.merge("url" => "http://example.com")
      hook3.active = true

      hook.save!
      hook2.save!
      hook3.save!

      hook3 = Hook.find hook3.id
      hook3.hook_limit = 2

      hook3.events = %w(pull_request push)
      hook3.config = hook3.config.merge("url" => "http://example.com")
      assert hook3.save, hook3.errors.full_messages.to_sentence
    end

    if !GitHub.enterprise?
      test "rejects 21 hooks to be installed on a Repository" do
        basic_repo = create :repository, owner: @user
        # necessary for the `all-fetaures` ci build
        GitHub.flipper[:increased_webhook_limit].disable

        20.times do
          hook = build(:hook, installation_target: basic_repo, name: "web", events: %w(push), active: true)
          hook.save!
        end

        hook = build(:hook, installation_target: basic_repo, name: "web", active: true, events: %w(push))
        refute hook.save, "Expected to fail because there are 20 installed hooks"
      end

      test "allows 30 hooks to be installed on a Repository when flagged" do
        cool_repo = create :repository, owner: @user
        GitHub.flipper[:increased_webhook_limit].enable_actor(cool_repo)

        29.times do
          hook = build(:hook, installation_target: cool_repo, name: "web", events: %w(push), active: true)
          hook.save!
        end

        hook = build(:hook, installation_target: cool_repo, name: "web", active: true, events: %w(push))
        assert hook.save
        hook = build(:hook, installation_target: cool_repo, name: "web", active: true, events: %w(push))
        refute hook.save
      end

      test "allows 30 hooks to be installed on a Repository owned by a special org when flagged" do
        cool_org = create :organization, admin: @user
        cool_repo = create :repository, owner: cool_org
        GitHub.flipper[:increased_webhook_limit].enable_actor(cool_org)

        29.times do
          hook = build(:hook, installation_target: cool_repo, name: "web", events: %w(push), active: true)
          hook.save!
        end

        hook = build(:hook, installation_target: cool_repo, name: "web", active: true, events: %w(push))
        assert hook.save
        hook = build(:hook, installation_target: cool_repo, name: "web", active: true, events: %w(push))
        refute hook.save
      end
    end
  end

  context "#configure_with" do
    test "requires url for generic web hook" do
      hook = build :hook, installation_target: @repo, name: "web"
      hook.events = %w(push)
      hook.configure_with(true, { "url" => "" })
      refute hook.valid?
    end

    test "requires url for generic web hook to have a length less than or equal to the value column limit" do
      hook = build :hook, installation_target: @repo, name: "web"
      hook.events = %w(push)
      limit = hook.config_attribute_records.columns_hash["value"].limit
      hook.configure_with(true, { "url" => "aa" * limit })

      refute hook.valid?
    end

    test "sends a ping after creation for webhooks" do
      hook = build :hook, installation_target: @repo, name: "web"
      hook.events = %w(push)

      Hook::Event::PingEvent.expects(:queue).once

      hook.configure_with(true, { "url" => "http://www.example.com" })
    end

    test "doesn't send a ping for non-webhooks" do
      hook = build :hook, installation_target: @repo, name: "basecamp"
      hook.events = %w(push)

      Hook::Event::PingEvent.expects(:queue).never

      hook.configure_with(true, { "url" => "http://www.example.com" })
    end
  end

  context "#track_creator" do
    test "created by a user" do
      hook = Hook.new
      hook.track_creator(create :user, login: "johndoe")

      assert hook.created_by_user?
      refute hook.created_by_oauth_application?
      refute hook.created_by_unknown?

      assert_equal "johndoe", hook.creator_name
    end

    test "created by an OauthApplication" do
      hook = Hook.new
      oauth_token = make_oauth(create(:user, login: "johndoe"), [:repo], @oauth_app).reset_token

      user = User.with_oauth_token(oauth_token)
      hook.track_creator(user)
      assert hook.created_by_oauth_application?
      refute hook.created_by_user?
      refute hook.created_by_unknown?

      assert_equal "Janky on behalf of johndoe", hook.creator_name
    end

    test "created by a personal access token" do
      hook = Hook.new

      personal_access = create(:personal_token_oauth_access, user: @user)
      personal_access_token = personal_access.reset_token

      user = User.with_oauth_token(personal_access_token)
      hook.track_creator(user)
      assert hook.created_by_user?
      refute hook.created_by_oauth_application?
      refute hook.created_by_unknown?
    end

    test "created before tracking so creator is unknown" do
      hook = Hook.new
      assert hook.created_by_unknown?
      refute hook.created_by_user?
      refute hook.created_by_oauth_application?

      assert_equal "unknown", hook.creator_name
    end
  end

  context "#url" do
    test "does not normalize the url when url contains un-escaped unicode characters" do
      @repo_hook.update config: { "url" => "http://example.com/foo bar" }
      assert_equal "http://example.com/foo bar", @repo_hook.url
    end

    test "returns nil if the value is nil" do
      @repo_hook.update config: { "url" => nil }

      assert_nil @repo_hook.url
    end

    test "interpolates templated url if app has Proxima sync capability enabled" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })
      app_hook = create :hook, installation_target: app
      app_hook.url = "https://{hostname}/callback"

      assert_equal "#{GitHub.url}/callback", app_hook.url
    end

    test "does not interpolate templated url if app does not have Proxima sync capability" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: false }, options: { owner: @user })
      app_hook = create :hook, installation_target: app
      app_hook.url = "https://{hostname}/callback"

      assert_equal "https://{hostname}/callback", app_hook.url
    end

    test "does not interpolate templated url if installation target is not an Integration" do
      @repo_hook.update config: { "url" => "https://{hostname}/callback" }

      refute_predicate @repo_hook, :integration_hook?
      assert_equal "https://{hostname}/callback", @repo_hook.url
    end
  end

  context "#masked_config" do
    test "returns a generic mask for password fields" do
      hook = build(:hook, "name" => "web",
                       "config" => {
                         "secret" => "1hook-secretX",
                         "url" => "https://git.io/a",
                       })
      masked_config = hook.masked_config
      assert_equal "********", masked_config["secret"]
      assert_equal "https://git.io/a", masked_config["url"]
    end

    test "returns a mask for config given as an argument" do
      masked_config = @repo_hook.masked_config("secret" => "password", "url" => "http://example.com")
      assert_equal "********", masked_config["secret"]
      assert_equal "http://example.com", masked_config["url"]
    end

    test "ignores invalid config keys" do
      hook = build(:hook, "name" => "web",
                       "config" => {
                         "secret" => "1hook-secretX",
                         "endpoint" => "https://git.io/a",
                       })
      masked_config = hook.masked_config
      assert_equal "********", masked_config["secret"]
      assert_nil masked_config["endpoint"]
    end

    test "returns an empty hash when passed a nil config" do
      assert_equal({}, @repo_hook.masked_config(nil))
    end

    test "returns interpolated tenant-scoped url value if app has Proxima sync capability enabled" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })
      hook = create :hook, installation_target: app
      hook.url = "https://{hostname}/callback"

      # Ensure we're interpolating hostname
      assert_equal "#{GitHub.url}/callback", hook.masked_config["url"]
    end

    test "does not return interpolated tenant-scoped url value if app does not have Proxima sync capability" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: false }, options: { owner: @user })
      hook = create :hook, installation_target: app
      hook.url = "https://{hostname}/callback"

      # Ensure the value is not interpolated
      assert_equal "https://{hostname}/callback", hook.masked_config["url"]
    end
  end

  context "config_with_interpolated_url" do
    test "returns the config with the interpolated url" do
      app = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, options: { owner: @user })
      hook = create :hook, installation_target: app
      hook.url = "https://{hostname}/callback"

      # Ensure we're interpolating hostname
      assert_equal "#{GitHub.url}/callback", hook.config_with_tenant_scoped_url["url"]
    end
  end

  context "#hookshot_parent_id" do
    test "returns organization-{id} for org hooks" do
      assert_equal "organization-#{@org.id}", @org_hook.hookshot_parent_id
    end

    test "returns repository-{id} for repo hooks" do
      assert_equal "repository-#{@repo.id}", @repo_hook.hookshot_parent_id
    end

    test "returns business-{id} for business hooks" do
      assert_equal "business-#{@business.id}", @business_hook.hookshot_parent_id
    end
  end

  context "#hook_type" do
    test "returns :repo for repo hooks" do
      assert_equal :repo, @repo_hook.hook_type
    end

    test "returns :org for org hooks" do
      assert_equal :org, @org_hook.hook_type
    end

    test "returns :business for business hooks" do
      assert_equal :business, @business_hook.hook_type
    end

    test "returns :marketplace_listing for marketplace listing hooks" do
      hook = build(:hook, installation_target: build(:marketplace_listing))
      assert_equal :marketplace_listing, hook.hook_type
    end
  end

  context "#webhooks_only_for_org_hooks" do
    test "email hooks cannot be installed on an organization" do
      email_hook = build :hook, :org, name: "email", config: { address: "user@github.com" }

      refute email_hook.valid?
      assert_includes email_hook.errors[:base], "Email hooks are only supported on repositories."
    end

    test "email hooks cannot be installed on an enterprise account" do
      email_hook = build :hook, installation_target: @business, name: "email", config: { address: "user@github.com" }

      refute email_hook.valid?
      assert_includes email_hook.errors[:base], "Email hooks are only supported on repositories."
    end
  end

  context "#email_address_is_valid" do
    test "single email address is valid" do
      hook  = build :hook,
        name: "email",
        installation_target: @repo,
        config: { address: "nat@github.com" },
        events: %w(push),
        creator: @user
      assert_predicate hook, :valid?
    end

    test "two email addresses is valid" do
      hook  = build :hook,
        name: "email",
        installation_target: @repo,
        config: { address: "nat@github.com two@github.com" },
        events: %w(push),
        creator: @user
      assert_predicate hook, :valid?
    end

    test "three email addresses is not valid" do
      hook  = build :hook,
        name: "email",
        installation_target: @repo,
        config: { address: "nat@github.com two@github.com three@github.com" },
        events: %w(push),
        creator: @user
      refute_predicate hook, :valid?
      assert_includes hook.errors[:base], "You may only add a maximum of two email addresses."
    end

    test "comma separated is not valid" do
      hook  = build :hook,
        name: "email",
        installation_target: @repo,
        config: { address: "nat@github.com,two@github.com" },
        events: %w(push),
        creator: @user
      refute_predicate hook, :valid?
      assert_includes hook.errors[:base], "Address must be up to 2 valid email addresses separated by whitespace."
    end
  end

  context "#hook_config_is_valid?" do
    test "valid config is valid" do
      hook = build :hook, :web,
        active: true,
        installation_target: @repo,
        config: { "url" => "http://example-valid-config.com", "secret" => "donottell" },
        events: %w(push),
        creator: @user
      assert_predicate hook, :valid?
    end

    test "invalid config is invalid" do
      hook = build :hook, :web,
        active: true,
        installation_target: @repo,
        config: { "url" => "http://example-valid-config.com", "secret" => "donottell", "invalid" => "nope", "invalid2" => "nope" },
        events: %w(push),
        creator: @user
      refute_predicate hook, :valid?
      assert_includes hook.errors[:base], "Invalid config attribute: invalid"
      assert_includes hook.errors[:base], "Invalid config attribute: invalid2"
    end
  end

  context "#editable_by?" do
    test "returns true for repo hooks if user can admin the repo" do
      assert @repo_hook.installation_target.adminable_by?(@user)
      assert @repo_hook.editable_by?(@user)
    end

    test "returns true for repo hooks if user has manage_webhooks FGP" do
      grant_custom_role(user: @random_user, target: @org_repo, fgps: [:manage_webhooks])
      assert @org_repo_hook.editable_by?(@random_user)
    end

    test "returns true for repo hooks if user has a staff unlock" do
      staff = create(:staff_admin_user, :verified, stafftools_roles: ["can-unlock-repos-with-owners-permission"])
      create :staff_access_grant, accessible: @org_repo, granted_by: @org_repo.owner
      staff.unlock_repository(@org_repo, "hi")
      assert @org_repo_hook.editable_by?(staff)
    end

    test "returns false for repo hooks if user is site admin" do
      site_admin = create(:staff_admin_user)
      assert site_admin.site_admin?
      refute @org_repo_hook.editable_by?(site_admin)
    end

    test "returns false for repo hooks if user cannot admin the repo" do
      refute @repo_hook.installation_target.adminable_by?(@random_user)
      refute @repo_hook.editable_by?(@random_user)
    end

    test "returns false for org hooks managed by oauth apps" do
      assert @oauth_org_hook.installation_target.adminable_by?(@user)
      refute @oauth_org_hook.editable_by?(@user)
    end

    test "returns true for org hooks not managed by oauth apps if user can admin the org" do
      assert @org_hook.installation_target.adminable_by?(@user)
      assert @org_hook.editable_by?(@user)
    end

    test "returns false for org hooks if user cannot admin the org" do
      refute @org_hook.installation_target.adminable_by?(@random_user)
      refute @org_hook.editable_by?(@random_user)
    end

    test "returns true for listing hooks if use can admin" do
      listing = create(:marketplace_listing)
      listing_hook = create :hook, installation_target: listing
      assert listing_hook.editable_by?(listing.owner)
    end

    test "returns false for listing hooks if user can't admin" do
      listing = create(:marketplace_listing)
      listing_hook = create :hook, installation_target: listing
      refute listing_hook.editable_by?(create(:user))
    end

    test "returns true for business hooks if user is a business admin" do
      assert @business_hook.editable_by?(@business.owners.first)
    end

    test "returns false for business hooks if user is NOT a business admin" do
      refute @business_hook.editable_by?(@random_user)
    end
  end

  context "#config" do
    test "returns a configuration attribute" do
      refute_empty @repo_hook.config
    end

    test "returns an empty hash with no attributes" do
      @repo_hook.config = nil
      assert_empty @repo_hook.config
    end
  end

  context "#partial_config=" do
    test "creates a HookConfigAttribute model" do
      attributes = { "content_type" => "form", "secret" => "a_value" }
      @repo_hook.partial_config = attributes

      @repo_hook.save!
      @repo_hook.reload
      assert_equal 4, @repo_hook.config_attributes.size
      assert_equal @repo_hook.config, @repo_hook.config_attributes
      assert_equal "a_value", @repo_hook.config_attributes["secret"]
    end

    test "allow creating a HookConfigAttribute model with non-string value" do
      attributes = { "secret" => ["push"] }
      @repo_hook.partial_config = attributes

      @repo_hook.save!
      @repo_hook.reload
      assert_equal 3, @repo_hook.config_attributes.size
      assert_equal @repo_hook.config, @repo_hook.config_attributes
      assert_equal ["push"].to_s, @repo_hook.config_attributes["secret"]
    end

    test "allow creating a HookConfigAttribute model with pre-existing invalid key" do
      @repo_hook.partial_config = { "invalid_key" => "some value" }

      @repo_hook.save(validate: false)

      @repo_hook.partial_config = { "secret" => "my secret stuff" }
      @repo_hook.save!
      @repo_hook.reload
    end

    test "updating a hook with an invalid HookConfigAttribute removes invalid key" do
      @repo_hook.partial_config = { "invalid_key" => "some value" }

      @repo_hook.save(validate: false)

      @repo_hook.partial_config = { "secret" => "my secret stuff" }
      @repo_hook.save!
      @repo_hook.reload

      assert_nil @repo_hook.config_attributes["invalid_key"]
    end

    test "updating a hook with a new invalid HookConfigAttribute fails validation" do
      @repo_hook.partial_config = { "secret" => "my secret stuff", "invalid" => "true" }
      refute @repo_hook.valid?
      assert_includes @repo_hook.errors[:base], "Invalid config attribute: invalid"
    end
  end

  context "#fires_for_event?" do
    test "returns false if there isn't a HookEventSubscription for the event" do
      assert_same_elements ["push"], @repo_hook.subscribed_events
      refute @repo_hook.fires_for_event?("label")
    end

    test "returns true if there is a HookEventSubscription for the event" do
      assert_same_elements ["push"], @repo_hook.subscribed_events
      assert @repo_hook.fires_for_event?("push")
    end

    test "returns true if there is a wildcard HookEventSubscription" do
      @repo_hook.add_events(Hook::WildcardEvent)
      @repo_hook.save
      assert @repo_hook.fires_for_event?("label")
    end

    test "returns false for wildcard events if the Hook::Event is feature flagged" do
      @repo_hook.add_events(Hook::WildcardEvent)
      @repo_hook.save
      refute @repo_hook.fires_for_event?("super_stealth")
    end

    test "returns false for wildcard events if the Hook::Event has feature flagged actions" do
      @repo_hook.add_events(Hook::WildcardEvent)
      @repo_hook.save

      refute @repo_hook.fires_for_event?("partially_exposed", action: :created)
      assert @repo_hook.fires_for_event?("partially_exposed", action: :edited)
    end

    test "returns true if the event is auto_subscribed" do
      refute_includes @repo_hook.events, "ping"
      assert_predicate Hook::Event::PingEvent, :auto_subscribed?

      assert @repo_hook.fires_for_event?("ping")
    end
  end

  context "#toggle_active_status_from_stafftools" do
    test "successfully toggles active status of hook from true to false" do
      @repo_hook.toggle_active_status_from_stafftools(disable_reason: nil)
      refute_predicate @repo_hook, :active?
    end

    test "successfully toggles active status of hook from false to true" do
      disabled_hook = create :hook, :all_events, active: false
      disabled_hook.toggle_active_status_from_stafftools(disable_reason: nil)
      assert_predicate disabled_hook, :active?
    end

    test "hook.active_changed event payload includes disable_reason when disable_reason parameter is NOT nil" do
      events = subscribe "hook.active_changed"
      disable_reason = "some reason for disabling"
      @repo_hook.toggle_active_status_from_stafftools(disable_reason: disable_reason)
      assert event = events.pop, "a hook.active_changed event was expected"
      assert_equal disable_reason, event.payload[:staff_disable_reason]
    end

    test "hook.active_changed event payload does NOT include disable_reason when disable_reason parameter is nil" do
      events = subscribe "hook.active_changed"
      @repo_hook.toggle_active_status_from_stafftools(disable_reason: nil)
      assert event = events.pop, "a hook.active_changed event was expected"
      assert_nil event.payload[:staff_disable_reason]
    end

    context "when hook is disabled via the toggle" do
      test "calls #HookMailer::stafftools_disable_notice to send hook admins an email" do
        HookMailer.expects(:stafftools_disable_notice).once.with(@repo_hook).returns(stub(deliver_later: nil))
        @repo_hook.toggle_active_status_from_stafftools(disable_reason: "some reason")
      end

      test "calls #HookMailer::oauth_hook_stafftools_disable_notice to send oauth app admins an email if hook was created by an oauth_app" do
        oauth_app = create(:oauth_application)
        oauth_app_hook = create :hook, :all_events, oauth_application: oauth_app

        HookMailer.expects(:oauth_hook_stafftools_disable_notice).once.with(oauth_app_hook).returns(stub(deliver_later: nil))
        oauth_app_hook.toggle_active_status_from_stafftools(disable_reason: "some reason")
      end
    end

    context "when is enabled via the toggle" do
      test "calls #HookMailer::stafftools_enable_notice to send hook admins an email" do
        HookMailer.expects(:stafftools_enable_notice).once.with(@disabled_hook).returns(stub(deliver_later: nil))
        @disabled_hook.toggle_active_status_from_stafftools(disable_reason: nil)
      end

      test "calls #HookMailer::oauth_hook_stafftools_enable_notice to send oauth app admins an email if hook was created by an oauth_app" do
        oauth_app = create(:oauth_application)
        oauth_app_hook = create :hook, :all_events, oauth_application: oauth_app, active: false

        HookMailer.expects(:oauth_hook_stafftools_enable_notice).once.with(oauth_app_hook).returns(stub(deliver_later: nil))
        oauth_app_hook.toggle_active_status_from_stafftools(disable_reason: nil)
      end
    end
  end

  context "#owner_name_and_type" do
    test "returns repository name with owner if it is a repo hook" do
      assert_equal "#{@repo_hook.installation_target.nwo} repository", @repo_hook.owner_name_and_type
    end

    test "returns organization name if it is an org hook" do
      assert_equal "#{@org_hook.installation_target.login} organization", @org_hook.owner_name_and_type
    end

    test "returns business name if it is a business hook" do
      assert_equal "#{@business_hook.installation_target.name} enterprise", @business_hook.owner_name_and_type
    end

    test "returns app name with owner if it is an app hook" do
      app_hook = create :hook, installation_target: create(:integration)
      assert_equal "#{app_hook.installation_target.name} app", app_hook.owner_name_and_type
    end

    test "returns sponsors listing owner name if it is a sponsors listing hook" do
      sponsors_listing_hook = create :hook, installation_target: create(:sponsors_listing)
      assert_equal "#{sponsors_listing_hook.installation_target.owner.login} sponsors listing", sponsors_listing_hook.owner_name_and_type
    end

    test "returns marketplace listing name with owner if it is a marketplace listing hook" do
      marketplace_listing_hook = create :hook, installation_target: create(:marketplace_listing)
      assert_equal "#{marketplace_listing_hook.installation_target.slug} marketplace listing", marketplace_listing_hook.owner_name_and_type
    end
  end

  context ".subscribed_to_integrator_event" do
    test "returns a relation" do
      hooks = Hook.subscribed_to_integrator_event("security_advisory")

      assert_kind_of ActiveRecord::Relation, hooks
    end

    test "returns a relation given an invalid integrator event" do
      hooks = Hook.subscribed_to_integrator_event("bogus")

      assert_kind_of ActiveRecord::Relation, hooks
      assert_empty hooks
    end

    test "returns integration hooks that are subscribed to the integrator event" do
      hook = create(:hook, {
        installation_target: create(:integration),
        events: %w(security_advisory),
      })

      hooks = Hook.subscribed_to_integrator_event("security_advisory")

      assert_equal [hook], hooks
    end

    test "ignores integration hooks that are not subscribed to the integrator event" do
      create(:hook, {
        installation_target: create(:integration),
        events: %w(push),
      })

      hooks = Hook.subscribed_to_integrator_event("security_advisory")

      assert_empty hooks
    end

    test "ignores integration hooks that are subscribed to the integrator event but are not active" do
      create(:hook, {
        installation_target: create(:integration),
        events: %w(security_advisory),
        active: false,
      })

      hooks = Hook.subscribed_to_integrator_event("security_advisory")

      assert_empty hooks
    end

    test "optionally limits hooks by installation target id" do
      integration = create(:integration, :with_active_hook, integrator_events: %w(installation_target))
      create(:integration, :with_active_hook, integrator_events: %w(installation_target))

      hook = integration.hook
      hooks = Hook.subscribed_to_integrator_event("installation_target", installation_target_ids: [integration.id])

      assert_equal [hook], hooks
    end
  end

  context "#parent_actor" do
    test "returns a Hook::ParentAsActor class" do
      assert_kind_of Hook::ParentAsActor, @repo_hook.parent_actor
    end

    test "can respond to flipper_id" do
      actor = @repo_hook.parent_actor

      assert_equal "Hook::ParentAsActor:#{@repo_hook.hookshot_parent_id}", actor.flipper_id
    end

    test "memoizes the actor class" do
      original_oid = @repo_hook.parent_actor.object_id
      new_oid = @repo_hook.parent_actor.object_id

      assert_equal original_oid, new_oid
    end
  end

  context "EventAsActor" do
    test "can respond to flipper_id" do
      actor = Hook::EventAsActor.new("registry_package")

      assert_equal "Hook::EventAsActor:registry_package", actor.flipper_id
    end

    test "can toggle feature flag based on EventAsActor" do
      actor = Hook::EventAsActor.new("check_run")
      assert actor.is_a?(GitHub::FlipperActor)
      GitHub.flipper[:hook_event_as_actor].disable(actor)
      refute GitHub.flipper[:hook_event_as_actor].enabled?(actor)
      GitHub.flipper[:hook_event_as_actor].enable(actor)
      assert GitHub.flipper[:hook_event_as_actor].enabled?(actor)
      GitHub.flipper[:hook_event_as_actor].disable(actor)
      refute GitHub.flipper[:hook_event_as_actor].enabled?(actor)
    end
  end

  context "on destroy callbacks" do
    test "attempting to destroy a new hook doesn't blow up" do
      Hook.stubs(:delivers_in_test?).returns(true)
      hook = Hook.new
      assert_nothing_raised do
        hook.destroy
      end
    end
  end

  context "#remove_disallowed_events!" do
    test "does not remove allowed events" do
      hook = create :hook
      hook.events = %w(issue_comment push label)
      hook.remove_disallowed_events
      assert_same_elements %w(issue_comment push label), hook.events
    end

    test "removes disallowed events" do
      hook = create :hook
      hook.events = %w(push fruit_loop_event)
      hook.remove_disallowed_events
      assert_same_elements %w(push), hook.events
    end
  end

  context "#display_name" do
    test "returns the name of the hook" do
      cli_hook = create :hook, :cli
      email_hook = create :hook, :email
      webhook = create :hook, :web

      assert_equal ["GitHub Command Line - #{cli_hook.creator&.name}", "Email", "webhook"],
                   [cli_hook.display_name, email_hook.display_name, webhook.display_name]
    end
  end

  context "on_denylist?" do
    test "returns true if app is on the denylist" do
      integration = create(:integration)
      GitHub.flipper[:webhooks_denylist].enable(integration)
      app_hook = create :hook, installation_target: integration
      assert app_hook.on_denylist?
    end

    test "returns false if denylist feature flag is fully enabled" do
      integration = create(:integration)
      GitHub.flipper[:webhooks_denylist].enable
      app_hook = create :hook, installation_target: integration
      refute app_hook.on_denylist?
    end

    test "returns false if app is not on the denylist" do
      integration = create(:integration)
      app_hook = create :hook, installation_target: integration
      refute app_hook.on_denylist?
    end

    test "returns false if hook is not associated with an integration" do
      app_hook = create :hook, installation_target: @repo
      refute app_hook.on_denylist?
    end
  end

  context "destroy_in_background_with" do
    test "is deleted with repository" do
      GitHub.flipper[:repo_hook_associations].enable

      repo = create(:repository)
      repo_hook = create(:hook, installation_target: repo)
      other_hook = create(:hook, installation_target: create(:repository))

      assert_destroyed_in_background_with_parent do |config|
        config.parent_record = repo
        config.expect_destroyed = [repo_hook]
        config.expect_not_destroyed = [other_hook]
      end
    end
  end
end
