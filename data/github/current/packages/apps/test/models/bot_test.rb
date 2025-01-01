# typed: true
# frozen_string_literal: true

require "test_helper"

class BotTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner

    @admin = create(:user)
    @integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
    @bot = @integration.bot

    @second_integration = create(:integration, name: "complex-ci", default_permissions: { "metadata" => :read })
    @second_bot = @second_integration.bot

    @org = create(:organization, admin: @admin)
    @repo = create(:private_repository, :minimal, owner: @org)
  end

  context ".find_by_token" do
    test "returns nil when no bot exists with the given token" do
      assert_nil Bot.find_by_token("bogus")
    end

    test "returns nil when given a nil token" do
      assert_nil Bot.find_by_token(nil)
    end

    test "sends a stat when the token is cannot be found" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      assert_nil Bot.find_by_token("bogus")

      assert_equal 1, stats.increments("bot.find_by_token").length, "expected a bot.find_by_token event"
      assert_same_elements ["result:failure", "missing:token"], stats.increments("bot.find_by_token").first.tags
    end

    test "sends a stat when the authenticatable cannot be found" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      Timecop.freeze do
        installation = make_integration_installation(integration: @integration, repository: @repo)
        token        = installation.generate_token

        # skip the ActiveRecord callbacks
        installation.delete

        assert_nil Bot.find_by_token(token)

        assert_equal 1, stats.increments("bot.find_by_token").length, "expected a bot.find_by_token event"
        assert_same_elements ["result:failure", "missing:authenticatable"], stats.increments("bot.find_by_token").first.tags
      end
    end

    test "returns bot without reading from primary if found on replica" do
      Bot.expects(:bot_read_from_collab_primary).never

      parent       = make_integration_installation(integration: @integration, repository: @repo)
      installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
      token        = installation.generate_token

      Bot.find_by_token(token)
    end

    test "checks primary on collab when ScopeIntegrationInstallation not found on replica" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      Timecop.freeze do
        parent       = make_integration_installation(integration: @integration, repository: @repo)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
        token        = installation.generate_token

        AuthenticationToken.any_instance.stubs(:authenticatable).returns(nil)

        bot = Bot.find_by_token(token)
        assert_equal @integration.bot, bot
        assert_equal installation, bot.installation
        assert_equal 1, stats.increments("bot.find_by_token").length, "expected a bot.find_by_token event"
        assert_same_elements ["result:success", "check_primary:true", "token_type:bot"], stats.increments("bot.find_by_token").first.tags
      end
    end

    test "loads the parent from primary if it's missing" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      Timecop.freeze do
        parent       = make_integration_installation(integration: @integration, repository: @repo)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
        token        = installation.generate_token

        parent.delete; installation.reload
        assert_nil installation.parent, "expected the parent to be missing"

        dummy_parent = make_integration_installation(integration: @integration, repository: @repo)
        IntegrationInstallation.expects(:find_by).with(id: installation.integration_installation_id).returns(dummy_parent)

        bot = Bot.find_by_token(token)
        assert_equal dummy_parent, bot.installation.parent

        assert_equal 1, stats.increments("bot.find_by_token").length, "expected a bot.find_by_token event"
        assert_same_elements ["result:success", "missing_parent:true", "token_type:authenticatable"], stats.increments("bot.find_by_token").first.tags
      end
    end

    # https://github.com/github/ecosystem-apps/issues/858
    test "instruments failures during explicit lookup from primary" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      Timecop.freeze do
        parent       = make_integration_installation(integration: @integration, repository: @repo)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
        token        = installation.generate_token

        AuthenticationToken.any_instance.stubs(:authenticatable).returns(nil)

        # For some reason, the installation is not found in the primary:
        installation.delete

        assert_nil Bot.find_by_token(token)

        assert_equal 1, stats.increments("bot.find_by_token").length, "expected a bot.find_by_token event"
        expected_tags = ["check_primary:true", "primary_lookup:failed", "missing:authenticatable", "result:failure"]
        assert_same_elements expected_tags, stats.increments("bot.find_by_token").first.tags
      end
    end

    context "IntegrationInstallation" do
      test "returns the bot associated with the given token" do
        installation = make_integration_installation(integration: @integration, repository: @repo)
        token        = installation.generate_token

        bot = Bot.find_by_token(token)
        assert_equal @integration.bot, bot
        assert_equal installation, bot.installation
      end

      # https://github.com/github/github/issues/111313
      test "returns nil if authenticatable is no longer present" do
        installation = make_integration_installation(integration: @integration, repository: @repo)
        token        = installation.generate_token

        installation.delete
        assert_predicate AuthenticationToken.with_unhashed_token(token), :any?

        assert_nil Bot.find_by_token(token)
      end

      test "doesn't return expired tokens" do
        version = @integration.versions.create(default_permissions: { contents: :read })
        installation = @integration.install_on(
          @org,
          repositories: [@repo],
          version: version,
          installer: @admin,
          entry_point: :test_case
        ).installation

        token_creation_time = "2016/01/14 00:13:00Z"
        token = T.let(nil, T.nilable(AuthenticationToken))
        Timecop.freeze(Time.parse(token_creation_time)) do
          _, token = AuthenticationToken.create_for(installation)
        end

        # 1 minute *before* token expires
        Timecop.freeze(Time.parse("2016/01/14 01:12:00Z")) do
          assert_equal installation.bot, Bot.find_by_token(token)
        end

        # 1 minute *after* token expires
        Timecop.freeze(Time.parse("2016/01/14 01:14:00Z")) do
          assert_nil Bot.find_by_token(token)
        end
      end

      test "returns nil if the Integration is missing" do
        installation = make_integration_installation(integration: @integration, repository: @repo)
        token        = installation.generate_token

        @integration.delete

        installation.reload
        assert_nil installation.integration

        assert_nil Bot.find_by_token(token)
      end
    end

    context "ScopedIntegrationInstallation" do
      test "returns the bot associated with the given token" do
        parent       = make_integration_installation(integration: @integration, repository: @repo)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
        token        = installation.generate_token

        bot = Bot.find_by_token(token)
        assert_equal @integration.bot, bot
        assert_equal installation, bot.installation
      end

      test "returns nil if the Integration is missing" do
        parent       = make_integration_installation(integration: @integration, repository: @repo)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
        token        = installation.generate_token

        @integration.delete

        assert_nil Bot.find_by_token(token)
      end
    end

    context "SiteScopedIntegrationInstallation" do
      test "returns the bot associated with the given token" do
        GitHub.flipper[:disabled_global_apps].disable
        integration = create_unlimited_global_integration

        installation = make_site_scoped_integration_installation(
          integration: integration,
          target: @org,
          repositories: [@repo],
        )
        token = installation.generate_token

        bot = Bot.find_by_token(token)
        assert_equal integration.bot, bot
        assert_equal installation, bot.installation
      end

      test "returns nil if the Integration is missing" do
        GitHub.flipper[:disabled_global_apps].disable
        integration = create_unlimited_global_integration

        installation = make_site_scoped_integration_installation(
          integration: integration,
          target: @org,
          repositories: [@repo],
        )
        token = installation.generate_token

        integration.delete

        assert_nil Bot.find_by_token(token)
      end
    end
  end

  context "validation" do
    test "does not require email" do
      bot = Bot.new(login: "app-bot")
      bot.valid?

      assert bot.errors[:email].blank?
    end

    test "does not require a password" do
      bot = Bot.new(login: "app-bot")
      bot.valid?

      assert bot.errors[:password].blank?
    end

    test "requires a login" do
      bot = Bot.new
      bot.valid?

      refute bot.errors[:login].blank?
    end

    test "login must be suffixed with '[bot]' when :owner_scoped_github_apps is disabled" do
      GitHub.flipper[:owner_scoped_github_apps].disable
      bot = Bot.new(login: "code-checker[bot]")
      bot.valid?
      assert bot.errors[:login].blank?

      bot = Bot.new(login: "code-checker")
      bot.valid?
      refute bot.errors[:login].blank?
    end

    test "login is not suffixed with '[bot]' when :owner_scoped_github_apps is enabled" do
      GitHub.flipper[:owner_scoped_github_apps].enable
      integration = create(:integration)
      bot = Bot.new(login: "code-checker[bot]", integration: integration)
      bot.valid?
      assert bot.errors[:login].blank?

      bot = Bot.new(login: "code-checker", integration: integration)
      bot.valid?
      assert bot.errors[:login].blank?
    end

    test "login must be under 39 chars" do
      too_long_str = "r" * (Bot::MAX_SLUG_LENGTH + 1)
      bot = Bot.new(login: "#{too_long_str}[bot]")
      bot.valid?

      refute bot.errors[:login].blank?
    end

    test "requires an integration" do
      bot = Bot.new(login: "app-bot[bot]", integration: nil)

      refute bot.valid?
      refute bot.errors[:integration].blank?

      bot.integration = @integration
      assert bot.valid?
    end
  end

  if GitHub.spamminess_check_enabled?
    test "preemptively_safelist" do
      assert_predicate @bot, :hammy?
    end
  end

  test "#github_owned? return true for GitHub" do
    integration = create(:integration, name: "github-ci", owner: GitHub.trusted_oauth_apps_owner, default_permissions: { "metadata" => :read })
    bot = integration.bot
    assert_predicate bot, :github_owned?
  end

  test "does not need a verified email address in order to create content" do
    GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
    refute_predicate @bot, :require_email_verification?
    refute_predicate @bot, :content_creation_requires_email_verification?
  end

  context "#primary_avatar_path" do
    test "shares the same primary_avatar_path as the integration" do
      assert_equal @bot.primary_avatar_path, @integration.primary_avatar_path
    end

    test "returns a default avatar when the integration does not exist" do
      integration = create(:integration, default_permissions: { "metadata" => :read })
      bot = integration.bot

      integration.delete

      # Re-fetch Bot to dump memoized value for primary_avatar_path
      bot = Bot.find(bot.id)

      assert_nil bot.integration
      assert_equal Integration.new.primary_avatar_path, bot.primary_avatar_path
    end
  end

  context "#primary_avatar_url" do
    test "returns url from primary_avatar_path", feature_disabled: :proxima_synced_avatar_url do
      assert_nil @bot.integration.canonical_avatar_url
      assert_includes @bot.primary_avatar_url, @bot.primary_avatar_path
    end

    test "returns canonical_avatar_url for Proxima synced apps", feature_enabled: :proxima_synced_avatar_url do
      integration = create(:synchronized_integration)
      assert ProximaAppSynchronization.synchronized?(integration)
      assert_equal integration.canonical_avatar_url, integration.bot.primary_avatar_url
    end if TestEnv.test_in_multitenancy_mode?
  end

  context "repository abilities" do
    test "permit repository action specified in the bot's current installation context" do
      org_a = create(:organization, login: "org-a")
      org_b = create(:organization, login: "org-b")
      repo_a = create(:private_repository, :minimal, owner: org_a, name: "a")
      repo_b = create(:private_repository, :minimal, owner: org_b, name: "b")

      integration = create(:integration, default_permissions: { "contents" => :read })
      installation_on_org_a = integration.install_on(
        org_a,
        repositories: [repo_a],
        installer: org_a.admins.first,
        entry_point: :test_case
      ).installation
      installation_on_org_b = integration.install_on(
        org_b,
        repositories: [repo_b],
        installer: org_b.admins.first,
        entry_point: :test_case
      ).installation

      assert_able installation_on_org_a.bot, :read, repo_a.resources.contents
      refute_able installation_on_org_b.bot, :read, repo_a.resources.contents

      refute_able installation_on_org_a.bot, :read, repo_b.resources.contents
      assert_able installation_on_org_b.bot, :read, repo_b.resources.contents
    end

    test "do not permit privileged repository action for a bot without a current installation context" do
      org = create(:organization)
      repo = create(:private_repository, :minimal, owner: org)
      integration = create(:integration, default_permissions: { "contents" => :read })
      integration.install_on(
        org,
        repositories: [repo],
        installer: org.admins.first,
        entry_point: :test_case
      )

      bot = integration.bot
      assert_nil bot.installation
      refute_able bot, :read, repo.resources.contents
    end
  end

  context "#associated_repository_ids" do
    test "gracefully accepts all arguments supported by method defined in superclass" do
      assert_empty @bot.associated_repository_ids(
        min_action: nil, including: nil, include_oauth_restriction: true, include_indirect_forks: true, include_oopfs: true,
      )
    end

    test "returns IDs for the repositories included in the bot's current installation context" do
      org_a = create(:organization, login: "org-a")
      org_b = create(:organization, login: "org-b")
      repo_a = create(:private_repository, :minimal, owner: org_a, name: "a")
      repo_b = create(:private_repository, :minimal, owner: org_b, name: "b")

      integration = create(:integration, default_permissions: { "metadata" => :read })
      installation_on_org_a = integration.install_on(
        org_a,
        repositories: [repo_a],
        installer: org_a.admins.first,
        entry_point: :test_case,
      ).installation
      installation_on_org_b = integration.install_on(
        org_b,
        repositories: [repo_b],
        installer: org_b.admins.first,
        entry_point: :test_case
      ).installation

      assert_same_elements [repo_a.id], installation_on_org_a.bot.associated_repository_ids
      assert_same_elements [repo_b.id], installation_on_org_b.bot.associated_repository_ids
    end

    test "returns an empty list for a bot without a current installation context" do
      org = create(:organization)
      repo = create(:private_repository, :minimal, owner: org)
      integration = create(:integration)
      integration.install_on(
        org,
        repositories: [repo],
        installer: org.admins.first,
        entry_point: :test_case
      )

      bot = integration.bot
      assert_nil bot.installation
      assert_empty bot.associated_repository_ids
    end

    test "can limit repositories based on the given ability action type" do
      version = @integration.versions.create(default_permissions: { "statuses" => :write })
      installation = @integration.install_on(
        @org,
        repositories: [@repo],
        version: version,
        installer: @admin,
        entry_point: :test_case
      ).installation
      bot = installation.bot

      assert_same_elements [@repo.id], bot.associated_repository_ids(min_action: :read)
      assert_same_elements [@repo.id], bot.associated_repository_ids(min_action: :write)
      assert_empty bot.associated_repository_ids(min_action: :admin)
    end

    test "limits results to repositories the bot has access to the specified resource on" do
      @integration.update(default_permissions: { "issues" => :read })
      @integration.reload

      installation = @integration.install_on(
        @org,
        repositories: [@repo],
        installer: @admin,
        entry_point: :test_case
      ).installation
      bot = installation.bot

      assert_same_elements [@repo.id], bot.associated_repository_ids(resource: "issues")
    end

    test "excludes repositories the bot does not have access to the specified resource on" do
      @integration.update(default_permissions: { "issues" => :read })

      installation = @integration.install_on(
        @org,
        repositories: [@repo],
        installer: @admin,
        entry_point: :test_case
      ).installation
      bot = installation.bot

      assert_empty bot.associated_repository_ids(resource: "statuses")
    end
  end

  context "#async_load_installation_for" do
    test "loads and sets the installation for a resource" do
      installation = @integration.install_on(
        @org,
        repositories: [@repo],
        installer: @admin,
        entry_point: :test_case
      ).installation
      bot = @integration.bot
      assert_nil bot.installation

      bot.async_load_installation_for(@repo).sync
      assert_equal installation, bot.installation
    end
  end

  context "#ability_delegate" do
    test "returns the current installation" do
      installation = @integration.install_on(
        @org,
        repositories: [@repo],
        installer: @admin,
        entry_point: :test_case
      ).installation
      bot = installation.bot

      assert_equal installation, bot.ability_delegate
    end

    test "returns nil if there is no installation" do
      bot = Bot.new
      assert_nil bot.ability_delegate
    end
  end

  test "#slug returns the login minus the login suffix" do
    assert_equal "simple-ci", @bot.slug
  end

  test "#display_login_legacy returns the slug" do
    assert_equal @bot.slug, @bot.display_login_legacy
  end

  test "#display_login returns the integration slug + LOGIN_SUFFIX" do
    assert_equal "#{@bot.slug}#{Bot::LOGIN_SUFFIX}", @bot.display_login
  end

  test "#safe_profile_name returns the display_login" do
    assert_equal @bot.display_login, @bot.safe_profile_name
  end

  test "#permalink returns bot slug with apps prefix" do
    prefix = GitHub.enterprise? ? "github-apps" : "apps"
    assert_equal "/#{prefix}/simple-ci", @bot.permalink(include_host: false)
  end

  context "#to_param" do
    test "#to_param returns bot slug with apps prefix" do
      prefix = GitHub.enterprise? ? "github-apps" : "apps"
      assert_equal "#{prefix}/simple-ci", @bot.to_param
    end

    # https://github.com/github/ecosystem-apps/issues/4909
    #
    # #to_param explodes because #slug is expecting the Bot's login to match an
    # old-style regex pattern relating to the app's slug, which doesn't happen
    # with new-style bots that have been given random logins to prevent name
    # collisions.
    test "new-style bots can deal with :owner_scoped_github_apps flag being subsequently disabled" do
      GitHub.flipper[:owner_scoped_github_apps].enable
      app = create(:integration)
      GitHub.flipper[:owner_scoped_github_apps].disable

      assert_nothing_raised do
        app.bot.to_param
      end

      prefix = GitHub.enterprise? ? "github-apps" : "apps"
      assert_equal "#{prefix}/#{app.slug}", app.bot.to_param
    end

    # https://github.com/github/ecosystem-apps/issues/4909
    #
    # #to_param explodes because #slug delegates to the bot's integration,
    # which (for some reason - probably a separate issue) has been deleted,
    # while the bot still exists.
    test "orphaned legacy bots can handle #to_param when :owner_scoped_github_apps flag is enabled" do
      GitHub.flipper[:owner_scoped_github_apps].disable
      app = create(:integration)
      bot = app.bot

      app.delete # Ensure the integration is deleted while leaving the Bot orphaned.
      assert_predicate bot.reload, :persisted?

      GitHub.flipper[:owner_scoped_github_apps].enable
      assert_nothing_raised do
        bot.to_param
      end

      prefix = GitHub.enterprise? ? "github-apps" : "apps"
      assert_equal "#{prefix}/#{bot.slug}", bot.to_param
    end

    # https://github.com/github/ecosystem-apps/issues/4909
    #
    # In this case, a new-style bot, with a randomly generated login value, is
    # created and subsequently orphaned, meaning its associated integration is
    # no longer available to provide the context for #to_param.
    #
    # Unfortunately we have zero record of the bot's association with its
    # integration record, so we just have to fall back to the randomly
    # generated login, which will produce a 404 when rendered as a link, but
    # there's nothing else we can do.
    test "orphaned new-style bots can handle #to_param when :owner_scoped_github_apps flag is enabled" do
      GitHub.flipper[:owner_scoped_github_apps].enable
      app = create(:integration)
      bot = app.bot

      app.delete # Ensure the integration is deleted while leaving the Bot orphaned.
      assert_predicate bot.reload, :persisted?

      assert_nothing_raised do
        bot.to_param
      end

      prefix = GitHub.enterprise? ? "github-apps" : "apps"
      assert_equal "#{prefix}/#{bot.login}", bot.to_param
    end

    # https://github.com/github/ecosystem-apps/issues/4909
    #
    # In this case, a new-style bot, with a randomly generated login value, is
    # created and subsequently orphaned, meaning its associated integration is
    # no longer available to provide the context for #to_param.
    #
    # Further complicating matters is the fact that the
    # owner_scoped_github_apps feature flag is now disabled but there's nothing
    # we can really do here because this type of bot has no record of its
    # previous identity via its parent app, so we create a param that will
    # ultimately 404 (E.g. apps/<random Hex login>), but there's not much else
    # we can do here.
    test "orphaned new-style bots can handle #to_param when :owner_scoped_github_apps flag is subsequently disabled" do
      GitHub.flipper[:owner_scoped_github_apps].enable
      app = create(:integration)
      bot = app.bot
      GitHub.flipper[:owner_scoped_github_apps].disable

      app.delete # Ensure the integration is deleted while leaving the Bot orphaned.
      assert_predicate bot.reload, :persisted?

      assert_nothing_raised do
        bot.to_param
      end

      prefix = GitHub.enterprise? ? "github-apps" : "apps"
      assert_equal "#{prefix}/#{bot.login}", bot.to_param
    end

    test "when all-else fails, doesn't explode" do
      bot = Bot.new

      assert_nothing_raised do
        bot.to_param
      end

      assert_equal "", bot.to_param
    end
  end

  context "#marketplace_listing_or_app_path" do
    if GitHub.enterprise?
      test "still returns 'github-apps/' if the bot has a marketplace listing" do
        integration = create(:integration, name: "app-on-enterprise")
        _listing = create(
          :marketplace_listing,
          :verified,
          :integration,
          name: "not-this-name",
          listable: integration,
        )
        bot = integration.bot

        assert_equal "/github-apps/app-on-enterprise", bot.marketplace_listing_or_app_path
      end
    else
      test "returns 'marketplace/' and bot's marketplace listing slug if it has an approved listing" do
        integration = create(:integration, name: "not-this-name")
        _listing = create(
          :marketplace_listing,
          :verified,
          :integration,
          name: "but-this-name",
          listable: integration,
        )
        bot = integration.bot

        assert_equal "/marketplace/but-this-name", bot.marketplace_listing_or_app_path
      end

      test "returns 'apps/' and the bot slug if the bot's marketplace listing has not been approved" do
        integration = create(:integration, name: "bot-name")
        _listing = create(
          :marketplace_listing,
          :draft,
          :integration,
          name: "draft-listing",
          listable: integration,
        )
        bot = integration.bot

        assert_equal "/apps/bot-name", bot.marketplace_listing_or_app_path
      end
    end
  end

  test "#to_s returns the slug" do
    assert_equal @bot.slug, @bot.to_s
  end

  test "#name returns the slug" do
    assert_equal @bot.slug, @bot.name
  end

  context ".find_by_emails" do
    test "returns bots associated with given emails" do
      emails = [
        "#{@bot.id}+#{@bot.slug}[bot]@#{GitHub.stealth_email_host_name}",
        "#{@second_bot.slug}[bot]@#{GitHub.stealth_email_host_name}",
      ]

      hash = Bot.find_by_emails(emails)

      assert_equal @bot, hash[emails.first]
      assert_equal @second_bot, hash[emails.second]
    end

    test "returns {} if no matches" do
      hash = Bot.find_by_emails(["d12[bot]@users.noreply.github.com"])

      assert_equal({}, hash)
    end

    test "does not return non-bot users" do
      hash = Bot.find_by_emails([@admin.email])

      assert_equal({}, hash)
    end
  end

  context ".find_by_email" do
    test "finds a Bot when email matches a Bot ID" do
      email = "#{@bot.id}+#{@bot.display_login}@#{GitHub.stealth_email_host_name}"
      assert_equal @bot, Bot.find_by_email(email)
    end

    test "finds a Bot when email matches a Bot login" do
      email = "#{@bot.display_login}@#{GitHub.stealth_email_host_name}"
      assert_equal @bot, Bot.find_by_email(email)
    end

    test "returns nil when email doesn't match a Bot login" do
      email = "regular@users.noreply.github.com"

      assert_nil Bot.find_by_email(email)
    end

    test "returns nil when no Bot is found with matching login" do
      email = "acme[bot]@users.noreply.github.com"

      assert_nil Bot.find_by_email(email)
    end

    test "returns nil when no Bot is found with an email containing a non-existent Bot ID" do
      unlikely_id = "9999999999999999"
      email = "#{unlikely_id}+#{@bot.display_login}@#{GitHub.stealth_email_host_name}"
      assert_nil Bot.find_by_email(email)
    end

    test "tenant slug for avatar in empty" do
      assert_equal "", @bot.tenant_slug_for_avatar
    end
  end
