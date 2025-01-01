# typed: false
# frozen_string_literal: true

require "test_helper"

module ExternalGroupTeamValidationsSharedTests
  def test_create_an_external_group_team_succeeds
    external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: @team)

    refute_nil external_group_team
    assert_predicate external_group_team, :valid?
    assert_equal @external_group.id, external_group_team.external_group_id
    assert_equal @team.id, external_group_team.team_id
  end

  def test_external_group_required
    external_group_team = ExternalGroupTeam.create(team: @team)

    refute_nil external_group_team
    refute_predicate external_group_team, :valid?
    assert_includes external_group_team.errors[:external_group], "can't be blank"
  end

  def test_team_required
    external_group_team = ExternalGroupTeam.create(external_group: @external_group)

    refute_nil external_group_team
    refute_predicate external_group_team, :valid?
    assert_includes external_group_team.errors[:team], "can't be blank"
  end

  def test_should_belong_to_same_saml_provider
    business = create(:business, :enterprise_managed)
    create :business_saml_provider, business: business
    org = create :business_plus_organization
    business.add_organization(org)
    team = create :team, organization: org
    team.organization.reload
    external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: team)

    refute_nil external_group_team
    refute_predicate external_group_team, :valid?
    assert_includes external_group_team.errors[:team_id], "must belong to the same identity provider as external group"
  end unless GitHub.enterprise?

  def test_team_with_explicit_members_linked_to_a_group_with_members
    @team.add_member(@user)

    assert_predicate @team.members, :any?
    assert_predicate @team, :explicit_members?

    assert @user.in?(@org.members)
    external_group = create(:external_group, :with_members, business: @business, number_of_members: 2)
    external_group_team = ExternalGroupTeam.create(external_group: external_group, team: @team)

    refute_predicate external_group_team, :valid?

    assert_equal 1, @team.members.count
    assert_includes external_group_team.errors[:team_id], "cannot have any members"
  end

  def test_adding_same_member_twice_does_not_throw_an_exception
    external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: @team)
    external_group_team.add_member(@user)

    assert_predicate @team.members, :any?
    assert_equal 1, @team.members.count

    external_group_team.add_member(@user)

    assert_predicate @team.members, :any?
    assert_equal 1, @team.members.count
  end
end

module ExternalGroupTeamProvisioningSharedTests
  include ExternalGroupHelpers

  def test_valid_external_user_membership_provisioning_with_reconcile_job
    external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: @team)
    ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @user.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @another_user.external_identities.first)

    reconcile_external_group_teams(external_group: @external_group)

    assert_same_elements [@user, @another_user], external_group_team.team.members
    # check for org membership update
    assert @user.in?(@org.members)
    assert @another_user.in?(@org.members)
    assert_same_elements [@user, @another_user, @org.admin], @org.members
  end
end

module ExternalGroupTeamDeprovisioningSharedTests
  include ExternalGroupHelpers

  def test_valid_external_user_membership_deprovisioning_with_reconcile_job
    external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: @team)
    ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @user.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @another_user.external_identities.first)

    reconcile_external_group_teams(external_group: @external_group)

    assert_same_elements [@user, @another_user], external_group_team.team.members

    ExternalIdentityGroupMembership.find_by(external_identity: @another_user.external_identities.first).destroy

    reconcile_external_group_teams(external_group: @external_group)

    assert_equal [@user], external_group_team.team.members
    assert @user.in?(@org.members)
    # the current flow shows removing user from team does't mean removing user from org
    assert @another_user.in?(@org.members)
    assert_same_elements [@user, @another_user,  @org.admin], @org.members
  end

  def test_valid_external_user_membership_deprovisioning_when_team_is_deleted_with_reconcile_job
    members_count = @org.members.count

    refute @user.in?(@org.members)
    refute @another_user.in?(@org.members)

    team = create(:team, organization: @org)

    external_group = create :external_group, business: @business
    external_group_team = ExternalGroupTeam.create(external_group: external_group, team: team)
    ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: @user.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: @another_user.external_identities.first)

    reconcile_external_group_teams(external_group: external_group)

    assert_equal 2, team.members.count
    assert_equal members_count + 2, @org.members.count
    assert_same_elements [@user.id, @another_user.id], external_group_team.team.member_ids

    assert @user.in?(@org.members)
    assert @another_user.in?(@org.members)

    assert_difference "ExternalGroupTeam.count", -1 do
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, DestroyTeamDependantsJob]) do
        team.destroy
      end
    end

    refute @user.in?(@org.members)
    refute @another_user.in?(@org.members)
  end
