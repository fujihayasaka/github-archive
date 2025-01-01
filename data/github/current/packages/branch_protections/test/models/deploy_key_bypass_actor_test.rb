# typed: true
# frozen_string_literal: true

require "test_helper"

class DeployKeyBypassActorTest < GitHub::TestCase
  fixtures do
    @business_owner = create(:user)
    @business = create(:business, owners: [@business_owner])

    @org = create(:business_plus_organization, business: @business)
    @org_repo = create(:repository, owner: @org)
    @org_repo2 = create(:repository, owner: @org)
    @ruleset = create(:repository_ruleset, :example_ruleset, name: "testing", source: @org)
  end

  test "create via type" do
    bypasser = RepositoryRulesetBypassActor.create(type: "DeployKeyBypassActor", repository_ruleset: @ruleset)
    assert bypasser.is_a?(DeployKeyBypassActor)
    assert_predicate bypasser, :valid?
    assert_equal "DeployKey", bypasser.actor_type
    assert_equal "DeployKeyBypassActor", bypasser.type
    bypasser.save!
  end

  test "create bypass actor" do
    bypasser = DeployKeyBypassActor.create(repository_ruleset: @ruleset)
    assert_predicate bypasser, :valid?
    assert_equal "DeployKey", bypasser.actor_type
    assert_equal "DeployKeyBypassActor", bypasser.type
    bypasser.save!
  end

  test "suggest and validate" do
    bypassers = DeployKeyBypassActor.suggest_bypassers(@org_repo, nil)
    assert_equal 1, bypassers.size
    bypasser = T.must(bypassers.first)
    assert_equal DeployKeyBypassActor, bypasser.class
    assert_equal "DeployKey", bypasser.class.display_type
    assert_equal "Deploy keys", bypasser.class.display_name

    assert_nil bypasser.id
    assert_nil bypasser.actor_id
    assert_equal "Deploy keys", bypasser.actor_name
    assert_equal "DeployKeyBypassActor", bypasser.type

    bypasser.repository_ruleset = @ruleset
    assert bypasser.valid?
    bypasser.save!
  end

  test "allowed_bypass_modes" do
    @ruleset.bypass_actors << DeployKeyBypassActor.new(bypass_mode: 0)
    @ruleset.save!
    rando = create(:user)
    repo_user = create(:user)
    @org_repo.add_member(repo_user, action: :admin)

    key = Sham.ssh_public_key
    application = create :oauth_application, user: repo_user
    access = create :oauth_access, user: repo_user, application:, scopes: %w(user)

    user_oauth_key = repo_user.public_keys.create_with_verification(key:, verifier: repo_user, oauth_authorization: access.authorization)
    repo_oauth_key = @org_repo.public_keys.create_with_verification(key:, verifier: repo_user, oauth_authorization: access.authorization)
    user_created_deploy_key = create(:public_key, repository: @org_repo, read_only: false)

    assert_equal [], DeployKeyBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, rando, @org_repo)
    assert_equal [], DeployKeyBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, repo_user, @org_repo)
    assert_equal [], DeployKeyBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @org.admins.first, @org_repo)
    assert_equal [], DeployKeyBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, user_oauth_key, @org_repo)
    assert_equal [0], DeployKeyBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, repo_oauth_key, @org_repo)
    assert_equal [0], DeployKeyBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, user_created_deploy_key, @org_repo)
    assert_equal [], DeployKeyBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, repo_oauth_key, @org_repo2)
    assert_equal [], DeployKeyBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, user_created_deploy_key, @org_repo2)
  end

  test "only one per ruleset" do
    @ruleset.bypass_actors << DeployKeyBypassActor.new
    assert @ruleset.valid?

    @ruleset.bypass_actors << DeployKeyBypassActor.new
    refute @ruleset.valid?
  end
end
