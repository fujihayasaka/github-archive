# typed: true
# frozen_string_literal: true

require "test_helper"

class UserPublicdeployKeysTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:staff_admin_user, login: "defunkt", plan: "medium", email: "chris@ozmm.org")
    @mojombo = create(:user, login: "mojombo", email: "tom@mojombo.com")
    @pj      = create(:user, login: "pj", email: "pjhyett@gmail.com", plan: "medium")
    @maddox  = create(:user, login: "maddox")
    @spammer = create(:user, login: "dr-evil", spammy: true)
    @grit    = create(:repository, name: "grit", owner: @mojombo, from_example: :pull_request_source)
    @ambition = create(:private_repository, name: "ambition", owner: @defunkt)
    @facebox  = create(:repository, name: "facebox", owner: @defunkt)
    @github   = create(:repository, name: "github", owner: @defunkt)

    @paid_org = create(:organization, admin: @defunkt, plan: GitHub::Plan.non_free_org_plans.first.name)
    @paid_org_team = create(:team, organization: @paid_org)

    oauth_app = make_oauth_app(@pj)
    @oauth_token = make_oauth(@mojombo, [:repo], oauth_app).reset_token

    @defunkt_grit = create(:fork_repository, forker: @defunkt, fork_repo: @grit, from_example: :pull_request_fork)
  end

  setup do
    GitHub.preview_features_enabled = true

    @key = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAzJFfKCBmeagAjnTp7X+3n0RKlnCQPwwmz40DbQdvVq3xHUtmGpBIQ3TX/qDpyMY97S4REkQf9oaJ9hevsOkJVg2eykv5F0gBwCTwrxzlxouI071hkToJKQfD3m9BEW3CZm6kt3qW6lVgEy30ijgZI9IZquuDiR01bayaWR3+FFCpY1fYr6yRl+g57KYOm/Kd0iiDlPhwh1W5U8C29RLFFKAirzAWpp78zONfrayXJK6cMxYKVkCGonTrhx7C06PEU5SA4Gl57OG1aFLsUg3TSvEt+nDdxh3lTZC3NAQPMmcpQ6HVEr0HcNylQrtN/fVYvz1cGutAGHkkf1ikw/QDyw== tom@fuzed.local"
    @processed_key = @key.sub(/\s+\S+$/, "") # key with trailing comment removed, like we do
  end

  def create_user(options = {})
    User.create({
      login: "quire",
      email: "quire@example.com",
      password: GitHub.default_password,
    }.merge(options))
  end

  test "can't use an existing key" do
    key = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAzJFfKCBmeagAjnTp7X+3n0RKlnCQPwwmz40DbQdvVq3xHUtmGpBIQ3TX/qDpyMY97S4REkQf9oaJ9hevsOkJVg2eykv5F0gBwCTwrxzlxouI071hkToJKQfD3m9BEW3CZm6kt3qW6lVgEy30ijgZI9IZquuDiR01bayaWR3+FFCpY1fYr6yRl+g57KYOm/Kd0iiDlPhwh1W5U8C29RLFFKAirzAWpp78zONfrayXJK6cMxYKVkCGonTrhx7C06PEU5SA4Gl57OG1aFLsUg3TSvEt+nDdxh3lTZC3NAQPMmcpQ6HVEr0HcNylQrtN/fVYvz1cGutAGHkkf1ikw/QDyw== tom@fuzed.local"
    orig = create_user public_keys: key
    user = create_user public_keys: key,
      login: orig.login + "-dupe", email: "quire2@example.com"
    refute_predicate user, :valid?
    assert user.errors[:public_keys].any?
  end

  test "has a key fingerprint" do
    key = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAzJFfKCBmeagAjnTp7X+3n0RKlnCQPwwmz40DbQdvVq3xHUtmGpBIQ3TX/qDpyMY97S4REkQf9oaJ9hevsOkJVg2eykv5F0gBwCTwrxzlxouI071hkToJKQfD3m9BEW3CZm6kt3qW6lVgEy30ijgZI9IZquuDiR01bayaWR3+FFCpY1fYr6yRl+g57KYOm/Kd0iiDlPhwh1W5U8C29RLFFKAirzAWpp78zONfrayXJK6cMxYKVkCGonTrhx7C06PEU5SA4Gl57OG1aFLsUg3TSvEt+nDdxh3lTZC3NAQPMmcpQ6HVEr0HcNylQrtN/fVYvz1cGutAGHkkf1ikw/QDyw== tom@fuzed.local"
    @mojombo.public_keys.create!(key: key)
    assert !@mojombo.public_keys.first.fingerprint_sha256.blank?
  end

  test "includes keys from repos user owns" do
    @grit.public_keys.create!(key: @key)
    assert @mojombo.public_keys.empty?
    assert_equal [@processed_key], @mojombo.deploy_keys.collect(&:key)
  end

  test "includes keys from repos owned by an org user is an Owner of" do
    org = create :organization, admin: @mojombo, plan: "bronze"
    repo = create(:private_repository, owner: org)
    repo.public_keys.create!(key: @key)
    assert_equal [@processed_key], @mojombo.deploy_keys.collect(&:key)
  end

  test "includes keys from org repos where a team grants user admin access" do
    org = create :organization, admin: @defunkt, plan: "bronze"
    repo = create(:private_repository, owner: org)
    team = create :team, organization: org, permission: "admin"
    team.add_repository repo, :admin
    team.add_member @mojombo

    repo.public_keys.create!(key: @key)
    assert_equal [@processed_key], @mojombo.deploy_keys.collect(&:key)
  end

  test "excludes keys from org repos where user teams do not grant admin access" do
    org = create :organization, admin: @defunkt, plan: "bronze"
    repo = create(:private_repository, owner: org)
    team = create :team, organization: org, permission: "push"
    team.add_repository repo, :push
    team.add_member @mojombo

    repo.public_keys.create!(key: @key)
    assert_equal [], @mojombo.deploy_keys
  end

  test "excludes keys from org repos where user has no team access" do
    org = create :organization, admin: @defunkt, plan: "bronze"
    repo = create(:private_repository, owner: org)

    repo.public_keys.create!(key: @key)
    assert_equal [], @mojombo.deploy_keys
  end

  test "excludes keys from repos where user is only a collaborator" do
    repo = create :private_repository, owner: @defunkt, name: "somerepo"
    repo.add_member @mojombo

    repo.public_keys.create!(key: @key)
    assert_equal [], @mojombo.deploy_keys
  end

  test "excludes keys from private repos where user does not have access" do
    repo = create :private_repository, owner: @defunkt, name: "somerepo"
    repo.public_keys.create!(key: @key)
    assert_equal [], @mojombo.deploy_keys
  end

  test "excludes keys from public repos where user does not otherwise have access" do
    repo = create(:public_repository, owner: @defunkt, name: "somerepo")
    repo.public_keys.create!(key: @key)
    assert_equal [], @mojombo.deploy_keys
  end
end