end

module ExternalGroupTeamLinkUnlinkSharedTests
  def test_valid_external_user_membership_provisioning
    external_group_team = nil
    perform_enqueued_jobs(only: ExternalGroupTeamLinkJob) do
      external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)
    end

    assert_same_elements @external_group_users, external_group_team.team.members

    # check for org membership update
    assert @external_group_users[0].in?(@org.members)
    assert @external_group_users[1].in?(@org.members)
    assert_same_elements @external_group_users + [@org.admin], @org.members
  end

  def test_valid_external_user_membership_deprovisioning
    external_group_team = nil
    perform_enqueued_jobs(only: ExternalGroupTeamLinkJob) do
      external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)
    end
    assert_same_elements @external_group_users, external_group_team.team.members

    assert_difference "ExternalGroupTeam.count", -1 do
      perform_enqueued_jobs(only: [ExternalGroupTeamUnlinkJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        external_group_team.destroy
      end

      refute_predicate @team.members, :any?

      # check for org membership update
      refute @external_group_users[0].in?(@org.members)
      refute @external_group_users[1].in?(@org.members)
      assert_same_elements [@org.admin], @org.members
    end
  end

  def test_does_not_crete_membership_for_suspended_external_identity
    @external_group_with_members.external_identity_group_memberships.first.external_identity.disable

    assert_difference "ExternalGroupTeam.count", 1 do
      perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)
      end

      assert_predicate @team.members, :any?

      # check for org membership update
      refute @external_group_users[0].in?(@org.members)
      assert @external_group_users[1].in?(@org.members)
    end
  end

  def test_valid_external_user_membership_relinking_with_reconcile_job
    external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: @team)
    ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @user.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @another_user.external_identities.first)

    reconcile_external_group_teams(external_group: @external_group)

    assert_equal [@user, @another_user], external_group_team.team.members

    perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      external_group_team.external_group = @external_group_with_members
      external_group_team.save

      assert_equal @external_group_with_members.id, external_group_team.external_group_id
    end

    # check for org membership update
    refute @user.in?(@org.members)
    refute @another_user.in?(@org.members)
    assert @external_group_users[0].in?(@org.members)
    assert @external_group_users[1].in?(@org.members)
    assert_same_elements @external_group_users + [@org.admin], @org.members
  end

  def test_valid_unlinking_flow_with_reconcile_job
    external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: @team)
    ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @user.external_identities.first)

    reconcile_external_group_teams(external_group: @external_group)

    perform_enqueued_jobs(only: [ExternalGroupTeamUnlinkJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      external_group_team.destroy
    end
    assert_equal @team.members.count, 0
    refute @user.in?(@team.members)
  end

  def test_optionally_passes_and_logs_caller_param_on_destroy
    external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: @team)

    base_log = {
      "gh.caller" => "ExternalGroupTeam"
    }
    log_1 = base_log.merge({ "info.message" => "Starting external_group_team_unlink job" })
    log_2 = base_log.merge({ "info.message" => "Finished external_group_team_unlink job" })

    assert_logged(**log_1) do
      assert_logged(**log_2) do
        perform_enqueued_jobs(only: ExternalGroupTeamUnlinkJob) do
          external_group_team.destroy
        end
      end
    end
  end
end

module ExternalGroupTeamReconcileMembershipsSharedTests
  extend ActiveSupport::Concern

  included do
    test "does not reconcile if external group is deleted" do
      external_group = nil
      perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        external_group = create(:external_group, :with_members, :with_team, business: @business).reload
      end
      external_group_team = external_group.external_group_teams.first
      external_group.delete

      Team.any_instance.expects(:add_member).never
      Team.any_instance..expects(:remove_member).never

      external_group_team.reconcile_memberships
    end

    test "does not reconcile if team is deleted" do
      external_group = nil
      perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        external_group = create(:external_group, :with_members, :with_team, business: @business).reload
      end
      external_group_team = external_group.external_group_teams.first
      external_group_team.team.delete

      Team.any_instance.expects(:add_member).never
      Team.any_instance.expects(:remove_member).never

      external_group_team.reconcile_memberships
    end

    test "rescues ActiveRecord::RecordNotFound when team is deleted and reloaded" do
      external_group = nil
      perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        external_group = create(:external_group, :with_members, :with_team, business: @business).reload
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team
      org = team.organization
      member1 = team.members.first
      member2 = team.members.second
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        team.remove_member(member1, force: true)
        team.remove_member(member2, force: true)
        org.remove_member(member1)
        org.remove_member(member2)
      end

      refute team.member?(member1)
      refute team.member?(member2)
      refute org.member?(member1)
      refute org.member?(member2)
      refute_equal external_group.members.count, team.members.count

      team.destroy

      expected_log = {
        "code.namespace" => "ExternalGroupTeam",
        "code.function" => "reconcile_memberships",
        "exception.message" => "Couldn't find Team with",
        "gh.external_group_team.id" => external_group_team.id,
        "gh.external_group.name" => external_group.display_name,
        "gh.external_group.id" => external_group.id,
        "gh.team.name" => team.name,
        "gh.team.id" => team.id,
      }

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        assert_logged(**expected_log) do
          external_group_team.reconcile_memberships
        end
      end

      # DestroyDependantsOperation removes all org membership entries for this team.
      refute OrganizationMembershipEntry.where(organization_id: team.organization_id, adder_id: team.id, adder_type: :external_team).any?
      refute org.member?(member1)
      refute org.member?(member2)
      refute team.member?(member1)
      refute team.member?(member2)
    end

    test "does not reconcile if external group members matches team members" do
      external_group = nil
      perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        external_group = create(:external_group, :with_members, :with_team, business: @business).reload
      end
      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      Team.any_instance.expects(:add_member).never
      Team.any_instance..expects(:remove_member).never

      external_group_team.reconcile_memberships
    end

    test "passes and logs caller param on create" do
      external_group = nil

      assert_enqueued_jobs(1, only: ExternalGroupTeamLinkJob) do
        external_group = create(:external_group, :with_members, :with_team, business: @business).reload
      end

      external_group_team = external_group.external_group_teams.first

      base_log = {
        "gh.caller" => "ExternalGroupTeam"
      }
      log_1 = base_log.merge({ "info.message" => "Starting external_group_team_link job" })
      log_2 = base_log.merge({ "info.message" => "Finished external_group_team_link job" })

      assert_logged(**log_1) do
        assert_logged(**log_2) do
          perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
            external_group = create(:external_group, :with_members, :with_team, business: @business).reload
          end
        end
      end
    end

    test "reconciles when team has less users than the external group" do
      external_group = nil
      perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        external_group = create(:external_group, :with_members, :with_team, business: @business).reload
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      remove_member = team.members.first
      team.remove_member(remove_member, force: true)
      refute_same_elements external_group.member_user_ids, team.reload.member_ids

      external_group_team.reconcile_memberships
      assert_same_elements external_group.reload.member_user_ids, team.reload.member_ids
    end

    test "reconciles when team has more users than the external group" do
      external_group = nil
      perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        external_group = create(:external_group, :with_members, :with_team, business: @business).reload
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      add_member_1 = create :emu, business: @business
      add_member_2 = create :emu, business: @business
      team.add_member(add_member_1, force_emu: true)
      team.add_member(add_member_2, force_emu: true)
      refute_same_elements external_group.member_user_ids, team.reload.member_ids

      external_group_team.reconcile_memberships
      assert_same_elements external_group.reload.member_user_ids, team.reload.member_ids
    end

    test "sets out_of_seats to false when reconciling with no add members" do
      external_group = nil
      perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        external_group = create(:external_group, :with_members, :with_team, business: @business).reload
      end
      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      add_member_1 = create :emu, business: @business
      add_member_2 = create :emu, business: @business
      team.add_member(add_member_1, force_emu: true)
      team.add_member(add_member_2, force_emu: true)

      ExternalGroupTeamSyncStatusUpdateJob.expects(:enqueue_once_per_interval)
        .with(
          args: [external_group_team.id, false],
          unique_id: external_group_team.id,
          interval: ExternalGroupTeam::SYNC_STATUS_JOB_DELAY,
        )
      external_group_team.reconcile_memberships
    end

    test "reconciles when team has different users than the external group" do
      external_group = nil
      perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        external_group = create(:external_group, :with_members, :with_team, business: @business).reload
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      remove_member = team.members.first
      team.remove_member(remove_member, force: true)
      add_member_1 = create :emu, business: @business
      add_member_2 = create :emu, business: @business
      team.add_member(add_member_1, force_emu: true)
      team.add_member(add_member_2, force_emu: true)

      refute_same_elements external_group.member_user_ids, team.reload.member_ids

      external_group_team.reconcile_memberships
      assert_same_elements external_group.reload.member_user_ids, team.reload.member_ids
    end

    test "avoids suspended users from being added to teams during reconcile" do
      external_group = nil
      perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        external_group = create(:external_group, :with_members, :with_team, business: @business).reload
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      remove_member = team.members.first
      team.remove_member(remove_member, force: true)
      remove_member.external_identities.first.disable
      refute_same_elements external_group.member_user_ids, team.reload.member_ids

      external_group_team.reconcile_memberships
      refute_same_elements external_group.reload.member_user_ids, team.reload.member_ids
    end

    test "ensure logging when reconciling for EMU" do
      GitHub.flipper[:do_not_check_license_for_org_members].disable

      external_group_team = nil
      perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)
      end

      user1 = create(:emu, business: @business)
      user2 = create(:emu, business: @business)
      ExternalIdentityGroupMembership.create(external_group: @external_group_with_members, external_identity: user1.external_identities.first)
      ExternalIdentityGroupMembership.create(external_group: @external_group_with_members, external_identity: user2.external_identities.first)
      perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob
      @business = Business.find(@business.id)
      @business.update(seats: @business.consumed_enterprise_licenses + 1)
      log1 = {
        "code.namespace" => "ExternalGroupTeam",
        "code.function" => "reconcile_memberships",
        "info.message" => "adding user to team succeeded",
        "gh.add_member_status" => "success",
        "gh.external_group_team.id" => external_group_team.id,
        "gh.external_group.name" => @external_group_with_members.display_name,
        "gh.external_group.id" => @external_group_with_members.id,
        "gh.team.name" => @team.name,
        "gh.team.id" => @team.id,
        "gh.user.id" => user1.id,
      }
      log2 = {
        "code.namespace" => "ExternalGroupTeam",
        "code.function" => "reconcile_memberships",
        "exception.message" => "failed to add user to team",
        "gh.add_member_status" => "no_seat",
        "gh.external_group_team.id" => external_group_team.id,
        "gh.external_group.name" => @external_group_with_members.display_name,
        "gh.external_group.id" => @external_group_with_members.id,
        "gh.team.name" => @team.name,
        "gh.team.id" => @team.id,
        "gh.user.id" =>  user2.id,
      }
      log3 = {
        "gh.business.slug": @business.slug,
        "gh.license_usage.completed": false
      }

      refute_equal @external_group_with_members.members.size, @team.members.size
      assert_logged(**log1, **log2, **log3) do
        perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob do
          external_group_team.reconcile_memberships
        end
      end
    end unless GitHub.single_business_environment?

    test "triggers ExternalGroupTeamSyncStatusUpdateJob upon completion" do
      external_group = perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        create(:external_group, :with_members, :with_team, business: @business)
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      remove_member = team.members.first
      team.remove_member(remove_member, force: true)

      refute_same_elements external_group.member_user_ids, team.reload.member_ids

      ExternalGroupTeamSyncStatusUpdateJob.expects(:enqueue_once_per_interval)
        .with(
          args: [external_group_team.id, false],
          unique_id: external_group_team.id,
          interval: ExternalGroupTeam::SYNC_STATUS_JOB_DELAY,
        )

      external_group_team.reconcile_memberships
    end

    test "enqueues the ExternalGroupTeamSyncStatusUpdateJob in the rescue block" do
      external_group = perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        create(:external_group, :with_members, :with_team, business: @business)
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      remove_member = team.members.first
      team.remove_member(remove_member, force: true)

      refute_same_elements external_group.member_user_ids, team.reload.member_ids

      Team.any_instance.stubs(:bulk_add_members_with_failover).raises(ActiveRecord::RecordNotFound)

      ExternalGroupTeamSyncStatusUpdateJob.expects(:enqueue_once_per_interval)
        .with(
          args: [external_group_team.id, false],
          unique_id: external_group_team.id,
          interval: ExternalGroupTeam::SYNC_STATUS_JOB_DELAY,
        )

      assert_raises ActiveRecord::RecordNotFound do
        external_group_team.reconcile_memberships
      end
    end

    test "tells the ExternalGroupTeamSyncStatusUpdateJob when a business is out of licenses" do
      GitHub.flipper[:do_not_check_license_for_org_members].disable

      external_group = perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        create(:external_group, :with_members, :with_team, business: @business)
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      remove_member = team.members.first
      team.remove_member(remove_member, force: true)

      refute_same_elements external_group.member_user_ids, team.reload.member_ids

      Team.any_instance.stubs(:bulk_add_members_with_failover).returns([Team::AddMemberStatus::NO_SEAT])

      ExternalGroupTeamSyncStatusUpdateJob.expects(:enqueue_once_per_interval)
        .with(
          args: [external_group_team.id, true],
          unique_id: external_group_team.id,
          interval: ExternalGroupTeam::SYNC_STATUS_JOB_DELAY,
        )

      external_group_team.reconcile_memberships
    end
  end
