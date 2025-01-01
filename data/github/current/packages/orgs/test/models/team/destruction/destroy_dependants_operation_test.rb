# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamDestructionDestroyDependantsOperationTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @owner = create(:user)
    @org = create :organization, plan: "bronze", admin: @owner
    @org.update_default_repository_permission(:none, actor: @owner)
    @grand_parent_team = create :team, organization: @org, privacy: :closed, name: "employees"
    @parent_team = create :team, organization: @org, privacy: :closed, name: "marketing",   parent_team_id: @grand_parent_team.id, ldap_mapping: LdapMapping.new(dn: "cn=enterprise,ou=groups,dc=github,dc=com")
    @team  = create :team, organization: @org, privacy: :closed, name: "opensource",  parent_team_id: @parent_team.id
  end

  setup do
    ActionMailer::Base.deliveries.clear
  end

  def destroy(team, org_destroyed: false, with_instrumentation: true)
    affected = team.descendants + [team]
    info = Team::Destruction::DestroyOperation.team_info_for_dependants_destruction(affected)
    org_id = @org.id

    @org.delete if org_destroyed
    Team::Destruction::DestroyDependantsOperation.new(org_id, info).execute(with_instrumentation: with_instrumentation)
  end

  def abilities_participating(participant)
    where_actors   = Ability.where(actor_type: participant.ability_type, actor_id: participant.ability_id, priority: [Ability.priorities[:direct], Ability.priorities[:indirect]]).to_a
    where_subjects = Ability.where(subject_type: participant.ability_type, subject_id: participant.ability_id, priority: [Ability.priorities[:direct], Ability.priorities[:indirect]]).to_a
    where_actors + where_subjects
  end

  test "coerces team info, so argument serialization is not important" do
    create(:team_membership_request, team: @team)
    affected = @team.descendants + [@team]
    org_id = @org.id
    info = Team::Destruction::DestroyOperation
      .team_info_for_dependants_destruction(affected)

    # simulate Resque's JSON encoding of job arguments
    info = JSON.parse(info.to_json)
    operation = Team::Destruction::DestroyDependantsOperation.new(org_id, info)

    assert_equal info.keys.first.to_i, operation.team_ids_to_info.keys.first
    info.values.first.each do |(key, _val)|
      assert_includes operation.team_ids_to_info.values.first.keys, key.to_sym
    end
  end

  test "destroys membership requests" do
    create(:team_membership_request, team: @parent_team)
    create(:team_membership_request, team: @team)

    assert_difference "TeamMembershipRequest.count", -2 do
      destroy @parent_team
    end
  end

  test "destroys team invitations" do
    create(:team_invitation, team: @parent_team, organization_invitation: create(:organization_invitation, organization: @org))
    create(:team_invitation, team: @team, organization_invitation: create(:organization_invitation, organization: @org))

    assert_equal 2, TeamInvitation.count
    assert_equal 2, OrganizationInvitation.count

    destroy @parent_team

    assert_equal 0, TeamInvitation.count
    assert_equal 2, OrganizationInvitation.count
  end

  if GitHub.enterprise?
    test "destroys ldap mappings" do
      assert_difference("LdapMapping.count", -1) do
        destroy @parent_team
      end
    end
  end

  test "destroy team review_requests " do
    owner = create :user, login: "owner", plan: "large"
    user = create(:user)

    reviewer = create(:user, login: "reviewer")

    org = create :organization, login: "acme", admin: user, plan: "business", seats: 10
    collab_1     = create :user, login: "collab-1"
    collab_2     = create :user, login: "collab-2"
    collab_3     = create :user, login: "collab-3"
    team = create(:team, organization: org, name: "Employee", privacy: :closed)

    repo = create :repository, owner: org, from_example: :rebase_pull_request
    repo.add_member user
    repo.add_member collab_1
    repo.add_member collab_2
    repo.add_member collab_3, action: :read
    repo.add_member owner
    team.add_member collab_1
    team.add_member reviewer
    team.add_repository(repo, :push)

    pull = create :pull_request,
      repository:       repo,
      base_repository:  repo,
      base_user:        repo.owner,
      base_ref:         "master",
      head_repository:  repo,
      head_user:        repo.owner,
      head_ref:         "contrib",
      draft:            false


    request = pull.review_requests.build(reviewer: team)
    request.save!

    assert pull.review_requested_for? team

    review = pull.pending_review_for(user: reviewer)
    review.approve!
    assert_empty pull.pending_review_requests
    refute_empty pull.review_requests

    destroy team
    review.reload
    pull.reload
    assert_empty pull.review_requests

  end

  test "destroys team group mappings" do
    create(:team_group_mapping, team: @parent_team)

    assert_difference("Team::GroupMapping.count", -1) do
      destroy @parent_team
    end
  end

  context "revokes user permissions" do
    test "destroys abilities and queues a team_remove_members job to destroy membership information" do
      user = create(:user)
      repo = create(:private_repository, owner: @org)

      @grand_parent_team.add_member user
      @team.add_member user
      @team.add_repository(repo, :push)

      refute_empty abilities_participating(@parent_team)
      refute_empty abilities_participating(@team)
      refute_empty abilities_participating(@grand_parent_team)

      destroy @parent_team

      assert_empty abilities_participating(@parent_team)
      assert_empty abilities_participating(@team)
      refute_empty abilities_participating(@grand_parent_team)

      assert_enqueued_jobs 1, only: ClearTeamMembershipsJob, queue: :team_remove_members
    end

    test "destroys abilities but doesn't queue a team_remove_members job to destroy membership information if the org doesn't exist" do
      user = create(:user)
      repo = create(:private_repository, owner: @org)

      @grand_parent_team.add_member user
      @team.add_member user
      @team.add_repository(repo, :push)

      refute_empty abilities_participating(@parent_team)
      refute_empty abilities_participating(@team)
      refute_empty abilities_participating(@grand_parent_team)

      destroy @parent_team, org_destroyed: true

      assert_empty abilities_participating(@parent_team)
      assert_empty abilities_participating(@team)
      refute_empty abilities_participating(@grand_parent_team)

      assert_enqueued_jobs 0, only: ClearTeamMembershipsJob, queue: :team_remove_members
    end

    test "destroys membership information if all jobs are run" do
      user = create(:user)
      repo = create(:private_repository, owner: @org)

      @team.add_member user
      @team.add_repository(repo, :push)

      assert_able user, :write, repo

      destroy @parent_team

      refute_able user, :write, repo
    end

    test "destroys abilities even when a repository is destroyed" do
      user = create(:user)
      repo = create(:private_repository, owner: @org)

      @grand_parent_team.add_member user
      @team.add_member user
      @team.add_repository(repo, :push)
      repo.destroy!

      events = subscribe "team.remove_repository"
      expected_payload = {
        team: @team.name,
        team_id: @team.id,
        repo: nil,
        repo_id: repo.id,
        ldap_mapped: @team.ldap_mapped?,
        org: @org.login,
        org_id: @org.id,
      }

      destroy @parent_team

      assert event = events.pop
      assert_equal expected_payload, event.payload
      assert_enqueued_jobs 1, only: ClearTeamMembershipsJob, queue: :team_remove_members
    end

    if GitHub.user_abuse_mitigation_enabled?
      test "destroys moderator abilities" do
        @org.moderation.add_moderator(@parent_team, actor: @owner)
        assert @org.moderator?(@parent_team)

        user = create(:user)
        repo = create(:private_repository, owner: @org)

        @grand_parent_team.add_member user
        @team.add_member user
        @team.add_repository(repo, :push)

        refute_empty abilities_participating(@parent_team)
        refute_empty abilities_participating(@team)
        refute_empty abilities_participating(@grand_parent_team)

        destroy @parent_team

        assert_empty abilities_participating(@parent_team)
        assert_empty abilities_participating(@team)
        refute_empty abilities_participating(@grand_parent_team)
      end
    end

    test "sends webhooks" do
      user = create(:user)
      repo = create(:private_repository, owner: @org)
      @team.add_member user
      @team.add_repository(repo, :push)

      event_data = {
        action: :removed,
        member_id: user.id,
        member_login: user.login,
        team_id: @team.id,
        team_name: @team.name,
        organization_id: @org.id,
        actor_id: 666,
      }
      GitHub.context.push(actor_id: 666)
      Hook::Event::MembershipEvent.expects(:queue).with(equals(event_data)).once

      destroy @parent_team
    end

    test "doesn't send webhooks if org destroyed" do
      user = create(:user)
      repo = create(:private_repository, owner: @org)
      @team.add_member user
      @team.add_repository(repo, :push)

      Hook::Event::MembershipEvent.expects(:queue).never.with do |event|
        :removed == event[:action]
      end

      destroy @parent_team, org_destroyed: true
    end

    test "sends email notifications" do
      user = create(:user)
      repo = create(:private_repository, owner: @org)

      @team.add_member user
      @team.add_repository(repo, :push)

      assert_difference "ActionMailer::Base.deliveries.count", 1 do
        destroy @parent_team
      end
    end

    test "doesn't send email notifications if org destroyed" do
      user = create(:user)
      repo = create(:private_repository, owner: @org)

      @team.add_member user
      @team.add_repository(repo, :push)

      assert_difference "ActionMailer::Base.deliveries.size", 0 do
        destroy @parent_team, org_destroyed: true
      end
    end

    test "clears forks by queueing a remove-forks-for-inaccessible-repositories job for members and repos" do
      user = create(:user)
      repo = create(:private_repository, owner: @org)

      @team.add_member user
      @team.add_repository(repo, :push)

      assert_enqueued_jobs 2, only: RemoveForksForInaccessibleRepositoriesJob, queue: "sync_organization_default_repository_permission" do
        destroy @parent_team
      end

      assert_enqueued_with(job: RemoveForksForInaccessibleRepositoriesJob, args: [[repo.id], [user.id]], queue: "sync_organization_default_repository_permission")
    end

    test "enqueues CleanUpDeletedTeamAbilitiesJob for deleted teams" do
      user = create :user
      repo = create :private_repository, owner: @org

      @grand_parent_team.add_member user
      @team.add_member user
      @team.add_repository repo, :push

      refute_empty abilities_participating(@parent_team)
      refute_empty abilities_participating(@team)
      refute_empty abilities_participating(@grand_parent_team)

      Timecop.freeze do
        assert_enqueued_jobs 4, only: CleanUpDeletedTeamAbilitiesJob, queue: :clean_up_deleted_team_abilities do
          destroy @parent_team
        end

        assert_empty abilities_participating(@parent_team)
        assert_empty abilities_participating(@team)
        refute_empty abilities_participating(@grand_parent_team)

        assert_enqueued_with \
          job: CleanUpDeletedTeamAbilitiesJob,
          at: 1.hour.from_now,
          args: [@parent_team.id],
          queue: "clean_up_deleted_team_abilities"
        assert_enqueued_with \
          job: CleanUpDeletedTeamAbilitiesJob,
          at: 12.hours.from_now,
          args: [@parent_team.id],
          queue: "clean_up_deleted_team_abilities"

        assert_enqueued_with \
          job: CleanUpDeletedTeamAbilitiesJob,
          at: 1.hour.from_now,
          args: [@team.id],
          queue: "clean_up_deleted_team_abilities"
        assert_enqueued_with \
          job: CleanUpDeletedTeamAbilitiesJob,
          at: 12.hours.from_now,
          args: [@team.id],
          queue: "clean_up_deleted_team_abilities"
      end
    end
  end

  test "destroys the team's discussion posts and replies" do
    post = create(:discussion_post, team: @parent_team)
    create(:discussion_post_reply, discussion_post: post)
    create(:discussion_post, team: @team)

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
      assert_difference("DiscussionPost.count", -2) do
        assert_difference("DiscussionPostReply.count", -1) do
          destroy @parent_team
        end
      end
    end
  end

  test "destroys reactions to discussion posts and replies" do
    parent_post = create(:discussion_post, team: @parent_team)
    Reaction.react(
      user: parent_post.user,
      subject_id: parent_post.id,
      subject_type: "DiscussionPost",
      content: "+1",
    )

    post = create(:discussion_post, team: @team)
    Reaction.react(
      user: post.user,
      subject_id: post.id,
      subject_type: "DiscussionPost",
      content: "+1",
    )

    reply = create(:discussion_post_reply, discussion_post: post)
    Reaction.react(
      user: reply.user,
      subject_id: reply.id,
      subject_type: "DiscussionPostReply",
      content: "+1",
    )

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
      assert_difference("Reaction.count", -3) do
        destroy @parent_team
      end
    end
  end

  test "queues a job to delete all data in newsies for team and descendents" do
    Notifications::Subscriptions.expects(:async_delete_list_subscriptions).with do |*args|
      args[0].type == "Team" && args[0].id == @parent_team.id
    end
    Notifications::Subscriptions.expects(:async_delete_list_subscriptions).with do |*args|
      args[0].type == "Team" && args[0].id == @team.id
    end

    perform_enqueued_jobs(only: [RemoveForksForInaccessibleRepositoriesJob]) do
      destroy @parent_team
    end
  end

  test "does not log when with_instrumentation false" do
    assert_performed_audit_entries(count: 0, only: "team.destroy") do
      destroy @team, with_instrumentation: false
    end
  end

  test "logs when with_instrumentation true" do
    assert_performed_audit_entries(count: 1, only: "team.destroy") do
      destroy @team, with_instrumentation: true
    end
  end
