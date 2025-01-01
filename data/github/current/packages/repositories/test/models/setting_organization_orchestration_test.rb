# typed: true
# frozen_string_literal: true

require "test_helper"

class SettingOrganizationOrchestrationTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @biz = Business.first || create(:business)
    @org = create(:organization, business: @biz, plan: "business_plus")
    @member = create(:user)
    @org.add_member(@member)
    @org.allow_private_repository_forking(actor: @org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    @repo1 = create(:private_repository, owner: @org)
    @repo2 = create(:private_repository, owner: @org)
    @repo3 = create(:private_repository, owner: @org)
    @repo4 = create(:private_repository, owner: @org)
    @repo5 = create(:private_repository, owner: @org)

    # repo1 doesn't get a group, it will get assigned to the root group by the orchestration
    @repo2.join_group("")
    @repo3.join_group("foo")
    @repo4.join_group("foo/bar")
    @repo5.join_group("foo")

    TestGroupSetting.add(@org, "", value = { teams: ["blue"] })
    TestGroupSetting.add(@org, "foo", value = { teams: ["green"] })
    TestGroupSetting.add(@org, "food", value = { teams: ["yellow"] })
    TestGroupSetting.add(@org, "foo/bar", value = { teams: %w[blue red] })

    PaintGroupSetting.add(@org, "", value = { colors: ["pink"] })
  end

  test "apply settings to org" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "")
    setting = TestGroupSetting.load_by_group(group)

    o = T.must(setting).orchestrate(User.ghost)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob)

    assert_equal 1, SettingOrganizationOrchestration.where(repository_id: nil, state: :waiting).count
    assert_equal o.data[:organization_id], @org.id

    # try to run another orchestration at the same time. It should fail
    assert_raises(ActiveRecord::RecordInvalid) do
      o = T.must(setting).orchestrate(User.ghost)
    end
  end

  test "org at root" do
    group = RepositoryGroup.find_by!(owner: @org, group_path: "")
    setting = T.must(TestGroupSetting.load_by_group(group))

    # should send 3 notifications: start, in progress, and finished
    GitHub::WebSocket.expects(:notify_setting_orchestration_status_channel).times(3)

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      o = T.must(setting).orchestrate(User.ghost)
    end

    # repo1 should have been assigned to the root group
    assert_equal group.id, @repo1.group.id

    assert_equal 1, SettingOrganizationOrchestration.where(repository_id: nil, state: :succeeded).count
    assert_equal 5, SettingRepositoryOrchestration.count
    assert_equal 5, SettingRepositoryOrchestration.succeeded.count
    repos = SettingRepositoryOrchestration.pluck(:repository_id)
    assert_same_elements [@repo1.id, @repo2.id, @repo3.id, @repo4.id, @repo5.id], repos

    o = T.must(setting.orchestration)
    assert_equal 0, o.data[:failed]
    assert_equal 5, o.data[:succeeded]
    assert_equal 5, o.data[:total]
  end

  test "batch with repo conflict" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "")

    # create an orchestration for a single repo, but don't finish it
    setting = TestGroupSetting.load_by_group(@repo2.group)
    o1 = SettingOrchestration.from_group_setting(User.ghost.id, setting, @repo2)
    o1.execute!

    # create an orchestration for the whole org
    setting = TestGroupSetting.load_by_group(group)

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      o = T.must(setting).orchestrate(User.ghost)
    end

    o1.execute!

    # for now, we expect that both orchestrations targeting @repo2 will execute to completion
    assert_equal 1, SettingOrganizationOrchestration.where(repository_id: nil, state: :succeeded).count
    assert_equal 6, SettingRepositoryOrchestration.count
    assert_equal 6, SettingRepositoryOrchestration.succeeded.count
    repos = SettingRepositoryOrchestration.pluck(:repository_id)
    assert_same_elements [@repo1.id, @repo2.id, @repo2.id, @repo3.id, @repo4.id, @repo5.id], repos
  end

  test "run in batches" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "")
    setting = TestGroupSetting.load_by_group(group)

    # set a batch size of 0.3 * 10 = 3
    GitHub.flipper[:setting_orchestration_batch_size].enable_percentage_of_time(0.3)

    # should send 4 notifications: before batch 1, before batch 2, empty batch, and finished
    GitHub::WebSocket.expects(:notify_setting_orchestration_status_channel).times(4)

    o = T.must(setting).orchestrate(User.ghost)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob)
    assert_equal 1, SettingOrganizationOrchestration.waiting.count
    assert_equal 3, SettingRepositoryOrchestration.running.count
    assert_same_elements [@repo2.id, @repo3.id, @repo4.id], SettingRepositoryOrchestration.running.pluck(:repository_id)
    o.reload
    assert_equal 0, o.data[:failed]
    assert_equal 0, o.data[:succeeded]
    assert_equal 3, o.data[:in_progress]
    assert_equal 5, o.data[:total]

    perform_enqueued_jobs(only: RepositoryOrchestrationJob)
    assert_equal 1, SettingOrganizationOrchestration.running.count
    assert_equal 3, SettingRepositoryOrchestration.succeeded.count
    assert_same_elements [@repo2.id, @repo3.id, @repo4.id], SettingRepositoryOrchestration.pluck(:repository_id)

    perform_enqueued_jobs(only: RepositoryOrchestrationJob)
    assert_equal 1, SettingOrganizationOrchestration.waiting.count
    assert_equal 3, SettingRepositoryOrchestration.succeeded.count
    assert_equal 2, SettingRepositoryOrchestration.running.count
    assert_same_elements [@repo1.id, @repo5.id], SettingRepositoryOrchestration.running.pluck(:repository_id)
    o.reload

    assert_equal 0, o.data[:failed]
    assert_equal 3, o.data[:succeeded]
    assert_equal 2, o.data[:in_progress]
    assert_equal 5, o.data[:total]

    perform_enqueued_jobs(only: RepositoryOrchestrationJob)
    assert_equal 1, SettingOrganizationOrchestration.running.count
    assert_equal 5, SettingRepositoryOrchestration.succeeded.count

    perform_enqueued_jobs(only: RepositoryOrchestrationJob)
    assert_equal 1, SettingOrganizationOrchestration.succeeded.count
    refute o.reload.step_name
    assert_equal 5, SettingRepositoryOrchestration.succeeded.count
    assert_equal 0, o.data[:failed]
    assert_equal 5, o.data[:succeeded]
    assert_equal 5, o.data[:total]
    assert_equal 0, o.data[:in_progress]

    repos = SettingRepositoryOrchestration.pluck(:repository_id)
    assert_same_elements [@repo1.id, @repo2.id, @repo3.id, @repo4.id, @repo5.id], repos
  end

  test "proceed if a child fails" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "")
    setting = TestGroupSetting.load_by_group(group)

    # set a batch size of 0.3 * 10 = 3
    GitHub.flipper[:setting_orchestration_batch_size].enable_percentage_of_time(0.3)

    o = T.must(setting).orchestrate(User.ghost)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob)

    assert_equal 1, SettingOrganizationOrchestration.waiting.count
    assert_equal 3, SettingRepositoryOrchestration.running.count

    # fail one of the orchestrations
    T.must(SettingRepositoryOrchestration.running.first).failed!
    begin
      # this job should raise because it will try to execute an orchestration we already finished
      perform_enqueued_jobs(only: RepositoryOrchestrationJob)
    rescue Orchestration::Error
    end

    assert_equal 1, SettingRepositoryOrchestration.failed.count, "one child should have failed"

    # run the rest of the orchestrations to completion
    while SettingOrchestration.running.count > 0
      begin
        # the parent orchestration will fail too, because the child failed
        perform_enqueued_jobs(only: RepositoryOrchestrationJob)
      rescue Orchestration::Error
      end
    end
    assert_equal :failed, o.reload.state.to_sym, "parent should have failed"
    assert_equal 1, SettingRepositoryOrchestration.failed.count, "one child should have failed"
    assert_equal 4, SettingRepositoryOrchestration.succeeded.count, "others should have succeeded"
    assert_same_elements o.data[:failed_orchestrations], SettingRepositoryOrchestration.failed.pluck(:id).to_a

    assert_equal 1, o.data[:failed]
    assert_equal 4, o.data[:succeeded]
    assert_equal 5, o.data[:total]
  end

  test "org at foo" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "foo")
    setting = T.must(TestGroupSetting.load_by_group(group))

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      o = T.must(setting).orchestrate(User.ghost)
    end

    assert_equal 1, SettingOrganizationOrchestration.where(repository_id: nil, state: :succeeded).count
    assert_equal 3, SettingRepositoryOrchestration.count
    assert_equal 3, SettingRepositoryOrchestration.succeeded.count
    repos = SettingRepositoryOrchestration.pluck(:repository_id)
    assert_same_elements [@repo3.id, @repo4.id, @repo5.id], repos

    o = T.must(setting.orchestration)
    assert_equal 0, o.data[:failed]
    assert_equal 3, o.data[:succeeded]
    assert_equal 3, o.data[:total]
  end

  test "org at foo/bar" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "foo/bar")
    setting = TestGroupSetting.load_by_group(group)

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      o = T.must(setting).orchestrate(User.ghost)
    end

    assert_equal 1, SettingOrganizationOrchestration.where(repository_id: nil, state: :succeeded).count
    assert_equal 1, SettingRepositoryOrchestration.count
    assert_equal 1, SettingRepositoryOrchestration.succeeded.count
    repos = SettingRepositoryOrchestration.pluck(:repository_id)
    assert_same_elements [@repo4.id], repos
  end

  test "orchestrate_all" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "")
    all_settings = RepositoryGroupSetting.load_all_by_group(group)
    assert_equal 2, all_settings.size

    o = RepositoryGroupSetting.orchestrate_all(User.ghost, all_settings.values)
    expected = ["SettingOrganizationOrchestrationTest::PaintGroupSetting",
                "SettingOrganizationOrchestrationTest::TestGroupSetting"]
    assert_same_elements expected, o.data[:types]
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

  class PaintGroupSetting < RepositoryGroupSetting
    def populate_attributes
      self.value ||= { "colors": {} }
      self.inherited ||= {}
      self.composite ||= {}
    end

    def apply(actor:, repository:); end
  end
end