end

module ExternalGroupTeamUpdateSyncStatusSharedTests
  extend ActiveSupport::Concern

  included do
    test "updates the group team sync_status field with an in_sync status when the group and team are in sync" do
      external_group = perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        create(:external_group, :with_members, :with_team, business: @business)
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      assert_same_elements external_group.member_user_ids, team.reload.member_ids

      assert external_group_team.reload.in_sync?

      external_group_team.update_sync_status(out_of_seats: false)
      assert external_group_team.reload.in_sync?
      assert_same_elements external_group.reload.member_user_ids, team.reload.member_ids
    end

    test "updates the group team sync_status field with an out_of_sync_insufficient_licenses status when there are membership mismatches and the business is out of seats" do
      external_group = perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        create(:external_group, :with_members, :with_team, business: @business)
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      remove_member = team.members.first
      team.remove_member(remove_member, force: true)
      add_member_1 = create :emu, business: @business
      add_member_2 = create :emu, business: @business
      team.add_member(add_member_1, force_emu: true)
      team.add_member(add_member_2, force_emu: true)

      refute_same_elements external_group.member_user_ids, team.reload.member_ids

      assert external_group_team.reload.in_sync?

      external_group_team.update_sync_status(out_of_seats: true)
      assert external_group_team.reload.out_of_sync_insufficient_licenses?
      refute_same_elements external_group.reload.member_user_ids, team.reload.member_ids
    end

    test "updates the group team sync_status field with an out_of_sync_generic status when the group has fewer members than the team" do
      external_group = perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        create(:external_group, :with_members, :with_team, business: @business)
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      remove_member = team.members.first
      team.remove_member(remove_member, force: true)
      add_member_1 = create :emu, business: @business
      add_member_2 = create :emu, business: @business
      team.add_member(add_member_1, force_emu: true)
      team.add_member(add_member_2, force_emu: true)

      refute_same_elements external_group.member_user_ids, team.reload.member_ids

      assert external_group_team.reload.in_sync?

      external_group_team.update_sync_status(out_of_seats: false)

      assert external_group_team.reload.out_of_sync_generic?
      refute_same_elements external_group.reload.member_user_ids, team.reload.member_ids
    end

    test "query counts stay the same or go down" do
      external_group = perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        create(:external_group, :with_members, :with_team, business: @business)
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team

      remove_member = team.members.first
      team.remove_member(remove_member, force: true)
      add_member_1 = create :emu, business: @business
      add_member_2 = create :emu, business: @business
      team.add_member(add_member_1, force_emu: true)
      team.add_member(add_member_2, force_emu: true)

      refute_same_elements external_group.member_user_ids, team.reload.member_ids

      assert_query_count(3, ignore_feature_flags: true) do
        external_group_team.update_sync_status(out_of_seats: false)
      end
    end
  end
