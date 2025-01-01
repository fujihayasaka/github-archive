# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationBypassActorTest < GitHub::TestCase
  include GpgKeyHelper

  fixtures do
    make_trusted_oauth_apps_owner
    @merge_queue_bot = create(:merge_queue_integration)

    @business_owner = create(:user)
    @business = create(:business, owners: [@business_owner])

    @org = create(:business_plus_organization, business: @business)
    @org_repo = create(:repository, owner: @org)
    @signing_key = create_gpg_key
    @key_user = @signing_key.user
    @org_repo.add_member(@key_user, action: :write)
    @bot = create(:integration, owner: @key_user).bot
    make_integration_installation(integration: @bot.integration, repository: @org_repo, permissions: { "contents" => :write })

    @ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: @ruleset)
  end

  test "create via type" do
    bypasser = RepositoryRulesetBypassActor.create(type: "IntegrationBypassActor", actor: @bot.integration, repository_ruleset: @ruleset)
    assert bypasser.is_a?(IntegrationBypassActor)
    assert_predicate bypasser, :valid?
    assert_equal bypasser.actor_type, "Integration"
    assert_equal "IntegrationBypassActor", bypasser.type
    bypasser.save!
  end

  test "create bypass actor" do
    bypasser = IntegrationBypassActor.create(actor: @bot.integration, repository_ruleset: @ruleset)

    assert_equal bypasser.actor_id, @bot.integration.id
    assert_predicate bypasser, :valid?
    assert_equal bypasser.actor_type, "Integration"
    assert_equal "IntegrationBypassActor", bypasser.type
  end

  test "suggest and validate" do
    bypassers = IntegrationBypassActor.suggest_bypassers(@org_repo, nil)
    if @org_repo.merge_queue_bot_bypass_enabled?
      assert_equal 2, bypassers.size

      merge_queue_bypasser = T.must(bypassers.first)
      assert_equal IntegrationBypassActor, merge_queue_bypasser.class
      assert_equal "Integration", merge_queue_bypasser.class.display_type
      assert_equal "Integration", merge_queue_bypasser.class.display_name
      assert_equal @merge_queue_bot.name, merge_queue_bypasser.actor_name
      assert_equal "IntegrationBypassActor", merge_queue_bypasser.type

      merge_queue_bypasser.repository_ruleset = @ruleset
      assert merge_queue_bypasser.valid?
      merge_queue_bypasser.save!
    else
      assert_equal 1, bypassers.size
    end

    other_bypasser = T.must(bypassers.last)
    assert_equal IntegrationBypassActor, other_bypasser.class
    assert_equal "Integration", other_bypasser.class.display_type
    assert_equal "Integration", other_bypasser.class.display_name
    assert_equal @bot.name, other_bypasser.actor_name
    assert_equal "IntegrationBypassActor", other_bypasser.type

    other_bypasser.repository_ruleset = @ruleset
    assert other_bypasser.valid?
    other_bypasser.save!
  end

  test "allowed_bypass_modes" do
    @ruleset.bypass_actors << IntegrationBypassActor.new(actor: @bot.integration, bypass_mode: 0)
    @ruleset.save!

    rando = create(:user)
    repo_user = create(:user)
    @org_repo.add_member(repo_user, action: :admin)

    assert_equal [], IntegrationBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, rando, @org_repo)
    assert_equal [], IntegrationBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, repo_user, @org_repo)
    assert_equal [], IntegrationBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @org.admins.first, @org_repo)
    assert_equal [0], IntegrationBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @bot, @org_repo)

    @ruleset.bypass_actors.first.bypass_mode = 1
    @ruleset.bypass_actors.first.save!
    assert_equal [], IntegrationBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, rando, @org_repo)
    assert_equal [], IntegrationBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, repo_user, @org_repo)
    assert_equal [], IntegrationBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @org.admins.first, @org_repo)
    assert_equal [1], IntegrationBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @bot, @org_repo)
  end

  test "missing integration does not raise" do
    @ruleset.bypass_actors << IntegrationBypassActor.new(actor: @bot.integration, bypass_mode: 0)
    @ruleset.save!

    refute_nil @ruleset.bypass_actors.first.actor_name
    refute_nil @ruleset.bypass_actors.first.actor_preferred_avatar_url

    assert_equal [0], IntegrationBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @bot, @org_repo)

    @bot.integration.delete
    @bot.reload
    assert_nil @ruleset.reload.bypass_actors.first.actor_name
    assert_nil @ruleset.bypass_actors.first.actor_preferred_avatar_url

    assert_equal [], IntegrationBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @bot, @org_repo)

    bot2 = create(:integration, owner: @key_user).bot
    make_integration_installation(integration: bot2.integration, repository: @org_repo, permissions: { "contents" => :write })
    assert_equal [], IntegrationBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, bot2, @org_repo)
  end
end
