# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTeamTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @org   = create :organization, admin: @owner
    @team  = create(:team, organization: @org)
    @team2 = create(:team, organization: @org)
    @user  = create(:user)
    @user2 = create(:user)
    @repo  = create(:repository, :minimal, owner: @org)
    @repo2 = create(:repository, :minimal)
    @repo3 = create(:repository, :minimal, owner: @org)

    @user3 = create(:user)
    @team2.add_member @user3
  end

  setup do
    GitHub.flipper[:discard_stratocaster_fanout].disable
    T.let(GitHub, T.untyped).reset_stratocaster
  end

  test "can have users added" do
    @team.add_member @user
    assert_equal [@user], @team.members
  end

  test "doesn't send a notification when there are 0 repos" do
    ActionMailer::Base.deliveries.clear
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      @team.add_member @user
    end
  end

  test "doesn't send a notification when repos get added" do
    ActionMailer::Base.deliveries.clear
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      @team.add_repository @repo3, :pull
    end
  end

  test "can't have users added multiple times" do
    @team.add_member @user
    @team.add_member @user
    assert_equal [@user], @team.members
  end

  test "can't have orgs added" do
    @team.add_member @user
    @team.add_member create(:organization, admin: @user)
    assert_equal [@user], @team.members
  end

  test "can have repos added" do
    @team.add_repository @repo, :pull
    assert_equal [@repo], @team.batched_repositories
  end

  test "notifies owners when a repo is created" do
    repo = T.let(nil, T.nilable(Repository))

    GitHub.newsies.get_and_update_settings(@owner) do |settings|
      settings.auto_subscribe = true
    end

    only = [Newsies::AutoSubscribeUsersToRepositoryJob, ProcessEventJob, UpdateEventFeedsJob]
    perform_enqueued_jobs(only: only) { repo = create :repository, :full_creation, owner: @org }
    assert @owner.watching_repo?(repo), "owner should be subscribed to repo"

    events = @owner.events(type: :org, param: @org)
    assert_equal %w(CreateEvent), events.map(&:event_type)
  end

  test "notifies team members when a repo is created in a team" do
    @team.add_member @user2

    repo = T.let(nil, T.nilable(Repository))
    only = [ProcessEventJob, UpdateEventFeedsJob]
    perform_enqueued_jobs(only: only) do
      result = Repository.handle_creation(
        @owner, @org.login,
        { name: "team_repo",
          team_id: @team.id,
          public: true }
      )
      assert result.success, "could not create repo!"
      repo = result.repository
    end

    assert_includes @team.batched_repositories, repo

    events = @user2.events(type: :org, param: @org)
    assert_equal %w(CreateEvent), events.map(&:event_type)
  end

  test "can't have repos added multiple times" do
    @team.add_repository @repo, :pull
    @team.add_repository @repo, :pull
    assert_equal [@repo], @team.batched_repositories
  end

  test "can't have repos not belonging to the organization added" do
    @team.add_repository @repo2, :pull
    assert_equal [], @team.batched_repositories
  end

  test "knows its permission level" do
    assert  @team.pull?
    assert  @team.pull_only?
    assert !@team.push_only?
    assert !@team.admin?
    assert !@team.push?
  end

  test "can't have the same name as another team in its org" do
    refute build(:team, organization: @org, name: @team.name).valid?
  end

  test "can have the same name as another team in another org" do
    owner = create(:user)
    org   = create(:organization, admin: owner)
    assert create(:team, organization: org, name: @team.name).valid?
  end

  test "doesn't remove public members in other teams on delete" do
    GitHub.context.push(actor_id: @owner.id)
    @team.add_member @user
    @team2.add_member @user
    @org.publicize_member @user
    assert_equal 1, @org.public_members.size

    @team.destroy
    assert_equal 1, @org.public_members.size
  end

  test "doesn't delete public members in other teams when removed from a team" do
    @team.add_member @user
    @team2.add_member @user
    @org.publicize_member @user
    assert_equal 1, @org.public_members.size

    @team.remove_member(@user)
    assert_equal @user, @user.reload
    assert_equal 1, @org.public_members.size
  end

  test "deletes user from all teams when removing from organization" do
    @team.add_member @user
    @team2.add_member @user

    @repo.update! private: true
    @team.add_repository @repo, :pull
    @user.watch_repo @repo

    assert @user.watching_repo?(@repo)
    assert_same_elements [@team, @team2], @org.teams_for(@user)
    perform_enqueued_jobs(only: RevokeOrgMembershipAbilitiesJob) do
      @org.remove_member! @user
      assert_equal @user, @user.reload
      assert_equal [], @org.teams_for(@user)
      assert_equal [], @repo.teams_for(@user)
    end
  end

  test "cancels any pending join requests for a user when removing from organization" do
    @org.add_member @user
    request = @team.request_membership(@user)
    request2 = @team2.request_membership(@user)
    assert_equal 1, @team.pending_team_membership_requests.count
    assert_equal 1, @team2.pending_team_membership_requests.count

    perform_enqueued_jobs(only: [CancelTeamMembershipRequestsJob]) do
      @org.remove_member!(@user)
    end

    assert_empty @team.reload.pending_team_membership_requests
    assert_empty @team2.reload.pending_team_membership_requests
  end

  test "cancels any pending join requests for a user when converting to outside collaborator" do
    @org.add_member @user
    request = @team.request_membership(@user)
    request2 = @team2.request_membership(@user)
    assert_equal 1, @team.pending_team_membership_requests.count
    assert_equal 1, @team2.pending_team_membership_requests.count

    perform_enqueued_jobs(only: [CancelTeamMembershipRequestsJob, RemoveOrgMemberJob]) do
      @org.convert_to_outside_collaborator!(@user)
    end

    assert_empty @team.reload.pending_team_membership_requests
    assert_empty @team2.reload.pending_team_membership_requests
  end

  test "cancels any pending join requests for a user when promoting to owner" do
    @org.add_member @user
    request = @team.request_membership(@user)
    request2 = @team2.request_membership(@user)
    assert_equal 1, @team.pending_team_membership_requests.count
    assert_equal 1, @team2.pending_team_membership_requests.count

    perform_enqueued_jobs(only: [CancelTeamMembershipRequestsJob]) do
      @org.update_member(@user, action: :admin)
    end

    assert_empty @team.reload.pending_team_membership_requests
    assert_empty @team2.reload.pending_team_membership_requests
  end

  test "sends an email when user is removed from organization" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # Does not send email notifications for bulk removals
    user = create(:user)
    @org.add_member user
    assert @org.direct_or_team_member? user

    ActionMailer::Base.deliveries.clear

    assert_difference "ActionMailer::Base.deliveries.size" do
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) { @org.remove_member! user }
    end
  end

  test "does not enqueue ClearTeamMembership job when removed from org" do
    user = create(:user)
    @org.add_member user

    GitHub.context.push(actor_id: @owner.id) do
      perform_enqueued_jobs(only: RevokeOrgMembershipAbilitiesJob) do
        @org.remove_member!(user)
      end
    end

    assert_enqueued_jobs 0, only: ClearTeamMembershipsJob, queue: :team_remove_members
  end

  test "enqueues jobs to purge incidental relations when removed from org" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # Bulk removals do not queue all these jobs
    user = create(:user)
    @org.add_member user

    GitHub.context.push(actor_id: @owner.id) do
      @org.remove_member!(user)
      perform_enqueued_jobs(only: RevokeOrgMembershipAbilitiesJob)
    end

    assert_enqueued_jobs 1, only: RemoveOrgMemberForksJob, queue: :archive_restore
    assert_enqueued_jobs 1, only: RemoveOrgMemberRepositoryStarsJob, queue: :remove_org_member_repository_stars
    assert_enqueued_jobs 1, only: RemoveOrgMemberWatchedRepositoriesJob, queue: :remove_org_member_watched_repositories
    assert_enqueued_jobs 1, only: RemoveOrgMemberIssueAssignmentsJob, queue: :remove_org_member_issue_assignments
  end

  test "enqueues a job to restore a user's membership" do
    restorable_org_user = create(:restorable_organization_user, :complete)
    invitee = restorable_org_user.user
    org = restorable_org_user.organization

    assert_enqueued_with job: RestoreOrganizationUserJob, queue: "restore_organization_user" do
      org.restore_membership(invitee, actor: create(:user))
    end
  end

  test "does not trigger notifying user of removal from teams, when removed from org" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # Bulk removals do not notify user of removal from orgs
    user = create(:user)
    @org.add_member(user)
    @team.add_member(user)
    ActionMailer::Base.deliveries.clear
    assert @org.direct_or_team_member?(user)
    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      @org.remove_member!(user)

      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.first
      assert_match /#{@org.safe_profile_name}/, mail.text_part.body.to_s
      refute_match /#{@team.name}/, mail.text_part.body.to_s
    end
  end
end