end

module ExternalGroupTeamMembershipChangesSharedTests
  def test_returns_empty_arrays_when_no_changes
    external_group = nil
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      external_group = create(:external_group, :with_members, :with_team, business: @business).reload
    end

    to_add, to_remove = external_group.external_group_teams.first.calculate_membership_changes
    assert_empty to_add
    assert_empty to_remove
  end

  def test_returns_to_add_with_user_ids_and_to_remove_empty_when_team_has_less_users_than_the_external_group
    external_group = nil
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      external_group = create(:external_group, :with_members, :with_team, business: @business).reload
    end

    external_group_team = external_group.external_group_teams.first
    team = external_group_team.team

    remove_member = team.members.first
    team.remove_member(remove_member, force: true)

    to_add, to_remove = external_group_team.calculate_membership_changes
    assert_same_elements [remove_member.id], to_add
    assert_empty to_remove
  end

  def test_returns_to_remove_with_user_ids_and_to_add_empty_when_team_has_more_users_than_the_external_group
    external_group = nil
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      external_group = create(:external_group, :with_members, :with_team, business: @business).reload
    end

    external_group_team = external_group.external_group_teams.first
    team = external_group_team.team

    add_member_1 = create :emu, business: @business
    add_member_2 = create :emu, business: @business
    team.add_member(add_member_1, force_emu: true)
    team.add_member(add_member_2, force_emu: true)

    to_add, to_remove = external_group_team.calculate_membership_changes
    assert_same_elements [add_member_1.id, add_member_2.id], to_remove
    assert_empty to_add
  end

  def test_returns_to_remove_with_user_ids_and_to_add_with_user_ids_when_team_has_different_users_than_the_external_group
    external_group = nil
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      external_group = create(:external_group, :with_members, :with_team, business: @business).reload
    end

    external_group_team = external_group.external_group_teams.first
    team = external_group_team.team

    remove_member = team.members.first
    team.remove_member(remove_member, force: true)
    add_member_1 = create :emu, business: @business
    add_member_2 = create :emu, business: @business
    team.add_member(add_member_1, force_emu: true)
    team.add_member(add_member_2, force_emu: true)

    to_add, to_remove = external_group_team.calculate_membership_changes
    assert_same_elements [add_member_1.id, add_member_2.id], to_remove
    assert_same_elements [remove_member.id], to_add
  end

  def test_returns_to_remove_with_user_id_when_team_has_different_users_than_the_external_group_with_user_as_argument
    external_group = nil
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      external_group = create(:external_group, :with_members, :with_team, business: @business).reload
    end

    external_group_team = external_group.external_group_teams.first
    team = external_group_team.team

    remove_member = team.members.first
    ExternalIdentityGroupMembership.find_by(external_identity_id: remove_member.external_identities.first.id).destroy

    to_add, to_remove = external_group_team.calculate_membership_changes(user: remove_member)
    assert_same_elements [remove_member.id], to_remove
    assert_empty to_add
  end

  def test_returns_to_add_with_user_id_when_team_has_less_users_than_the_external_group_with_user_as_argument
    external_group = nil
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      external_group = create(:external_group, :with_members, :with_team, business: @business).reload
    end

    external_group_team = external_group.external_group_teams.first
    team = external_group_team.team

    add_member = create :emu, business: @business
    ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: add_member.external_identities.first)

    to_add, to_remove = external_group_team.calculate_membership_changes(user: add_member)
    assert_same_elements [add_member.id], to_add
    assert_empty to_remove
  end

  def test_reconcile_team_memberships_returns_two_users_with_different_actions
    external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

    delete_user = @external_group_with_members.external_identity_group_memberships.first.external_identity.user
    @external_group_with_members.external_identity_group_memberships.first.destroy

    disable_user = @external_group_with_members.external_identity_group_memberships.last.external_identity.user
    @external_group_with_members.external_identity_group_memberships.last.external_identity.disable
    @external_group_with_members.external_identity_group_memberships.last.external_identity.save

    refute_nil @external_group_with_members.external_identity_group_memberships.last.external_identity.reload.disabled_at

    emu = create :emu, business: @business
    ExternalIdentityGroupMembership.create(external_group: @external_group_with_members, external_identity: emu.external_identities.first)

    assert_includes @team.members, delete_user
    assert_includes @team.members, disable_user
    refute_includes @team.members, emu

    reconciled_members = external_group_team.reconcile_team_memberships

    assert_equal :delete, reconciled_members[delete_user.id]
    assert_equal :delete, reconciled_members[disable_user.id]
    assert_equal :add, reconciled_members[emu.id]
  end
