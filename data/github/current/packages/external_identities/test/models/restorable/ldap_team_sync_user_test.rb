# typed: true
# frozen_string_literal: true

require "test_helper"

class RestorableLdapTeamSyncUserTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @member = create(:user)
    @org = create(:organization)
    @org.allow_private_repository_forking(actor: @org.admins.first)
    @org.add_member(@member)
    @repo = create :private_repository, owner: @org, from_example: :simple
    @team = create :team, organization: @org
    @team.add_member(@member)
    @repo_fork, status = @repo.fork(forker: @member)
    assert_equal :created, status
    example_repo :simple, @repo_fork
  end

  setup do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  test "save user forks" do
    restorable = Restorable::LdapTeamSyncUser.start(@team, @member)
    restorable.save_user_forks

    @repo_fork.remove(@member)
    assert_nil Repositories::Public.find_active(@repo_fork.id)

    restorables = Restorable::LdapTeamSyncUser.team_restorables(@team)
    assert_equal 1, restorables.count
    restorables.each { |r| r.restore }
    assert Repositories::Public.find_active(@repo_fork.id)
  end

  test "restore user fork fails if user cannot access parent repo" do
    restorable = Restorable::LdapTeamSyncUser.start(@team, @member)
    restorable.save_user_forks

    @org.remove_member!(@member)
    assert_nil Repositories::Public.find_active(@repo_fork.id)

    restorables = Restorable::LdapTeamSyncUser.team_restorables(@team)
    restorables.each { |r| r.restore }
    assert_nil Repositories::Public.find_active(@repo_fork.id)
  end

  test "restores user fork noop if restorable is purged" do
    Timecop.freeze do
      restorable = Restorable::LdapTeamSyncUser.start(@team, @member)
      restorable.save_user_forks

      @repo_fork.remove(@member)

      PurgeRestorablesJob.perform_now(expiration: Time.now + 1.year)
    end

    restorables = Restorable::LdapTeamSyncUser.team_restorables(@team)
    restorables.each { |r| r.restore }
    assert_nil Repositories::Public.find_active(@repo_fork.id)
  end

  test "restore user fork noop if user already has fork in network" do
    restorable = Restorable::LdapTeamSyncUser.start(@team, @member)
    restorable.save_user_forks

    @org.remove_member!(@member)
    assert_nil Repositories::Public.find_active(@repo_fork.id)

    Repository.any_instance.stubs(:find_fork_in_network_for_user).returns(@repo)
    restorables = Restorable::LdapTeamSyncUser.team_restorables(@team)
    restorables.each { |r| r.restore }
    assert_nil Repositories::Public.find_active(@repo_fork.id)
  end
end if GitHub.enterprise?