end

class NonEmuTeamDestructionDestroyDependantsOperationTest < GitHub::TestCase
  setup do
    @business = create :business
    @org_with_business = create :organization, business: @business
    @enterprise_team = create :enterprise_team, business: @business, sync_to_organizations: "all"
    @org_team = create :team, organization: @org_with_business
    @org_mapping = EnterpriseTeamOrganizationMapping.create(enterprise_team: @enterprise_team, organization: @org_with_business, team: @org_team)

    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

    @user = create :user
    @business.add_user_accounts([@user.id])
  end

  def destroy(team, org, org_destroyed: false)
    affected = team.descendants + [team]
    info = Team::Destruction::DestroyOperation.team_info_for_dependants_destruction(affected)
    org_id = org.id

    org.delete if org_destroyed
    Team::Destruction::DestroyDependantsOperation.new(org_id, info).execute
  end

  test "destroys enterprise team organization membership entries" do
    @enterprise_team.bulk_add_members(users: [@user])
    perform_enqueued_jobs only: [EnterpriseTeamOrganizationReconciliationRunnerJob, OrganizationBulkAddMembersJob] do
      EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: @enterprise_team.id)
    end

    assert OrganizationMembershipEntry.where(organization: @org_with_business, user: @user, adder_type: :enterprise_team).exists?

    assert_difference "OrganizationMembershipEntry.where(adder_type: :enterprise_team).count", -1 do
      perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
        destroy @org_team, @org_with_business
        assert_not @org_with_business.members.include?(@user)
      end
    end
  end

  test "destroys enterprise team organization membership entries, remains in org" do
    # Add the user before the enterprise team does
    @org_with_business.add_member(@user)

    # ET creates an org membership entry
    @enterprise_team.bulk_add_members(users: [@user])
    perform_enqueued_jobs only: [EnterpriseTeamOrganizationReconciliationRunnerJob, OrganizationBulkAddMembersJob] do
      EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: @enterprise_team.id)
    end

    assert OrganizationMembershipEntry.where(organization: @org_with_business, user: @user, adder_type: :enterprise_team).exists?

    # OME is destroyed
    assert_difference "OrganizationMembershipEntry.where(adder_type: :enterprise_team).count", -1 do
      perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
        destroy @org_team, @org_with_business
        # User remains in the org
        assert @org_with_business.members.include?(@user)
      end
    end
  end
