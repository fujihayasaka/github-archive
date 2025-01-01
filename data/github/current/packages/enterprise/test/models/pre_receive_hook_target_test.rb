# typed: true
# frozen_string_literal: true

require "test_helper"

class PreReceiveHookTargetTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @env = create(:pre_receive_environment)
    @hook = create :pre_receive_hook, environment: @env
    @org = create(:organization)
    @business = create :business, organizations: [@org]
    @repo = create :repository, :minimal, owner: @org
    @repo_target = create :pre_receive_hook_target, hookable: @repo
    @owner = create :user, login: "theowner"
    @user_repo = create :repository, :minimal, owner: @owner
    @global_target = create :pre_receive_hook_target, hookable: @business
    @org_target = create :pre_receive_hook_target, hookable: @org
  end

  test "requires a hook" do
    target = PreReceiveHookTarget.new hookable_type: "Repository", hookable_id: (create :repository, :minimal).id, enforcement: GitHub::PreReceiveHookEntry::ENABLED
    assert !target.valid?
    target.hook = @hook
    assert target.valid?
  end

  test "requires hookable" do
    hookable = create(:repository, :minimal)
    target = PreReceiveHookTarget.new enforcement: GitHub::PreReceiveHookEntry::ENABLED, hook: @hook
    assert !target.valid?
    target.hookable = hookable
    assert target.valid?
  end

  test "requires enforcement" do
    target = PreReceiveHookTarget.new hookable_type: "Repository", hookable_id: (create :repository, :minimal).id, hook: @hook
    assert !target.valid?
    target.enforcement = GitHub::PreReceiveHookEntry::ENABLED
    assert target.valid?
    target.enforcement = "0"
    assert target.valid?, "enforcement should accept an integer.to_s"
  end

  test "enforcement level must be either enabled, disabled, or testing" do
    target = PreReceiveHookTarget.new hookable: @business, hook: @hook
    target.enforcement = GitHub::PreReceiveHookEntry::ENABLED
    assert target.valid?
    target.enforcement = "enabled"
    assert target.valid?
    target.enforcement = :enabled
    assert target.valid?
    target.enforcement = GitHub::PreReceiveHookEntry::DISABLED
    assert target.valid?
    target.enforcement = GitHub::PreReceiveHookEntry::TESTING
    assert target.valid?
  end

  test "enforcement level must be either enabled or disabled if set at repo/org level" do
    target = PreReceiveHookTarget.new hookable_type: "Repository", hookable_id: (@repo).id, hook: @hook
    target.enforcement = GitHub::PreReceiveHookEntry::ENABLED
    assert target.valid?
    target.enforcement = GitHub::PreReceiveHookEntry::DISABLED
    assert target.valid?
    target.enforcement = GitHub::PreReceiveHookEntry::TESTING
    assert !target.valid?
  end

  test "hookable_type must be repository, user, or Business" do
    target = PreReceiveHookTarget.new enforcement: GitHub::PreReceiveHookEntry::ENABLED, hook: @hook
    target.hookable_id = (@repo).id
    target.hookable_type = "Repository"
    assert target.valid?
    target.hookable_id = (create(:user)).id
    target.hookable_type = "User"
    assert target.valid?
    target.hookable_id = @business.id
    target.hookable_type = "Business"
    assert target.valid?
    target.hookable_id = (create(:issue)).id
    target.hookable_type = "Issue"
    assert !target.valid?
  end

  test "only one target is allowed for the same hook and hookable" do
    target = PreReceiveHookTarget.create enforcement: GitHub::PreReceiveHookEntry::ENABLED, hook: @hook, hookable: @repo
    assert target.valid?
    target_same = PreReceiveHookTarget.new enforcement: GitHub::PreReceiveHookEntry::DISABLED, hook: @hook, hookable: @repo
    assert !target_same.valid?
  end

  test "accepts nested attributes for hook" do
    target = PreReceiveHookTarget.create(
      enforcement: GitHub::PreReceiveHookEntry::ENABLED,
      hookable: create(:repository, :minimal),
      hook_attributes: { name: "hook name",
                            repository: create(:repository),
                            script: "script",
                            environment: create(:pre_receive_environment),
      })
    assert PreReceiveHook.find_by(name: "hook name")
  end

  test "can call .hookable with business target" do
    target = PreReceiveHookTarget.new hookable: @business, enforcement: GitHub::PreReceiveHookEntry::ENABLED
    assert target.hookable
  end

  test "creates an audit log entry on enforcement at repository level" do
    events = subscribe "pre_receive_hook.enforcement"
    PreReceiveHookTarget.create enforcement: GitHub::PreReceiveHookEntry::ENABLED, hook: @hook, hookable: @repo

    expected_payload = {
      enforcement: "Enabled",
      final: "Can be overridden at lower level",
      repo: @repo.nwo,
      repo_id: @repo.id,
      public_repo: @repo.public?,
      pre_receive_hook: @hook.name,
      pre_receive_hook_id: @hook.id,
      pre_receive_environment: @env.name,
      pre_receive_environment_id: @env.id,
    }
    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "creates an audit log entry on enforcement at organization level" do
    events = subscribe "pre_receive_hook.enforcement"
    PreReceiveHookTarget.create enforcement: GitHub::PreReceiveHookEntry::ENABLED, hook: @hook, hookable: @org

    expected_payload = {
      enforcement: "Enabled",
      final: "Can be overridden at lower level",
      org: @org.name,
      org_id: @org.id,
      pre_receive_hook: @hook.name,
      pre_receive_hook_id: @hook.id,
      repo: @hook.repository.nwo,
      repo_id: @hook.repository.id,
      public_repo: @hook.repository.public?,
      pre_receive_environment: @env.name,
      pre_receive_environment_id: @env.id,
    }
    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "creates an audit log entry on enforcement at global level" do
    events = subscribe "pre_receive_hook.enforcement"
    PreReceiveHookTarget.create enforcement: GitHub::PreReceiveHookEntry::ENABLED, hook: @hook, hookable: @business, final: true

    expected_payload = {
      enforcement: "Enabled",
      final: "Enforced for #{@business.slug}",
      business: @business.slug,
      business_id: @business.id,
      pre_receive_hook: @hook.name,
      pre_receive_hook_id: @hook.id,
      repo: @hook.repository.nwo,
      repo_id: @hook.repository.id,
      public_repo: @hook.repository.public?,
      pre_receive_environment: @env.name,
      pre_receive_environment_id: @env.id,
    }
    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "valid_hookable?" do
    [@repo, @user_repo, @business, @org].each do |hookable|
      assert PreReceiveHookTarget.valid_hookable?(hookable)
    end
    [0, nil, [nil, nil], "asdofin", [], GitHub].each do |hookable|
      refute PreReceiveHookTarget.valid_hookable?(hookable)
    end
  end

  test "enforcement_target with duplicate org and repository id" do
    global_target = create :pre_receive_hook_target, hookable: @business, hook: @hook
    id = [Organization.maximum(:id).to_i, Repository.maximum(:id).to_i].max + 1_000_000
    repo = create(:repository, :minimal, id: id)
    org = create(:organization, id: id, business: @business)
    create :pre_receive_hook_target, hookable: repo, hook: @hook
    assert_equal global_target, PreReceiveHookTarget.enforcement_target(org, @hook)
  end

  test "enforcement_target" do
    repo_target = create :pre_receive_hook_target, hookable: @repo, hook: @hook
    repo_target = PreReceiveHookTarget.find(repo_target.id)
    create :pre_receive_hook_target, hookable: @repo
    create :pre_receive_hook_target, hookable: @business
    assert_equal repo_target, PreReceiveHookTarget.enforcement_target(@repo, @hook)
    org_target = create :pre_receive_hook_target, hookable: @org, hook: @hook, final: true
    create :pre_receive_hook_target, hookable: @org
    assert_equal org_target, PreReceiveHookTarget.enforcement_target(@repo, @hook)
    global_target = create :pre_receive_hook_target, hookable: @business, hook: @hook
    assert_equal org_target, PreReceiveHookTarget.enforcement_target(@repo, @hook)
    global_target.destroy
    global_target = create :pre_receive_hook_target, hookable: @business, hook: @hook, final: true
    assert_equal global_target, PreReceiveHookTarget.enforcement_target(@repo, @hook)
    org_target.destroy
    assert_equal global_target, PreReceiveHookTarget.enforcement_target(@repo, @hook)
    global_target.destroy
    global_target = create :pre_receive_hook_target, hookable: @business, hook: @hook
    assert_equal repo_target, PreReceiveHookTarget.enforcement_target(@repo, @hook)
  end

  test "override_upstream_target finds and updates a target" do
    hook = @org_target.hook
    org_target = PreReceiveHookTarget.override_upstream_target(@org, hook, enforcement: 0)
    assert_equal @org_target, org_target
    assert_predicate org_target, :disabled?
    @org_target.reload
    assert_predicate @org_target, :disabled?
  end

  test "override_upstream_target creates a new target" do
    global_target = create :pre_receive_hook_target, hookable: @business, hook: @hook
    org_target = PreReceiveHookTarget.override_upstream_target(@org, @hook, enforcement: 0)
    assert_predicate org_target, :disabled?
    assert_equal @org, org_target.hookable
  end

  test "override_upstream_target creates a new org target when there's a repo with the same id" do
    create :pre_receive_hook_target, hookable: @business, hook: @hook
    id = [Organization.maximum(:id).to_i, Repository.maximum(:id).to_i].max + 1_000_000
    org = create(:organization, id: id, business: @business)
    repo = create(:repository, :minimal, id: id)
    create :pre_receive_hook_target, hookable: repo, hook: @hook
    org_target = PreReceiveHookTarget.override_upstream_target(org, @hook, enforcement: 0)
    assert_predicate org_target, :disabled?
    assert_equal org, org_target.hookable
    assert_equal org_target, PreReceiveHookTarget.find(org_target.id)
  end

  test "override_upstream_target works when there's no upstream target" do
    assert_raises(ArgumentError) do
      PreReceiveHookTarget.override_upstream_target(@org, @hook, enforcement: 0)
    end
  end

  test "override_upstream_target works when upstream is final" do
    create :pre_receive_hook_target, hookable: @business, hook: @hook, final: true
    assert_raises(PreReceiveHookTarget::NotAllowedByUpstreamError) do
      PreReceiveHookTarget.override_upstream_target(@org, @hook, enforcement: 0)
    end
  end

  [ActiveRecord::RecordNotUnique.new("message"),
    ActiveRecord::RecordInvalid.new(PreReceiveHookTarget.new),
  ].each do |error|
    test "override_upstream_target retries on #{error.class}" do
      enforcement_target = create :pre_receive_hook_target, hookable: @business, hook: @hook, enforcement: 0
      target1 = enforcement_target.dup.tap { |t| t.stubs(:update!).raises(error) }
      target2 = enforcement_target.dup
      PreReceiveHookTarget.any_instance.expects(:dup).times(2)
        .returns(target1)
        .then.returns(target2)
      new_target = PreReceiveHookTarget.override_upstream_target(@org, @hook, enforcement: 2)
      assert_equal target2, new_target
      assert_equal target2, PreReceiveHookTarget.for_hook(@hook).find { |t| t.hookable == @org }
    end
  end

  [ActiveRecord::RecordNotUnique.new("message"),
    ActiveRecord::RecordInvalid.new(PreReceiveHookTarget.new),
  ].each do |error|
    test "override_upstream_target raises #{error.class} after retry" do
      enforcement_target = create :pre_receive_hook_target, hookable: @business, hook: @hook, enforcement: 0
      PreReceiveHookTarget.any_instance.expects(:update!).times(2).raises(error)
      assert_raises(error.class) do
        PreReceiveHookTarget.override_upstream_target(@org, @hook, enforcement: 2)
      end
    end
  end

  context "scopes" do
    test "for_hook" do
      create :pre_receive_hook_target
      assert_empty PreReceiveHookTarget.for_hook(@hook)
      assert_empty PreReceiveHookTarget.for_hook(@hook.id)
      target1 = create :pre_receive_hook_target, hook_id: @hook.id
      assert_equal [target1], PreReceiveHookTarget.for_hook(@hook)
      assert_equal [target1], PreReceiveHookTarget.for_hook(@hook.id)
    end

    test "sorted_by" do
      names = PreReceiveHookTarget.all.map { |t| T.must(t.hook).name }.sort
      assert_equal names, PreReceiveHookTarget.sorted_by("hook.name").map { |t| T.must(t.hook).name }
      assert_equal names.reverse, PreReceiveHookTarget.sorted_by("hook.name", "DESC").map { |t| T.must(t.hook).name }
      ids = PreReceiveHookTarget.all.map { |t| T.must(t.hook).id }.sort
      assert_equal ids, PreReceiveHookTarget.sorted_by("hook.id", "asdoin").map { |t| T.must(t.hook).id }
      assert_equal ids.reverse, PreReceiveHookTarget.sorted_by("hook.id", "desc").map { |t| T.must(t.hook).id }
      target_ids = PreReceiveHookTarget.all.map(&:id).sort
      assert_equal target_ids, PreReceiveHookTarget.sorted_by("id").map(&:id)
      assert_equal target_ids.reverse, PreReceiveHookTarget.sorted_by("id", "desc").map(&:id)
    end

    test "sorted_by priority last" do
      hook = @repo_target.hook
      assert_equal @repo_target, PreReceiveHookTarget.for_hook(hook).for_hookable_and_parents(@repo).sorted_by("priority").last
    end

    test "sorted_by priority" do
      hook = create :pre_receive_hook, environment: @env
      global_target = create :pre_receive_hook_target, hookable: @business, hook: hook
      org_target = create :pre_receive_hook_target, hookable: @org, hook: hook
      repo_target = create :pre_receive_hook_target, hookable: @repo, hook: hook
      targets_scope = PreReceiveHookTarget.for_hook(hook).for_hookable_and_parents(@repo)
      assert_equal [global_target, org_target, repo_target], targets_scope.sorted_by("priority")
      assert_equal [repo_target, org_target, global_target], targets_scope.sorted_by("priority", "desc")
    end

    test "hookable_owner_chain" do
      repo_target = create :pre_receive_hook_target, hookable: @repo, hook: @hook
      repo_target = PreReceiveHookTarget.find(repo_target.id)
      create :pre_receive_hook_target, hookable: @repo
      global_target = create :pre_receive_hook_target, hookable: @business, hook: @hook
      create :pre_receive_hook_target, hookable: @business
      org_target = create :pre_receive_hook_target, hookable: @org, hook: @hook
      create :pre_receive_hook_target, hookable: @org
      chain = PreReceiveHookTarget.for_hook(@hook).for_hookable_and_parents(@repo).sorted_by("priority")
      assert_equal [global_target, org_target, repo_target], chain
    end

    test "visible_for_hookable" do
      PreReceiveHookTarget.destroy_all
      hook = create :pre_receive_hook
      hook2 = create :pre_receive_hook
      global_target = create :pre_receive_hook_target, hookable: @business, hook: hook
      global_target2 = create :pre_receive_hook_target, hookable: @business, hook: hook2,
                                                 enforcement: "disabled", final: true
      org_target = create :pre_receive_hook_target, hookable: @org, hook: hook

      assert_no_query_warnings do
        assert_equal [org_target], PreReceiveHookTarget.visible_for_hookable(@repo)
        global_target.update final: true
        assert_equal [global_target], PreReceiveHookTarget.visible_for_hookable(@repo)
        org_target.update final: true
        assert_equal [global_target], PreReceiveHookTarget.visible_for_hookable(@repo)
        global_target2.update enforcement: "enabled"
        assert_equal [global_target, global_target2].sort, PreReceiveHookTarget.visible_for_hookable(@repo).sort
      end
    end

    test "visible_for_hookable with disabled, non-final business target" do
      PreReceiveHookTarget.destroy_all
      hook = create :pre_receive_hook
      global_target = create :pre_receive_hook_target, hookable: @business, hook: hook,
        enforcement: "disabled", final: false
      assert_equal [global_target], PreReceiveHookTarget.visible_for_hookable(@repo)
    end

    context "for_hookable_and_parents" do
      test "for a repo" do
        PreReceiveHookTarget.destroy_all
        hook = create :pre_receive_hook
        hook2 = create :pre_receive_hook
        repo_target = create :pre_receive_hook_target, hookable: @repo, hook: hook
        repo_target2 = create :pre_receive_hook_target, hookable: @repo, hook: hook2
        global_target = create :pre_receive_hook_target, hookable: @business, hook: hook
        global_target2 = create :pre_receive_hook_target, hookable: @business, hook: hook2, enforcement: "disabled", final: true
        org_target = create :pre_receive_hook_target, hookable: @org, hook: hook
        assert_same_elements [org_target, global_target, global_target2, repo_target, repo_target2], PreReceiveHookTarget.for_hookable_and_parents(@repo)

      end

      test "when org.id duplicates a repo.id" do
        id = [Organization.maximum(:id).to_i, Repository.maximum(:id).to_i].max + 1_000_000
        repo = create(:repository, :minimal, id: id)
        PreReceiveHookTarget.destroy_all
        create :pre_receive_hook_target, hookable: repo, hook: @hook
        global_target = create :pre_receive_hook_target, hookable: @business, hook: @hook
        org = create(:organization, id: id, business: @business)
        assert_equal [global_target], PreReceiveHookTarget.for_hookable_and_parents(org)
      end
    end

  end

end
