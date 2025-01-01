# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPrereceiveHooksBehaviorTest < GitHub::TestCase
  fixtures do
    create(:pre_receive_environment, id: 1, name: "Default", image_url: "githubenterprise://internal", checksum: "0")

    @owner = create :user, login: "owner"
    @org = create :organization, login: "robots", admin: @owner
    @org2 = create :organization, login: "robots2", admin: @owner
    @business = create :business, organizations: [@org, @org2]

    @hook_repo = create(:repository, name: "hook-repo", owner: @owner)
    @no_hook_repo = create(:repository, name: "no-hook-repo", owner: @owner)
    @one_hook_repo = create(:repository, name: "one-hook-repo", owner: @owner)
    @multi_hook_repo = create(:repository, name: "multi-hook-repo", owner: @org)
    @cascade_repo = create(:repository, name: "cascade-hook-repo", owner: @org2)
    @default_repo = create(:repository, name: "default-repo", owner: @owner)

    @hook_env = create(:pre_receive_environment)

    hook1 = create(:pre_receive_hook, environment: @hook_env, repository: @hook_repo, script: "some-script.rb")
    hook2 = create(:pre_receive_hook, environment: @hook_env, repository: @hook_repo, script: "other-script.rb")
    hook3 = create(:pre_receive_hook, environment: @hook_env, repository: @hook_repo, script: "org-script.rb")
    hook4 = create(:pre_receive_hook, environment: PreReceiveEnvironment.default, repository: @default_repo, script: "org-script.rb")

    @business_target = create(:pre_receive_hook_target, hook: hook2, hookable: @business, enforcement: GitHub::PreReceiveHookEntry::DISABLED)
    create(:pre_receive_hook_target, hook: hook1, hookable: @one_hook_repo, enforcement: GitHub::PreReceiveHookEntry::ENABLED)
    @repo_target = create(:pre_receive_hook_target, hook: hook1, hookable: @multi_hook_repo, enforcement: GitHub::PreReceiveHookEntry::ENABLED)
    @org_target = create(:pre_receive_hook_target, hook: hook2, hookable: @org, enforcement: GitHub::PreReceiveHookEntry::ENABLED)

    create(:pre_receive_hook_target, hook: hook2, hookable: @cascade_repo, enforcement: GitHub::PreReceiveHookEntry::ENABLED)
    create(:pre_receive_hook_target, hook: hook1, hookable: @cascade_repo, enforcement: GitHub::PreReceiveHookEntry::ENABLED)
    create(:pre_receive_hook_target, hook: hook3, hookable: @org2, enforcement: GitHub::PreReceiveHookEntry::ENABLED, final: true)
    create(:pre_receive_hook_target, hook: hook3, hookable: @cascade_repo, enforcement: GitHub::PreReceiveHookEntry::DISABLED)
    create(:pre_receive_hook_target, hook: hook4, hookable: @default_repo, enforcement: GitHub::PreReceiveHookEntry::ENABLED)
  end

  test "no hooks configured" do
    assert_equal([], @no_hook_repo.pre_receive_hooks)
  end

  test "single hook configured" do
    hooks = @one_hook_repo.pre_receive_hooks
    assert_equal 1, hooks.size
    assert_equal "some-script.rb", hooks[0].script
    assert_equal @hook_repo.id, hooks[0].repository_id
    assert_equal @hook_env.id, hooks[0].environment_id
  end

  test "multiple hooks configured at different levels" do
    hooks = @multi_hook_repo.pre_receive_hooks
    assert_equal 2, hooks.size
    assert_equal "other-script.rb", hooks[0].script
    assert_equal @hook_repo.id, hooks[0].repository_id
    assert_equal "some-script.rb", hooks[1].script
    assert_equal @hook_repo.id, hooks[1].repository_id
  end

  test "hooks with final settings at different levels" do
    hooks = @cascade_repo.pre_receive_hooks
    assert_equal 3, hooks.size
    assert_equal "org-script.rb", hooks[0].script
    assert_equal @hook_repo.id, hooks[0].repository_id
    assert_equal "other-script.rb", hooks[1].script
    assert_equal @hook_repo.id, hooks[1].repository_id
    assert_equal "some-script.rb", hooks[2].script
    assert_equal @hook_repo.id, hooks[2].repository_id
  end

  test "hooks with default environment" do
    hooks = @default_repo.pre_receive_hooks

    assert_equal 1, hooks.size
    assert_equal "org-script.rb", hooks[0].script
    assert_equal @default_repo.id, hooks[0].repository_id
    assert_equal PreReceiveEnvironment.default.id, hooks[0].environment_id
  end

  test "finds hooks from the repository" do
    assert @multi_hook_repo.pre_receive_hooks.any? { |entry| entry.hook_id == @repo_target.hook_id }
  end

  test "finds hooks from the owner" do
    assert @multi_hook_repo.pre_receive_hooks.any? { |entry| entry.hook_id == @org_target.hook_id }
  end

  test "finds global hooks" do
    assert @multi_hook_repo.pre_receive_hooks.any? { |entry| entry.hook_id == @business_target.hook_id }
  end

end
