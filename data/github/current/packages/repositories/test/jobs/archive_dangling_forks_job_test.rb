# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ArchiveDanglingForksJobTest < GitHub::TestCase
  include CommitTestHelper
  include JobTestHelper

  setup do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  def destroy_ability_for(actor:, subject:)
    options = {
      actor_id: actor.ability_id,
      actor_type: actor.ability_type,
      subject_id: subject.ability_id,
      subject_type: subject.ability_type,
    }

    abilities = Ability.where(options)
    assert_equal 1, abilities.length

    abilities.destroy_all

    abilities = Ability.where(options)
    assert_equal 0, abilities.length
  end

  unless GitHub.enterprise?
    test "enqueues job" do
      self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      ArchiveDanglingForksJob.perform_later
      assert_enqueued_jobs 1, only: ArchiveDanglingForksJob, queue: :archive_dangling_forks
    end

    test "archives all dangling forks" do
      owner = create(:user, login: "owner")
      organization = create(:organization, admin: owner)
      organization.allow_private_repository_forking(actor: owner)

      member = create(:user, login: "member")
      organization.add_member(member)

      parent_repository = create(:private_repository, owner: organization, name: "parent-repository", from_example: :simple)
      member_fork = create(:fork_repository, forker: member, fork_repo: parent_repository)

      other_parent = create(:private_repository, owner: organization, from_example: :simple)
      assert other_parent.readable_by?(member)

      another_fork, status = other_parent.fork(forker: member)

      destroy_ability_for(actor: member, subject: organization)
      refute other_parent.readable_by?(member)

      start_id = Repository.minimum(:id)
      ArchiveDanglingForksJob.perform_later(start_id)

      assert Repositories::Public.is_deleted?(member_fork.id), "should have deleted member_fork"
      assert Repositories::Public.is_deleted?(another_fork.id), "should have deleted another_fork"
    end

    test "archives all dangling forks in a multi-tenant enterprise" do
      on_multi_tenant_enterprise do
        owner = create(:emu)
        business = owner.enterprise_managed_business
        member = create(:emu, business: business)
        GitHub::CurrentTenant.set(business)

        organization = create(:organization, admin: owner)
        organization.business.allow_private_repository_forking(actor: owner, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

        organization.add_member(member)

        parent_repository = create(:private_repository, owner: organization, name: "parent-repository", from_example: :simple)
        member_fork = create(:fork_repository, forker: member, fork_repo: parent_repository)

        other_parent = create(:private_repository, owner: organization, from_example: :simple)
        assert other_parent.readable_by?(member)

        another_fork, status = other_parent.fork(forker: member)

        destroy_ability_for(actor: member, subject: organization)

        start_id = Repository.minimum(:id)

        # Unset the tenant for the job run
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get
        refute_predicate GitHub::CurrentTenant, :unscoped?
        refute parent_repository.reload.owner
        # The call to exempt_from_tenant_context_requirement gets broken by the non-MT tests loading ArchiveDanglingForksJob
        # first, so this is a workaround to test running the job with unscoped queries
        ArchiveDanglingForksJob.any_instance.stubs(:unscope_tenant_queries?).returns(true)
        ArchiveDanglingForksJob.perform_later(start_id)

        assert Repositories::Public.is_deleted?(member_fork.id), "should have deleted member_fork"
        assert Repositories::Public.is_deleted?(another_fork.id), "should have deleted another_fork"
      end
    end

    test "#perform_with_retry enqueues the next batch upon finishing" do
      self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      batch_size = 10
      next_start = batch_size + 1

      ArchiveDanglingForksJob.stub_const(:BATCH_SIZE, batch_size) do

        # stub the run method as we're not interested in testing that it runs
        DataQuality::RepositoryNetwork::DanglingForks.any_instance.stubs(:run)

        # ensure the max_id value is larger than the batch size, to enqueue another task
        DataQuality::RepositoryNetwork::DanglingForks.any_instance.stubs(:max_id).returns(batch_size + 5)

        ArchiveDanglingForksJob.expects(:perform_later).with(next_start)
        ArchiveDanglingForksJob.perform_now
      end
    end

    def create_dangling_fork
      owner = create(:user, login: "owner")
      organization = create(:organization, admin: owner)
      organization.allow_private_repository_forking(actor: owner)

      member = create(:user, login: "member")
      organization.add_member(member)

      parent_repository = create(:private_repository, owner: organization, name: "parent-repository", from_example: :simple)
      member_fork = create(:fork_repository, forker: member, fork_repo: parent_repository)

      other_parent = create(:private_repository, owner: organization, from_example: :simple)
      assert other_parent.readable_by?(member)

      destroy_ability_for(actor: member, subject: organization)
      refute other_parent.readable_by?(member)
    end

    test "retry conditions" do
      create_dangling_fork
      assert_retry_on_dirty_exit job: ArchiveDanglingForksJob, args: []
      assert_retry_on_throttler_error job: ArchiveDanglingForksJob, args: []
    end

  end
end