end unless GitHub.single_business_environment?


module TeamDestructionDestroyOrgMembershipEntrySharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def destroy(team, org, org_destroyed: false)
    affected = team.descendants + [team]
    info = Team::Destruction::DestroyOperation.team_info_for_dependants_destruction(affected)
    org_id = org.id

    org.delete if org_destroyed
    Team::Destruction::DestroyDependantsOperation.new(org_id, info).execute
  end

  def test_destroys_organization_membership_entries_and_external_group_team
    assert @external_group_users[0].in?(@org_with_business.members)
    assert @external_group_users[1].in?(@org_with_business.members)

    assert_difference "OrganizationMembershipEntry.count", -2 do
      assert_difference "ExternalGroupTeam.count", -1 do
        perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
          destroy @team_with_external_group, @org_with_business
        end
      end
    end

    refute @external_group_users[0].in?(@org_with_business.members)
    refute @external_group_users[1].in?(@org_with_business.members)
  end

  def test_does_not_remove_org_membership_if_user_is_also_a_direct_member_of_the_org
    @unlinked_team = create :team, organization: @org_with_business
    @unlinked_team.add_member(@external_group_users[0])

    assert @external_group_users[0].in?(@org_with_business.members)
    assert @external_group_users[1].in?(@org_with_business.members)

    assert_difference "OrganizationMembershipEntry.count", -2 do
      assert_difference "ExternalGroupTeam.count", -1 do
        perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
          destroy @team_with_external_group, @org_with_business
        end
      end
    end

    assert @external_group_users[0].in?(@org_with_business.members)
    refute @external_group_users[1].in?(@org_with_business.members)
  end

  def test_does_nothing_if_no_external_group_team_or_org_membership_entries
    perform_enqueued_jobs only: [ExternalGroupTeamUnlinkJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
      @external_group_team.destroy
    end

    refute @team_with_external_group.external_group_team.present?
    assert_empty OrganizationMembershipEntry.where(
      organization_id: @org_with_business.id,
      adder_id: [@team_with_external_group.id],
      adder_type: :external_team)

    assert_no_difference "OrganizationMembershipEntry.count" do
      assert_no_difference "ExternalGroupTeam.count" do
        perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
          destroy @team_with_external_group, @org_with_business
        end
      end
    end
  end

  def test_delete_external_group_team
    assert @external_group_users[0].in?(@org_with_business.members)
    assert @external_group_users[1].in?(@org_with_business.members)

    assert_difference "OrganizationMembershipEntry.count", -2 do
      assert_difference "ExternalGroupTeam.count", -1 do
        perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
          destroy @team_with_external_group, @org_with_business
        end
      end
    end

    refute @external_group_users[0].in?(@org_with_business.members)
    refute @external_group_users[1].in?(@org_with_business.members)
  end

  def test_delete_enterprise_team_doesnt_send_remove_emails
    repo = create(:private_repository, owner: @org_with_business)
    @team_with_external_group.add_repository(repo, :push)
    @team_with_external_group.stubs(:enterprise_team_managed?).returns(true)

    team_mailer_stub = TeamsMailer.stubs(:removed_from_team).never

    perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
      destroy @team_with_external_group, @org_with_business
    end
  end
end

class EMUTeamDestructionDestroyDependantsOperationTest < GitHub::TestCase
  include TeamDestructionDestroyOrgMembershipEntrySharedTests

  fixtures do
    @emu = create :emu
    @business = @emu.enterprise_managed_business
    @org_with_business = create :organization, business: @business, admin: @emu

    @external_group_with_members = create :external_group, :with_members, business: @business, number_of_members: 2
    @external_group_users = @external_group_with_members.external_identity_group_memberships.map(&:external_identity).map(&:user)

    @team_with_external_group = create :team, organization: @org_with_business
    @external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team_with_external_group)

    perform_enqueued_jobs only: ExternalGroupTeamLinkJob
  end