end

class MultiTenantBotTest < GitHub::TestCase
  fixtures do
    @first_party_app = create(:integration)
    @first_party_app_owner = @first_party_app.owner
    @first_party_app_bot = @first_party_app.bot

    on_multi_tenant_enterprise do
      @user = @admin = create :emu
      @business = @user.enterprise_managed_business

      @integration = create(:integration, owner: @user)
      @bot = @integration.bot

      @org = create(:organization, admin: @user)
      @repo = create(:private_repository, :minimal, owner: @org)
    end
  end

  setup do
    on_multi_tenant_enterprise
    GitHub::CurrentTenant.set(@business)
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  context "#business_id" do
    test "is set to the owner's business_id" do
      integration = create(:integration, owner: @user)
      bot = integration.bot
      assert_equal @business.id, @user.business_id
      assert_equal @business.id, bot.business_id
    end
  end

  context "default scope" do
    test "includes Bots from the global application" do
      bot = @first_party_app_bot
      refute_equal bot.business_id, GitHub::CurrentTenant.get.id

      result = Bot.where(login: bot.login)

      assert_equal 1, result.count
      assert_equal bot, result.first
    end
  end

  test "#scope_to_current_tenant?" do
    assert_predicate Bot, :scope_to_current_tenant?
  end

  context ".find_by_token" do
    test "returns bot for same tenant" do
      parent       = make_integration_installation(integration: @integration, repository: @repo)
      installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
      token        = installation.generate_token

      bot = Bot.find_by_token(token)
      assert_equal @bot, bot
    end

    test "returns nil when authenticating as bot belonging to another tenant" do
      parent       = make_integration_installation(integration: @integration, repository: @repo)
      installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
      token        = installation.generate_token

      GitHub::CurrentTenant.set(create(:business)) do
        assert_nil Bot.find_by_token(token)
      end
    end

    test "returns nil when no bot exists with the given token" do
      assert_nil Bot.find_by_token("bogus")
    end

    test "returns nil when given a nil token" do
      assert_nil Bot.find_by_token(nil)
    end

    test "sends a stat when the token is cannot be found" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      assert_nil Bot.find_by_token("bogus")

      assert_equal 1, stats.increments("bot.find_by_token").length, "expected a bot.find_by_token event"
      assert_same_elements ["result:failure", "missing:token"], stats.increments("bot.find_by_token").first.tags
    end

    test "sends a stat when the authenticatable cannot be found" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      Timecop.freeze do
        installation = make_integration_installation(integration: @integration, repository: @repo)
        token        = installation.generate_token

        # skip the ActiveRecord callbacks
        installation.delete

        assert_nil Bot.find_by_token(token)

        assert_equal 1, stats.increments("bot.find_by_token").length, "expected a bot.find_by_token event"
        assert_same_elements ["result:failure", "missing:authenticatable"], stats.increments("bot.find_by_token").first.tags
      end
    end

    test "returns bot without reading from primary if found on replica" do
      Bot.expects(:bot_read_from_collab_primary).never

      parent       = make_integration_installation(integration: @integration, repository: @repo)
      installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
      token        = installation.generate_token

      Bot.find_by_token(token)
    end

    test "checks primary on collab when ScopeIntegrationInstallation not found on replica" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      Timecop.freeze do
        parent       = make_integration_installation(integration: @integration, repository: @repo)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
        token        = installation.generate_token

        AuthenticationToken.any_instance.stubs(:authenticatable).returns(nil)

        bot = Bot.find_by_token(token)
        assert_equal @integration.bot, bot
        assert_equal installation, bot.installation
        assert_equal 1, stats.increments("bot.find_by_token").length, "expected a bot.find_by_token event"
        assert_same_elements ["result:success", "check_primary:true", "token_type:bot"], stats.increments("bot.find_by_token").first.tags
      end
    end

    test "loads the parent from primary if it's missing" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      Timecop.freeze do
        parent       = make_integration_installation(integration: @integration, repository: @repo)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
        token        = installation.generate_token

        parent.delete; installation.reload
        assert_nil installation.parent, "expected the parent to be missing"

        dummy_parent = make_integration_installation(integration: @integration, repository: @repo)
        IntegrationInstallation.expects(:find_by).with(id: installation.integration_installation_id).returns(dummy_parent)

        bot = Bot.find_by_token(token)
        assert_equal dummy_parent, bot.installation.parent

        assert_equal 1, stats.increments("bot.find_by_token").length, "expected a bot.find_by_token event"
        assert_same_elements ["result:success", "missing_parent:true", "token_type:authenticatable"], stats.increments("bot.find_by_token").first.tags
      end
    end

    # https://github.com/github/ecosystem-apps/issues/858
    test "instruments failures during explicit lookup from primary" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      Timecop.freeze do
        parent       = make_integration_installation(integration: @integration, repository: @repo)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
        token        = installation.generate_token

        AuthenticationToken.any_instance.stubs(:authenticatable).returns(nil)

        # For some reason, the installation is not found in the primary:
        installation.delete

        assert_nil Bot.find_by_token(token)

        assert_equal 1, stats.increments("bot.find_by_token").length, "expected a bot.find_by_token event"
        expected_tags = ["check_primary:true", "primary_lookup:failed", "missing:authenticatable", "result:failure"]
        assert_same_elements expected_tags, stats.increments("bot.find_by_token").first.tags
      end
    end

    context "IntegrationInstallation" do
      test "returns the bot associated with the given token" do
        installation = make_integration_installation(integration: @integration, repository: @repo)
        token        = installation.generate_token

        bot = Bot.find_by_token(token)
        assert_equal @integration.bot, bot
        assert_equal installation, bot.installation
      end

      # https://github.com/github/github/issues/111313
      test "returns nil if authenticatable is no longer present" do
        installation = make_integration_installation(integration: @integration, repository: @repo)
        token        = installation.generate_token

        installation.delete
        assert_predicate AuthenticationToken.with_unhashed_token(token), :any?

        assert_nil Bot.find_by_token(token)
      end

      test "doesn't return expired tokens" do
        version = @integration.versions.create(default_permissions: { contents: :read })
        installation = @integration.install_on(
          @org,
          repositories: [@repo],
          version: version,
          installer: @admin,
          entry_point: :test_case
        ).installation

        token_creation_time = "2016/01/14 00:13:00Z"
        token = T.let(nil, T.nilable(AuthenticationToken))
        Timecop.freeze(Time.parse(token_creation_time)) do
          _, token = AuthenticationToken.create_for(installation)
        end

        # 1 minute *before* token expires
        Timecop.freeze(Time.parse("2016/01/14 01:12:00Z")) do
          assert_equal installation.bot, Bot.find_by_token(token)
        end

        # 1 minute *after* token expires
        Timecop.freeze(Time.parse("2016/01/14 01:14:00Z")) do
          assert_nil Bot.find_by_token(token)
        end
      end

      test "returns nil if the Integration is missing" do
        installation = make_integration_installation(integration: @integration, repository: @repo)
        token        = installation.generate_token

        @integration.delete

        installation.reload
        assert_nil installation.integration

        assert_nil Bot.find_by_token(token)
      end
    end

    context "ScopedIntegrationInstallation" do
      test "returns the bot associated with the given token" do
        parent       = make_integration_installation(integration: @integration, repository: @repo)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
        token        = installation.generate_token

        bot = Bot.find_by_token(token)
        assert_equal @integration.bot, bot
        assert_equal installation, bot.installation
      end

      test "returns nil if the Integration is missing" do
        parent       = make_integration_installation(integration: @integration, repository: @repo)
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo])
        token        = installation.generate_token

        @integration.delete

        assert_nil Bot.find_by_token(token)
      end
    end

    context "SiteScopedIntegrationInstallation" do
      test "returns the bot associated with the given token" do
        GitHub.flipper[:disabled_global_apps].disable
        integration = create_unlimited_global_integration

        installation = make_site_scoped_integration_installation(
          integration: integration,
          target: @org,
          repositories: [@repo],
        )
        token = installation.generate_token

        bot = Bot.find_by_token(token)
        assert_equal integration.bot, bot
        assert_equal installation, bot.installation
      end

      test "returns nil if the Integration is missing" do
        GitHub.flipper[:disabled_global_apps].disable
        integration = create_unlimited_global_integration

        installation = make_site_scoped_integration_installation(
          integration: integration,
          target: @org,
          repositories: [@repo],
        )
        token = installation.generate_token

        integration.delete

        assert_nil Bot.find_by_token(token)
      end
    end
  end

  context "#tenant_slug_for_avatar" do
    test "returns company specific entity if `enterprise_managed_business` is nil" do
      bot = create :bot
      assert_equal GitHub.company_specific_entity_acronym, bot.tenant_slug_for_avatar
    end

    test "return business slug if bot belongs to tenant" do
      bot = create :bot
      @business.user_accounts.create(user_id: bot.id)
      assert_equal @business.slug, bot.tenant_slug_for_avatar
    end
  end
end unless GitHub.single_business_environment?