end

module ExternalGroupTeamMembershipMismatchSharedTests
  extend ActiveSupport::Concern

  included do
    context "#calculate_group_team_mismatches" do
      test "returns a hash with empty mismatch arrays when group is synced with team" do
        perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob]) do
          external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)

          mismatches = external_group_team.calculate_group_team_mismatches

          assert_empty mismatches[:group_member_ids_not_in_team]
          assert_empty mismatches[:team_member_ids_not_in_group]
        end
      end

      test "always filters out users removed from IdP application, but still belonging to group" do
        perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob]) do
          external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)

          first_group_member_identity = @external_group_with_members.external_identity_group_memberships.first.external_identity
          first_group_member_identity.disable

          # the group member is now disabled, but they still belong to the group
          refute_nil first_group_member_identity.disabled_at
          assert @external_group_with_members.member?(first_group_member_identity.id)

          # ensure the user is removed from their team
          ExternalGroupTeamReconcileJob.perform_now(external_group_id: @external_group_with_members.id, team_id: @team.id, caller: self.class.name)

          refute @team.member? first_group_member_identity.user

          mismatches = external_group_team.calculate_group_team_mismatches

          assert_empty mismatches[:group_member_ids_not_in_team]
          assert_empty mismatches[:team_member_ids_not_in_group]
        end
      end

      test "still works when the team doesn't exist" do
        perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob]) do
          external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)

          assert_same_elements @team.member_ids, external_group_team.team.member_ids

          @team.destroy

          assert_nil external_group_team.reload.team&.member_ids

          mismatches = external_group_team.calculate_group_team_mismatches

          assert_empty mismatches[:team_member_ids_not_in_group]
          assert_same_elements mismatches[:group_member_ids_not_in_team], @external_group_with_members.active_user_ids
        end
      end

      test "still works when the group doesn't exist" do
        perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob]) do
          external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)

          assert_same_elements @external_group_with_members.active_user_ids, external_group_team.external_group.active_user_ids

          @external_group_with_members.delete

          assert_nil external_group_team.reload.external_group&.active_user_ids

          mismatches = external_group_team.calculate_group_team_mismatches

          assert_same_elements mismatches[:team_member_ids_not_in_group], external_group_team.reload.team&.member_ids
          assert_empty mismatches[:group_member_ids_not_in_team]
        end
      end

      test "returns a hash with group members not in team" do
        perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob]) do
          external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)

          first_team_member = @team.members.first
          @team.remove_member(first_team_member, force: true)

          assert @external_group_with_members.member?(first_team_member.external_identities.first.id)

          mismatches = external_group_team.calculate_group_team_mismatches

          assert_same_elements mismatches[:group_member_ids_not_in_team], [first_team_member.id]
          assert_empty mismatches[:team_member_ids_not_in_group]
        end
      end

      test "returns a hash with team members not in group" do
        perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob]) do
          external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)

          first_group_member = @external_group_with_members.members.first
          first_group_member.destroy

          refute @external_group_with_members.member? first_group_member.external_identity.id
          assert @team.member? User.find(first_group_member.external_identity.user_id)

          mismatches = external_group_team.calculate_group_team_mismatches

          assert_empty mismatches[:group_member_ids_not_in_team]
          assert_same_elements mismatches[:team_member_ids_not_in_group], [first_group_member.external_identity.user.id]
        end
      end

      test "returns a hash with both mismatched group members and mismatched team members" do
        external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)
        @team.add_member(@user, { force_emu: true })

        refute @external_group_with_members.member? @user.external_identities.first.id
        assert @team.member? @user

        mismatches = external_group_team.calculate_group_team_mismatches

        assert_same_elements mismatches[:group_member_ids_not_in_team], @external_group_with_members.member_user_ids
        assert_same_elements mismatches[:team_member_ids_not_in_group], @team.member_ids
      end
    end

    context "#calculate_memberships_in_sync?" do
      test "returns false if memberships are not in sync" do
        perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob]) do
          external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)
          @team.add_member(@user, { force_emu: true })

          refute @external_group_with_members.member? @user.external_identities.first.id
          assert @team.member? @user

          refute external_group_team.calculate_memberships_in_sync?
        end
      end

      test "returns true if memberships are in sync" do
        perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob]) do
          external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team)

          assert external_group_team.calculate_memberships_in_sync?
        end
      end
    end
  end
