# typed: true
# frozen_string_literal: true

require "test_helper"

class ForkGroupSettingTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @biz = Business.first || create(:business)
    @org = create(:organization, business: @biz, plan: "business_plus")

    @org.allow_private_repository_forking(actor: @org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    SportsGroupSetting.add(@org, "", value = { "ball": ["tennis"], "no_ball": ["chess"] })

    @repo = create(:private_repository, owner: @org)
    @repo0 = create(:private_repository, owner: @org, group_path: "")
    @repo1 = create(:private_repository, owner: @org, group_path: "foo")
    @repo2 = create(:private_repository, owner: @org, group_path: "foo/bar")
    @repo3 = create(:private_repository, owner: @org, group_path: "foo/bar/cat")

    setting = ForkGroupSetting.add(@org, "")

    setting = ForkGroupSetting.add(@org, "foo")
    setting.deny_external
    setting.save!

    setting = ForkGroupSetting.add(@org, "foo/bar")
    setting.deny_internal
    setting.save!

    setting = ForkGroupSetting.add(@org, "foo/bar/cat")
    setting.deny_users
    setting.save!
  end

  test "disabled without FF" do
    assert_nil ForkGroupSetting.for_repository(@repo)
    assert_nil ForkGroupSetting.for_repository(@repo0)
    assert_nil ForkGroupSetting.for_repository(@repo1)
    assert_nil ForkGroupSetting.for_repository(@repo2)
    assert_nil ForkGroupSetting.for_repository(@repo3)
  end unless GitHub.flipper[:repos_groups].enabled?

  test "deny_any?" do
    assert_nil ForkGroupSetting.for_repository(@repo)
    refute_predicate ForkGroupSetting.for_repository(@repo0), :deny_any?
    assert_predicate ForkGroupSetting.for_repository(@repo1), :deny_any?
    assert_predicate ForkGroupSetting.for_repository(@repo2), :deny_any?
    assert_predicate ForkGroupSetting.for_repository(@repo3), :deny_any?
  end if GitHub.flipper[:repos_groups].enabled?

  test "deny_all?" do
    refute_predicate ForkGroupSetting.for_repository(@repo0), :deny_all?
    refute_predicate ForkGroupSetting.for_repository(@repo1), :deny_all?
    refute_predicate ForkGroupSetting.for_repository(@repo2), :deny_all?
    assert_predicate ForkGroupSetting.for_repository(@repo3), :deny_all?
  end if GitHub.flipper[:repos_groups].enabled?

  test "deny_external?" do
    refute_predicate ForkGroupSetting.for_repository(@repo0), :deny_external?
    assert_predicate ForkGroupSetting.for_repository(@repo1), :deny_external?
    assert_predicate ForkGroupSetting.for_repository(@repo2), :deny_external?
    assert_predicate ForkGroupSetting.for_repository(@repo3), :deny_external?
  end if GitHub.flipper[:repos_groups].enabled?

  test "deny_internal?" do
    refute_predicate ForkGroupSetting.for_repository(@repo0), :deny_internal?
    refute_predicate ForkGroupSetting.for_repository(@repo1), :deny_internal?
    assert_predicate ForkGroupSetting.for_repository(@repo2), :deny_internal?
    assert_predicate ForkGroupSetting.for_repository(@repo3), :deny_internal?
  end if GitHub.flipper[:repos_groups].enabled?

  test "deny_users?" do
    refute_predicate ForkGroupSetting.for_repository(@repo0), :deny_users?
    refute_predicate ForkGroupSetting.for_repository(@repo1), :deny_users?
    refute_predicate ForkGroupSetting.for_repository(@repo2), :deny_users?
    assert_predicate ForkGroupSetting.for_repository(@repo3), :deny_users?
  end if GitHub.flipper[:repos_groups].enabled?

  test "reset forks that belong to group" do
    @repo0.block_private_repository_forking(actor: @org.admin)
    @repo1.block_private_repository_forking(actor: @org.admin)
    @repo2.block_private_repository_forking(actor: @org.admin)

    setting = ForkGroupSetting.for_repository(@repo1)

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      o = setting&.orchestrate(User.ghost)
    end

    # should still be blocked by repo config since orchestration didn't target it
    refute @repo0.reload.allow_private_repository_forking?

    # should now allow it by config since orchestration reset it, and the group setting is not totally disabled
    assert @repo1.reload.allow_private_repository_forking?
    assert @repo2.reload.allow_private_repository_forking?

    # should be blocked by group setting
    refute @repo3.reload.allow_private_repository_forking?
  end if GitHub.flipper[:repos_groups].enabled?

  test "ungrouped repos get settings too" do
    @repo.block_private_repository_forking(actor: @org.admin)
    @repo0.block_private_repository_forking(actor: @org.admin)

    settings = RepositoryGroupSetting.load_all_by_group(@repo0.group)

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      o = RepositoryGroupSetting.orchestrate_all(User.ghost, settings.values)
    end

    # should be reset even though it was not in a group before. It is now.
    assert @repo.reload.allow_private_repository_forking?

    # should be reset since it's in the group
    assert @repo0.reload.allow_private_repository_forking?
  end if GitHub.flipper[:repos_groups].enabled?

  class SportsGroupSetting < RepositoryGroupSetting
    def populate_attributes
      self.value ||= { "ball": [], "no_ball": [] }
      self.inherited ||= {}
      self.composite ||= {}
    end

    def apply(actor:, repository:); end
  end
end