end unless GitHub.single_business_environment?

class EMUTeamDestructionDestroyDependantsOperationTestInAllEnvironmentsExceptGHES < GitHub::TestCase
  fixtures do
    @emu = create :emu
    @business = @emu.enterprise_managed_business
    @org_with_business = create :organization, business: @business, admin: @emu

    @enterprise_team = create :enterprise_team, business: @business, sync_to_organizations: "all"
    @managed_org_team = create :team, organization: @org_with_business
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
    @org_mapping = EnterpriseTeamOrganizationMapping.create(enterprise_team: @enterprise_team, organization: @org_with_business, team: @managed_org_team)
  end

  setup do
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
  end

  def destroy(team, org, org_destroyed: false)
    affected = team.descendants + [team]
    info = Team::Destruction::DestroyOperation.team_info_for_dependants_destruction(affected)
    org_id = org.id

    org.delete if org_destroyed
    Team::Destruction::DestroyDependantsOperation.new(org_id, info).execute
  end

  test "destroys enterprise team organization membership entries" do
    @enterprise_team.bulk_add_members(users: [@emu])
    perform_enqueued_jobs only: [EnterpriseTeamOrganizationReconciliationRunnerJob, OrganizationBulkAddMembersJob] do
      EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: @enterprise_team.id)
    end
    assert OrganizationMembershipEntry.where(organization: @org_with_business, user: @emu, adder_type: :enterprise_team).exists?

    assert_difference "OrganizationMembershipEntry.where(adder_type: :enterprise_team).count", -1 do
      perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
        destroy @managed_org_team, @org_with_business
      end
    end
  end

  test "destroy_organization_membership_entries catches on Organization::UnableToRemoveEnterpriseTeamMemberError" do
    @enterprise_team.bulk_add_members(users: [@emu])
    perform_enqueued_jobs only: [EnterpriseTeamOrganizationReconciliationRunnerJob, OrganizationBulkAddMembersJob] do
      EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: @enterprise_team.id)
    end
    assert OrganizationMembershipEntry.where(organization: @org_with_business, user: @emu, adder_type: :enterprise_team).exists?

    assert_silent do
      perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob] do
        destroy @managed_org_team, @org_with_business
      end
    end
  end
end unless GitHub.enterprise?