end

class ExternalGroupSamlTeamTest < GitHub::TestCase
  include ExternalGroupTeamValidationsSharedTests
  include ExternalGroupTeamProvisioningSharedTests
  include ExternalGroupTeamDeprovisioningSharedTests
  include ExternalGroupTeamLinkUnlinkSharedTests
  include ExternalGroupTeamReconcileMembershipsSharedTests
  include ExternalGroupTeamUpdateSyncStatusSharedTests
  include ExternalGroupTeamMembershipChangesSharedTests
  include ExternalGroupTeamMembershipMismatchSharedTests
  include GitHub::LoggerHelper

  fixtures do
    @external_group = create :external_group

    @provider = @external_group.provider
    @business = @provider.business

    @external_group_with_members = create(:external_group, :with_members, business: @business, number_of_members: 2)
    @external_group_users = @external_group_with_members.external_identity_group_memberships.map(&:external_identity).map(&:user)

    @admin = create :emu, :owner, business: @business
    @user = create :emu, :owner, business: @business
    @another_user = create :emu, business: @business
    @just_another_user = create :user

    @org = create(:organization, seats: 10, business: @business, admin: @admin)
    @team = create(:team, organization: @org)
  end

  setup do
    GitHub.flipper[:disable_external_group_team_reconcile_job].disable
  end
