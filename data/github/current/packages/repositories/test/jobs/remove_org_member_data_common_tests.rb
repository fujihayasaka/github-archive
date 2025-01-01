# typed: true
# frozen_string_literal: true

# Common tests for classes which derive from RemoveOrgMemberDataJob
module RemoveOrgMemberDataCommonTests
  extend T::Helpers

  requires_ancestor { GitHub::TestCase }

  def verify_throttling(job_class, org, user)
    GitHub::Throttler::Null.any_instance.stubs(:throttle).raises(Freno::Throttler::Error)
    assert_enqueued_with(job: job_class, args: [org, user]) do
      job_class.perform_now(org, user)
    end
  end

  def verify_no_failbot_calls_by_default(job_class, org, user)
    user2, user2_fork, _ = setup_forks_for_user(org)

    assert user2_fork.plan_owner

    Failbot.expects(:report).never
    job_class.perform_now(org, user2)
  end

  def perform_bad_network_test(job_class, org, user)
    user2, user2_fork, _ = setup_forks_for_user(org)

    create_bad_network(user2_fork)
    assert_nil user2_fork.network.root
    assert_nil user2_fork.repository.reload.plan_owner
    assert_nil user2_fork.plan_owner

    # nil plan_owner means we skip removal and report bad network to Failbot
    Failbot.expects(:report).once
    job_class.perform_now(org, user2)
  end

  def setup_forks_for_user(org)
    user = create(:user)
    org.add_member(user)
    repo = create :private_repository, owner: org
    user_fork, reason = repo.fork(forker: user)

    repo2 = create :private_repository, owner: org
    user_fork2, reason2 = repo2.fork(forker: user)

    perform_enqueued_jobs(only: RevokeOrgMembershipAbilitiesJob) do
      org.remove_member!(user_fork.owner, save_settings: false)
    end

    [user, user_fork, user_fork2]
  end

  def create_bad_network(repository)
    network = repository.network
    network.root_id = Repository.last!.id + rand(1000..2000)
    network.save
  end
end
