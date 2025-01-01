# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotSeatAssignmentTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "#for_organization" do
    test "returns all seat assignments for an organization" do
      seat_assignment = create(:copilot_seat_assignment, :organization)
      assert_equal [seat_assignment], Copilot::SeatAssignment.for_organization(seat_assignment.organization)
    end

    test "returns nothing in the organization is nil" do
      create(:copilot_seat_assignment, :organization)
      assert_equal [], Copilot::SeatAssignment.for_organization(nil)
    end
  end

  context "#for_organization_id" do
    test "returns all seat assignments for an organization" do
      seat_assignment = create(:copilot_seat_assignment, :organization)
      assert_equal [seat_assignment], Copilot::SeatAssignment.for_organization_id(seat_assignment.organization.id)
    end

    test "gets for multiple organizations" do
      org1 = create(:organization)
      org2 = create(:organization)
      create(:copilot_seat_assignment, :organization, organization: org1)
      create(:copilot_seat_assignment, :organization, organization: org2)
      assert_equal 2, Copilot::SeatAssignment.for_organization_id([org1.id, org2.id]).count
    end
  end

  context "#force_destroy!" do
    test "copilot enterprise team seat assignment" do
      events = subscribe "copilot_seat_assignment.destroy"
      assignment = create(:copilot_seat_assignment, :enterprise_team, member_count: 5)
      assignment.convert_to_seats
      assert_equal 5, assignment.seats.count

      payload = {
        organization: nil,
        assignable_type: assignment.assignable_type,
        assignable_id: assignment.assignable_id,
        pending_cancellation_date: nil,
        owner: assignment.owner.slug,
        owner_id: assignment.owner_id,
        assigning_user: assignment.assigning_user.login,
        assigning_user_id: assignment.assigning_user_id,
      }

      assignment.seats.each do |seat|
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_cancelled).once.with(seat, nil, false, :cancel_immediately).once
      end

      assert_changes("Copilot::SeatAssignment.count", from: 1, to: 0) do
        assert_changes("Copilot::Seat.count", from: 5, to: 0) do
          assignment.force_destroy!
        end
      end
      assert_equal events.first.payload, payload
    end
  end

  context "validation" do
    test "factory" do
      seat_assignment = build(:copilot_seat_assignment)
      refute seat_assignment.valid?
      assert_equal [], seat_assignment.errors[:organization] # it creates an organization
      assert_equal [], seat_assignment.errors[:assigning_user] # it creates an organization
      refute_nil seat_assignment.errors[:assignable]

      # TRAITS
      seat_assignment = build(:copilot_seat_assignment, :team)
      assert seat_assignment.valid?

      seat_assignment = build(:copilot_seat_assignment, :user)
      assert seat_assignment.valid?

      seat_assignment = build(:copilot_seat_assignment, :organization_invitation)
      assert seat_assignment.valid?

      seat_assignment = build(:copilot_seat_assignment, :organization)
      assert seat_assignment.valid?
      seat_assignment.save!
    end

    test "enterprise_team" do
      assignment = build(:copilot_seat_assignment, :enterprise_team)
      assert assignment.valid?
      assert assignment.assignable.is_a?(::EnterpriseTeam)
      assert assignment.owner.is_a?(::Business)
      refute assignment.organization.present?

      assignment.save!
      assert_equal assignment.assignable.business, assignment.owner
      assert_equal assignment.assigning_user, assignment.assignable.business.admins.first
    end

    test "requires an organization" do
      organization = create(:organization)

      seat_assignment = Copilot::SeatAssignment.new
      refute seat_assignment.valid?
      refute_nil seat_assignment.errors[:organization]

      seat_assignment.organization = organization
      refute seat_assignment.valid?
      assert_equal [], seat_assignment.errors[:organization]
    end

    test "populates the owner column stuff" do
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)

      seat_assignment = build(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admin)
      assert seat_assignment.valid?

      seat_assignment.save!
      seat_assignment.reload
      assert_equal "Organization", seat_assignment.owner_type
      assert_equal seat_assignment.owner, organization
    end

    test "requires specific assignable types" do
      user = create(:user)
      organization = create(:organization)
      organization.add_member(user)

      seat_assignment = Copilot::SeatAssignment.new
      seat_assignment.organization = organization
      seat_assignment.assigning_user = user

      # user
      assignable_user = create(:user)
      organization.add_member(assignable_user)
      seat_assignment.assignable = assignable_user
      assert seat_assignment.valid?

      # team
      seat_assignment.assignable = create(:team, organization: organization)
      assert seat_assignment.valid?

      # organizationinvitations
      seat_assignment.assignable = create(:organization_invitation, organization: organization, inviter: user, invitee: create(:user))
      assert seat_assignment.valid?

      # invalid
      seat_assignment.assignable = create(:repository)
      refute seat_assignment.valid?
      assert_equal ["is not included in the list"], seat_assignment.errors[:assignable_type]
    end

    test "assignable user must belong to org" do
      user = create(:user)
      organization = create(:organization)
      organization.add_member(user)

      assigning_user = create(:user)
      organization.add_member(assigning_user)

      seat_assignment = Copilot::SeatAssignment.new
      seat_assignment.organization = organization
      seat_assignment.assigning_user = assigning_user
      seat_assignment.assignable = create(:user) # random user

      refute seat_assignment.valid?
      refute_nil seat_assignment.errors[:assignable]

      seat_assignment.assignable = user
      assert seat_assignment.valid?
    end

    test "assignable team must belong to org" do
      organization = create(:organization)
      team = create(:team, organization: organization)

      assigning_user = create(:user)
      organization.add_member(assigning_user)

      seat_assignment = Copilot::SeatAssignment.new
      seat_assignment.organization = organization
      seat_assignment.assigning_user = assigning_user
      seat_assignment.assignable = create(:team) # random team

      refute seat_assignment.valid?
      refute_nil seat_assignment.errors[:assignable]

      seat_assignment.assignable = team
      assert seat_assignment.valid?
    end

    test "assignable organization invitation must belong to org" do
      organization = create(:organization)
      organization_invitation = create(:organization_invitation, organization: organization)

      assigning_user = create(:user)
      organization.add_member(assigning_user)

      seat_assignment = Copilot::SeatAssignment.new
      seat_assignment.organization = organization
      seat_assignment.assigning_user = assigning_user
      seat_assignment.assignable = create(:organization_invitation) # random invitation

      refute seat_assignment.valid?
      refute_nil seat_assignment.errors[:assignable]

      seat_assignment.assignable = organization_invitation
      assert seat_assignment.valid?
    end

    test "assigning user must belong to org" do
      user = create(:user)
      organization = create(:organization)
      organization.add_member(user)

      assignable_user = create(:user)
      organization.add_member(assignable_user)

      seat_assignment = Copilot::SeatAssignment.new
      seat_assignment.organization = organization
      seat_assignment.assigning_user = create(:user) # random user
      seat_assignment.assignable = assignable_user

      refute seat_assignment.valid?
      refute_nil seat_assignment.errors[:assigning_user]

      seat_assignment.assigning_user = user
      assert seat_assignment.valid?
    end

    test "assigning bot must have correct permissions" do
      user = create(:user)
      organization = create(:organization)
      organization.add_member(user)

      seat_assignment = Copilot::SeatAssignment.new
      seat_assignment.organization = organization

      app_with_permissions = make_integration_installation(target: organization, permissions: { "organization_copilot_seat_management" => :write })
      seat_assignment.assigning_user = app_with_permissions.bot
      seat_assignment.assignable = user

      assert seat_assignment.valid?

      app_without_permissions = make_integration_installation(target: organization, permissions: { "administration" => :write })
      seat_assignment.assigning_user = app_without_permissions.bot

      refute seat_assignment.valid?
    end

    test "assignable is unique by organization" do
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)

      create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admin)
      seat_assignment = build(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admin)
      refute seat_assignment.valid?
      refute_nil seat_assignment.errors[:assignable_id]

      other_user = create(:user)
      organization.add_member(other_user)
      seat_assignment.assignable = other_user
      assert seat_assignment.valid?
      seat_assignment.save!
      assert seat_assignment.owner == organization
    end

    test "suspended users cannot be assigned a seat assignment" do
      org = create(:organization)
      admin = org.admins.first
      naughty_person = create(:user, suspended_at: Time.now)
      org.add_member(naughty_person)

      seat_assignment = build(:copilot_seat_assignment, organization: org, assignable: naughty_person, assigning_user: admin)

      refute seat_assignment.valid?
      assert_equal seat_assignment.errors.count, 1
      assert seat_assignment.errors[:assignable].include?("Seat assignment cannot be created for a suspended user")
    end

    test "suspended organizations cannot be assigned a seat assignment, or assign an org level assignment" do
      org = create(:organization, suspended_at: Time.now)
      admin = org.admins.first
      regular_person = create(:user)
      org.add_member(regular_person)

      seat_assignment = build(:copilot_seat_assignment, organization: org, assignable: org, assigning_user: admin)

      refute seat_assignment.valid?
      assert_equal seat_assignment.errors.count, 2
      assert seat_assignment.errors[:assignable].include?("Seat assignment cannot be created for a suspended organization")
      assert seat_assignment.errors[:owner].include?("Seat assignment cannot be created by a suspended organization")
    end

    test "a suspended org cannot assign team seat assignments" do
      org = create(:organization, suspended_at: Time.now)
      admin = org.admins.first
      regular_person = create(:user)
      team = create(:team, organization: org)
      org.add_member(regular_person)
      team.add_member(regular_person)

      seat_assignment = build(:copilot_seat_assignment, owner: org, assignable: team, assigning_user: admin)
      refute seat_assignment.valid?
      assert_equal seat_assignment.errors.count, 1
      assert seat_assignment.errors[:owner].include?("Seat assignment cannot be created by a suspended organization")
    end

    test "a suspended org cannot assign user seat assignments" do
      org = create(:organization, suspended_at: Time.now)
      admin = org.admins.first
      regular_person = create(:user)
      org.add_member(regular_person)

      seat_assignment = build(:copilot_seat_assignment, owner: org, assignable: regular_person, assigning_user: admin)
      refute seat_assignment.valid?
      assert_equal seat_assignment.errors.count, 1
      assert seat_assignment.errors[:owner].include?("Seat assignment cannot be created by a suspended organization")
    end

    test "a suspended basic enterprise cannot assign seat assignments" do
      biz = create(:business, :default_managed, seats_plan_type: :basic, suspended_at: Time.now)
      admin = biz.admins.first
      enterprise_team = create(:enterprise_team, business: biz)
      user = create(:user)
      biz.add_user_accounts([user.id], business_roles_bitfield: 0)
      enterprise_team.enterprise_team_memberships.create!(user_id: user.id)

      assignment = build(:copilot_seat_assignment, owner: biz, assignable: enterprise_team, assigning_user: admin)

      refute assignment.valid?
      assert_equal assignment.errors.count, 1
      assert assignment.errors[:owner].include?("Seat assignment cannot be created by a suspended business")
    end unless TestEnv.test_with_all_emus?

    test "a suspended basic emu enterprise cannot assign seat assignments" do
      # This factory implicitly creates an enterprise team with emus
      enterprise_team = create(:copilot_enterprise_team)
      business = enterprise_team.business
      business.update(suspended_at: Time.now)
      assignment = build(
        :copilot_seat_assignment,
        owner: business,
        assignable: enterprise_team,
        assigning_user: business.admins.first
      )

      refute assignment.valid?
      assert_equal assignment.errors.count, 1
      assert assignment.errors[:owner].include?("Seat assignment cannot be created by a suspended business")
    end if TestEnv.test_with_all_emus?
  end

  context "includes_user" do

    test "don't allow emu orgs to do invitations" do
      emu_owner = FactoryBot.create(:emu, :owner)
      external_identity = emu_owner.external_identities.first
      business = emu_owner.enterprise_managed_business
      business.update(seats_plan_type: :basic)
      organization = create(:enterprise_linked_organization, business: business)

      seat_assignment = build(:copilot_seat_assignment,
        organization: organization,
        assignable: create(:organization_invitation,
          organization: organization,
          inviter: external_identity.user,
          invitee: create(:user)
        ),
        assigning_user: emu_owner,
      )
      refute seat_assignment.valid?
      assert_equal ["cannot be an invitation"], seat_assignment.errors[:assignable_type]
    end

    context "user assignment" do
      test "it does include the user" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization)
        assert seat_assignment.includes_user?(user)
      end

      test "it doesn't include the user" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)

        user2 = create(:user)
        organization.add_member(user2)
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user2, organization: organization)
        refute seat_assignment.includes_user?(user)
      end
    end

    context "team assignment" do
      test "it does include the user if they are on the team" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)
        team = create(:team, organization: organization)
        team.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: organization)
        assert seat_assignment.includes_user?(user)
      end

      test "it doesn't include the user if they aren't on the team" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)
        team = create(:team, organization: organization)

        seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: organization)
        refute seat_assignment.includes_user?(user)
      end
    end

    context "organizationinvitation assignment" do
      test "it does include the user if they are on the team" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)
        team = create(:team, organization: organization)
        team.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: organization)
        assert seat_assignment.includes_user?(user)
      end

      test "it doesn't include the user if they aren't on the team" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)
        team = create(:team, organization: organization)

        seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: organization)
        refute seat_assignment.includes_user?(user)
      end
    end
  end

  context "for_enterprise_team" do
    test "returns nothing if no seat assignment exists" do
      enterprise_team = create(:copilot_enterprise_team)
      assert_empty Copilot::SeatAssignment.for_enterprise_team(enterprise_team)
    end

    test "returns the seat assignment if it exists" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      assert_equal assignment, Copilot::SeatAssignment.for_enterprise_team(assignment.assignable).first
    end
  end

  context "unassign!" do
    test "it unassigns the user" do
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)
      seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization, created_at: 10.days.ago, updated_at: 10.days.ago)
      updated_at = seat_assignment.updated_at
      assert seat_assignment.includes_user?(user)
      assert_nil seat_assignment.pending_cancellation_date

      freeze_time do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once
        seat_assignment.unassign!(organization.admins.first)
        seat_assignment.reload
        refute_equal updated_at, seat_assignment.updated_at
        assert_equal Time.now.utc, seat_assignment.updated_at
        assert_in_delta organization.next_metered_billing_cycle_starts_at.to_date, seat_assignment.pending_cancellation_date, 1.day
      end
    end

    test "it does not update the pending cancellation date if it's already set" do
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)
      seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization)

      freeze_time do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once
        seat_assignment.unassign!(organization.admins.first)
        seat_assignment.reload
      end

      pending_cancellation_date = seat_assignment.pending_cancellation_date

      travel 32.days do
        assert seat_assignment.pending_cancellation?
        seat_assignment.unassign!(organization.admins.first)
        seat_assignment.reload
        assert_equal pending_cancellation_date, seat_assignment.pending_cancellation_date
      end
    end
  end

  context "convert_to_seats" do
    context "users" do
      test "calls the command" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization)
        assert seat_assignment.includes_user?(user)

        Copilot::SeatAssignments::UserConverterCommand.expects(:call).with(seat_assignment)
        seat_assignment.convert_to_seats
      end

      test "creates the seat" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization)
        assert seat_assignment.includes_user?(user)

        assert_changes("Copilot::Seat.count", 1) do
          result = seat_assignment.convert_to_seats
          assert result.ok?
        end
      end

      test "idempotent" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization)
        assert seat_assignment.includes_user?(user)

        assert_changes("Copilot::Seat.count", 1) do
          result = seat_assignment.convert_to_seats
          assert result.ok?
        end

        assert_no_changes -> { Copilot::Seat.count } do
          result = seat_assignment.convert_to_seats
          assert result.ok?
        end
      end

      test "returns the existing seat" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization)
        assert seat_assignment.includes_user?(user)
        create(:copilot_seat, organization: organization, assigned_user: user, seat_assignment: seat_assignment)

        assert_no_changes("Copilot::Seat.count") do
          result = seat_assignment.convert_to_seats
          assert result.ok?
        end
      end

      test "returns the existing seats" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization)
        assert seat_assignment.includes_user?(user)

        create(:copilot_seat, organization: organization, assigned_user: user, seat_assignment: seat_assignment)

        assert_no_changes("Copilot::Seat.count") do
          result = seat_assignment.convert_to_seats
          assert result.ok?
        end
      end
    end
  end

  context "auth and capture post-commit hook" do
    test "does nothing if the flag copilot_auth_on_seat_assignment_creation is disabled" do
      GitHub.flipper[:copilot_auth_on_seat_assignment_creation].disable

      org = create(:organization)
      assert_enqueued_jobs(0, only: Copilot::Billing::OrganizationAuthAndCaptureJob) do
        create(:copilot_seat_assignment, :organization, organization: org)
      end
    end

    test "enqueues A&C only once if the copilot_auth_on_seat_assignment_creation flag is enabled" do
      GitHub.flipper[:copilot_auth_on_seat_assignment_creation].enable

      org = create(:organization)
      # rubocop:disable Style/HashSyntax
      assert_enqueued_with(job: Copilot::Billing::OrganizationAuthAndCaptureJob, args: [org.id, { :skip_account_age_check => true, :audit_log_reason => "seat_assignment_creation" }]) do
        create(:copilot_seat_assignment, :organization, organization: org)
      end

      assert_enqueued_jobs(0, only: Copilot::Billing::OrganizationAuthAndCaptureJob) do
        create(:copilot_seat_assignment, :organization, organization: org)
      end
    end

    test "enqueues A&C three times if the flag copilot_delayed_auth_on_seat_assignment_creation is enabled" do
      GitHub.flipper[:copilot_auth_on_seat_assignment_creation].enable
      GitHub.flipper[:copilot_delayed_auth_on_seat_assignment_creation].enable

      org = create(:organization)

      create(:copilot_seat_assignment, :organization, organization: org)
      # rubocop:disable Style/HashSyntax
      assert_enqueued_with(job: Copilot::Billing::OrganizationAuthAndCaptureJob, args: [org.id, { :skip_account_age_check => true, :audit_log_reason => "seat_assignment_creation" }])
      assert_enqueued_with(job: Copilot::Billing::OrganizationAuthAndCaptureJob, args: [org.id, { :skip_previous_authorizations_check => true, :skip_account_age_check => true, :audit_log_reason => "seat_assignment_creation_delayed_check_1" }])
      assert_enqueued_with(job: Copilot::Billing::OrganizationAuthAndCaptureJob, args: [org.id, { :skip_previous_authorizations_check => true, :skip_account_age_check => true, :audit_log_reason => "seat_assignment_creation_delayed_check_2" }])

      # Adding another seat doesn't trigger more auth checks
      assert_enqueued_jobs(0, only: Copilot::Billing::OrganizationAuthAndCaptureJob) do
        create(:copilot_seat_assignment, :organization, organization: org)
      end
    end

    test "enqueues A&C only once if the flag copilot_delayed_auth_on_seat_assignment_creation is enabled but org is trusted" do
      GitHub.flipper[:copilot_auth_on_seat_assignment_creation].enable
      GitHub.flipper[:copilot_delayed_auth_on_seat_assignment_creation].enable

      org = create(:organization)
      org.settings.set!(:trust_tier, "1")
      # Assert trusted
      assert TrustTiers::Tier.for_billable_owner(org).tier <= TrustTiers::Tier::TRUSTED

      create(:copilot_seat_assignment, :organization, organization: org)
      # rubocop:disable Style/HashSyntax
      assert_enqueued_with(job: Copilot::Billing::OrganizationAuthAndCaptureJob, args: [org.id, { :skip_account_age_check => true, :audit_log_reason => "seat_assignment_creation" }])
      assert_enqueued_jobs(1, only: Copilot::Billing::OrganizationAuthAndCaptureJob)

      # Adding another seat doesn't trigger more auth checks
      assert_enqueued_jobs(0, only: Copilot::Billing::OrganizationAuthAndCaptureJob) do
        create(:copilot_seat_assignment, :organization, organization: org)
      end
    end
  end

  context "requires_conversion/assignable_member_seat_count" do
    test "does nothing for organizationinvitations" do
      assignment = create(:copilot_seat_assignment, :organization_invitation)
      refute assignment.requires_conversion?
    end

    test "requires conversion for user without seat" do
      assignment = create(:copilot_seat_assignment, :user)
      assert_equal 0, assignment.assignable_member_seat_count
      assert_equal 1, assignment.assignable_members_eligible_for_seats_count
      assert assignment.requires_conversion?
    end

    test "does not require conversion for user with a single seat" do
      seat = create(:copilot_seat)
      assert_equal 1, seat.seat_assignment.assignable_member_seat_count
      assert_equal 1, seat.seat_assignment.assignable_members_eligible_for_seats_count
      refute seat.seat_assignment.requires_conversion?
    end

    test "does not require conversion when user is suspended" do
      assignment = create(:copilot_seat_assignment, :user)
      assignment.assignable.update_column(:suspended_at, Time.current)

      assert_equal 0, assignment.assignable_member_seat_count
      assert_equal 0, assignment.assignable_members_eligible_for_seats_count
      assert_equal 1, assignment.assignable_count
      assert_equal [assignment.assignable.id], assignment.assignable_member_ids
      refute assignment.requires_conversion?
    end

    test "does not require conversion when team includes suspended member and other members have seats" do
      org = create(:organization)
      team = create(:team, organization: org)

      user = create(:user)
      org.add_member(user)
      team.add_member(user)

      sus_user = create(:user)
      org.add_member(sus_user)
      team.add_member(sus_user)
      sus_user.update_column(:suspended_at, Time.current)

      create(:copilot_seat, assigned_user: user, organization: org)

      assignment = create(:copilot_seat_assignment, organization: org, assignable: team)

      assert_equal 1, assignment.assignable_member_seat_count
      assert_equal 1, assignment.assignable_members_eligible_for_seats_count
      assert_equal 2, assignment.assignable_member_ids.count
      assert_equal 2, assignment.assignable_count
      assert_equal team.member_ids, assignment.assignable_member_ids

      refute assignment.requires_conversion?
    end

    test "does not require conversion when child team includes suspended member and other members have seats, with child team feature flag enabled" do
      org = create(:organization)
      GitHub.flipper[:copilot_child_teams].enable
      team = create(:public_team, organization: org)
      child_team = create(:public_team, organization: org, parent_team_id: team.id)

      user = create(:user)
      org.add_member(user)
      team.add_member(user)

      sus_user = create(:user)
      org.add_member(sus_user)
      child_team.add_member(sus_user)
      sus_user.update_column(:suspended_at, Time.current)

      create(:copilot_seat, assigned_user: user, organization: org)

      assignment = create(:copilot_seat_assignment, organization: org, assignable: team)

      assert_equal 1, assignment.assignable_member_seat_count
      assert_equal 1, assignment.assignable_members_eligible_for_seats_count
      assert_equal 2, assignment.assignable_member_ids.count
      assert_equal 2, assignment.assignable_count
      assert_equal team.member_ids + child_team.member_ids, assignment.assignable_member_ids

      refute assignment.requires_conversion?
    end

    test "requires conversion when child team member does not have a seat, with child team feature flag enabled" do
      org = create(:organization)
      GitHub.flipper[:copilot_child_teams].enable
      team = create(:public_team, organization: org)
      child_team = create(:public_team, organization: org, parent_team_id: team.id)

      user = create(:user)
      org.add_member(user)
      team.add_member(user)

      child_team_member = create(:user)
      org.add_member(child_team_member)
      child_team.add_member(child_team_member)

      create(:copilot_seat, assigned_user: user, organization: org)

      assignment = create(:copilot_seat_assignment, organization: org, assignable: team)

      assert_equal 1, assignment.assignable_member_seat_count
      assert_equal 2, assignment.assignable_members_eligible_for_seats_count
      assert_equal 2, assignment.assignable_member_ids.count
      assert_equal 2, assignment.assignable_count
      assert_equal [user.id, child_team_member.id], assignment.assignable_member_ids

      assert assignment.requires_conversion?
    end

    test "does not require conversion when child team member does not have a seat, with child team feature flag disabled" do
      org = create(:organization)
      GitHub.flipper[:copilot_child_teams].disable
      team = create(:public_team, organization: org)
      child_team = create(:public_team, organization: org, parent_team_id: team.id)

      user = create(:user)
      org.add_member(user)
      team.add_member(user)

      child_user = create(:user)
      org.add_member(child_user)
      child_team.add_member(child_user)

      create(:copilot_seat, assigned_user: user, organization: org)

      assignment = create(:copilot_seat_assignment, organization: org, assignable: team)

      assert_equal 1, assignment.assignable_member_seat_count
      assert_equal 1, assignment.assignable_members_eligible_for_seats_count
      assert_equal 1, assignment.assignable_member_ids.count
      assert_equal 1, assignment.assignable_count
      assert_equal team.member_ids, assignment.assignable_member_ids

      refute assignment.requires_conversion?
    end

    test "does not require conversion when organization includes suspended member and other members have seats" do
      org = create(:organization)

      sus_user = create(:user)
      org.add_member(sus_user)
      sus_user.update_column(:suspended_at, Time.current)

      create(:copilot_seat, assigned_user: org.admins.first, organization: org)

      assignment = create(:copilot_seat_assignment, organization: org, assignable: org)

      assert_equal 1, assignment.assignable_member_seat_count
      assert_equal 1, assignment.assignable_members_eligible_for_seats_count
      assert_equal 2, assignment.assignable_member_ids.count
      assert_equal 2, assignment.assignable_count
      assert_equal org.member_ids, assignment.assignable_member_ids

      refute assignment.requires_conversion?
    end

    test "does not require conversion for user with multiple seats but sends exception" do
      Copilot::ErrorReporter.expects(:report!).once
      seat = create(:copilot_seat)
      other_seat = Copilot::Seat.new(
        organization: seat.organization,
        assigned_user: seat.assigned_user,
        seat_assignment: seat.seat_assignment
      )
      other_seat.save(validate: false)
      refute seat.seat_assignment.requires_conversion?
    end

    test "requires conversion for team" do
      assignment = create(:copilot_seat_assignment, :team)
      team = assignment.assignable
      user = create(:user)
      team.add_member(user)
      team.reload

      assert_equal 1, team.members.count
      assert_equal team.member_ids, assignment.assignable_member_ids
      assert assignment.requires_conversion?
    end

    test "doesn't require conversion for team with seats" do
      assignment = create(:copilot_seat_assignment, :team)
      team = assignment.assignable
      user = create(:user)
      team.add_member(user)
      team.reload

      assignment.convert_to_seats
      refute assignment.requires_conversion?
    end

    test "doesn't require conversion for team with a user who already has a seat" do
      team_assignment = create(:copilot_seat_assignment, :team)
      team = team_assignment.assignable
      organization = team_assignment.owner

      user = create(:user)
      organization.add_member(user)
      user_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: team_assignment.organization)
      user_assignment.convert_to_seats

      seat = Copilot::Seat.for_assigned_user_and_owner(user, organization).first
      assert seat
      team.add_member(user)
      team.reload

      refute team_assignment.requires_conversion?

      assert_no_changes -> { Copilot::Seat.count } do
        team_assignment.convert_to_seats
      end
    end

    test "requires conversion for enterprise team" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      assert_equal assignment.assignable.member_user_ids, assignment.assignable_member_ids
      assert assignment.requires_conversion?
    end

    test "doesn't require conversion for enterprise team with seats" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      assignment.convert_to_seats
      refute assignment.requires_conversion?
    end

    test "requires conversion for organization" do
      assignment = create(:copilot_seat_assignment, :organization)
      assert assignment.requires_conversion?
    end

    test "doesn't require conversion for organization with seats" do
      assignment = create(:copilot_seat_assignment, :organization)
      assignment.convert_to_seats
      refute assignment.requires_conversion?
    end

    test "doesn't require conversion for organization with a user who already has a seat" do
      organization = create(:organization)

      user_assignment = create(:copilot_seat_assignment, :user, assignable: organization.admins.first, organization: organization)
      user_assignment.convert_to_seats

      seat = Copilot::Seat.for_assigned_user_and_owner(organization.admins.first, organization).first
      assert seat

      refute user_assignment.requires_conversion?

      org_assignment = Copilot::SeatAssignment.new(
        assignable_type: "Organization",
        assignable_id: organization.id,
        owner_type: "Organization",
        owner_id: organization.id,
        organization: organization,
        assigning_user: organization.admins.first,
      )
      org_assignment.save(validate: false)

      org_assignment.reload
      refute org_assignment.requires_conversion?

      assert_no_changes -> { Copilot::Seat.count } do
        org_assignment.convert_to_seats
      end

      seat.reload
      assert_equal seat.seat_assignment.id, org_assignment.id
    end
  end

  context "batch_methods" do
    context "copilot_plan" do
      test "gets business by default" do
        GitHub.flipper[:copilot_mixed_licenses].disable
        seat_assignment = create(:copilot_seat_assignment, :organization)
        assert_equal :COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT, seat_assignment.copilot_sku
      end

      test "gets enterprise when passed" do
        GitHub.flipper[:copilot_mixed_licenses].disable
        seat_assignment = create(:copilot_seat_assignment, :organization, copilot_plan: "enterprise")
        assert_equal :COPILOT_ENTERPRISE_SEAT_ASSIGNMENT, seat_assignment.copilot_sku
      end

      test "gets standalone for an enterprise team" do
        seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
        assert_equal :COPILOT_STANDALONE_SEAT_ASSIGNMENT, seat_assignment.copilot_sku
      end

      test "sends an error" do
        seat_assignment = create(:copilot_seat_assignment, :organization)
        seat_assignment.stubs(:owner_type).returns("potato")
        assert_raises(Copilot::Errors::SeatAssignmentError) do
          seat_assignment.copilot_sku
        end
      end

      context "with mixed licensing" do
        test "gets business by default" do
          GitHub.flipper[:copilot_mixed_licenses].enable

          seat_assignment = create(:copilot_seat_assignment, :organization)
          assert_equal :COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT, seat_assignment.copilot_sku
        end

        test "gets enterprise when passed" do
          GitHub.flipper[:copilot_mixed_licenses].enable

          seat_assignment = create(:copilot_seat_assignment, :organization)
          Copilot::Organization.new(seat_assignment.owner).copilot_plan_enterprise!

          assert_equal :COPILOT_ENTERPRISE_SEAT_ASSIGNMENT, seat_assignment.copilot_sku
        end
      end
    end
  end
end if GitHub.copilot_enabled?