end unless GitHub.single_business_environment?

class ExternalGroupOIDCTeamTest < GitHub::TestCase
  include ExternalGroupTeamValidationsSharedTests
  include ExternalGroupTeamProvisioningSharedTests
  include ExternalGroupTeamDeprovisioningSharedTests
  include ExternalGroupTeamLinkUnlinkSharedTests
  include ExternalGroupTeamReconcileMembershipsSharedTests
  include ExternalGroupTeamUpdateSyncStatusSharedTests
  include ExternalGroupTeamMembershipChangesSharedTests
  include ExternalGroupTeamMembershipMismatchSharedTests
  include GitHub::LoggerHelper

  fixtures do
    @external_group = create :external_group, provider_type: :oidc

    @provider = @external_group.provider
    @business = @provider.business

    @external_group_with_members = create(:external_group, :with_members, business: @business, number_of_members: 2)
    @external_group_users = @external_group_with_members.external_identity_group_memberships.map(&:external_identity).map(&:user)

    @admin = create :emu, :owner, business: @business
    @user = create :emu, :owner, business: @business
    @another_user = create :emu, business: @business
    @just_another_user = create :user

    @org = create(:organization, seats: 10, business: @business, admin: @admin)
    @team = create(:team, organization: @org)
  end

  setup do
    GitHub.flipper[:disable_external_group_team_reconcile_job].disable
  end
end unless GitHub.single_business_environment?
