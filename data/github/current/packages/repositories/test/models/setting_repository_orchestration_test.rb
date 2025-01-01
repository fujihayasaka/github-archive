# typed: true
# frozen_string_literal: true

require "test_helper"

class SettingRepositoryOrchestrationTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @biz = Business.first || create(:business)
    @org = create(:organization, business: @biz, plan: "business_plus")
    @member = create(:user)
    @org.add_member(@member)
    @org.allow_private_repository_forking(actor: @org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    @repo1 = create(:private_repository, owner: @org)
    @repo2 = create(:private_repository, owner: @org, group_path: "")
    @repo3 = create(:private_repository, owner: @org, group_path: "foo")

    TestGroupSetting.add(@org, "", value = { teams: ["blue"] })
    TestGroupSetting.add(@org, "foo", value = { teams: ["green"] })
  end

  test "individual repo" do
    setting = TestGroupSetting.load_by_group(@repo2.group)
    o = SettingOrchestration.from_group_setting(User.ghost.id, setting, @repo2)
    o.execute!

    assert_enqueued_jobs(1, only: RepositoryOrchestrationJob)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob)

    assert_equal 0, SettingOrganizationOrchestration.all.count
    assert_equal 1, SettingRepositoryOrchestration.count
    assert_equal 1, SettingRepositoryOrchestration.succeeded.count
    repos = SettingRepositoryOrchestration.pluck(:repository_id)
    assert_same_elements [@repo2.id], repos
  end

  test "only one orchestration" do
    setting = TestGroupSetting.load_by_group(@repo2.group)
    o1 = SettingOrchestration.from_group_setting(User.ghost.id, setting, @repo2)
    o1.execute!

    # attempt another orchestration for the same repo. Should fail.
    assert_raises(ActiveRecord::RecordInvalid) do
      o2 = SettingOrchestration.from_group_setting(User.ghost.id, setting, @repo2)
    end
  end

  test "invalid repo for path" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "foo")
    setting = TestGroupSetting.load_by_group(group)
    o = SettingOrchestration.from_group_setting(User.ghost.id, setting, @repo2)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      o.execute!
    end
    o.reload

    assert_equal "skipped", o.state
    assert_equal "validate_repo", o.step_name
    assert_equal "not in group 'foo'", o.error_message
  end

  class TestGroupSetting < RepositoryGroupSetting
    after_initialize :populate_attributes

    def populate_attributes
      self.value ||= { "teams": [], "deny": [] }
      self.inherited ||= {}
      self.composite ||= {}
    end

    def apply(actor:, repository:); end
  end
end
