# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotSeatAssignmentTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include DogstatsTestHelpers

  setup do
    disable_feature_flag(:copilot_revokable_access)
  end

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
        access_revoked_at: nil,
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

    test "assignable user does not need to belong to an org with copilot_revokable_access enabled" do
      enable_feature_flag(:copilot_revokable_access)

      user = create(:user)
      organization = create(:organization)

      seat_assignment = Copilot::SeatAssignment.build(
        owner: organization,
        assignable: user,
        assigning_user: organization.admin
      )

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

    context "suspended users" do
      test "suspended users cannot be assigned a seat assignment when copilot_revokable_access feature flag is disabled" do
        org = create(:organization)
        admin = org.admins.first
        naughty_person = create(:user, suspended_at: Time.now)
        org.add_member(naughty_person)

        seat_assignment = build(:copilot_seat_assignment, organization: org, assignable: naughty_person, assigning_user: admin)

        refute seat_assignment.valid?
        assert_equal seat_assignment.errors.count, 1
        assert seat_assignment.errors[:assignable].include?("Seat assignment cannot be created for a suspended user")
      end

      test "suspended users can be assigned a seat assignment when copilot_revokable_access feature flag is enabled" do
        enable_feature_flag(:copilot_revokable_access)

        org = create(:organization)
        admin = org.admins.first
        naughty_person = create(:user, suspended_at: Time.now)
        org.add_member(naughty_person)

        seat_assignment = build(:copilot_seat_assignment, organization: org, assignable: naughty_person, assigning_user: admin)

        assert seat_assignment.valid?
      end
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

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once
      seat_assignment.unassign!(organization.admins.first)

      refute_nil seat_assignment.pending_cancellation_date

      pending_cancellation_date = seat_assignment.pending_cancellation_date

      travel 32.days do
        assert seat_assignment.pending_cancellation?
        seat_assignment.unassign!(organization.admins.first)
        assert_equal pending_cancellation_date, seat_assignment.pending_cancellation_date
      end
    end

    context "user suspension" do
      test "it destroys the assignment if the user is suspended" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization, created_at: 10.days.ago, updated_at: 10.days.ago)
        user.suspend("naughty")

        assert_changes("Copilot::SeatAssignment.count", from: 1, to: 0) do
          seat_assignment.unassign!(organization.admins.first)
        end
      end

      test "it sets the assignment to pending cancellation when the copilot_revokable_access flag is enabled" do
        enable_feature_flag(:copilot_revokable_access)

        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization, created_at: 10.days.ago, updated_at: 10.days.ago)
        user.suspend("naughty")

        assert_no_changes("Copilot::SeatAssignment.count") do
          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once
          seat_assignment.unassign!(organization.admins.first)
        end
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
      disable_feature_flag(:copilot_auth_on_seat_assignment_creation)

      org = create(:organization)
      assert_enqueued_jobs(0, only: Copilot::Billing::OrganizationAuthAndCaptureJob) do
        create(:copilot_seat_assignment, :organization, organization: org)
      end
    end

    test "enqueues A&C only once if the copilot_auth_on_seat_assignment_creation flag is enabled" do
      enable_feature_flag(:copilot_auth_on_seat_assignment_creation)

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
      enable_feature_flag(:copilot_auth_on_seat_assignment_creation)
      enable_feature_flag(:copilot_delayed_auth_on_seat_assignment_creation)

      org = create(:organization)

      create(:copilot_seat_assignment, :organization, organization: org)
      # rubocop:disable Style/HashSyntax
      assert_enqueued_with(job: Copilot::Billing::OrganizationAuthAndCaptureJob, args: [org.id, { :skip_account_age_check => true, :audit_log_reason => "seat_assignment_creation" }])
      assert_enqueued_with(job: Copilot::Billing::OrganizationAuthAndCaptureJob, args: [org.id, { :skip_previous_authorizations_check => true, :skip_account_age_check => true, :audit_log_reason => "seat_assignment_creation_delayed_check" }])

      # Adding another seat doesn't trigger more auth checks
      assert_enqueued_jobs(0, only: Copilot::Billing::OrganizationAuthAndCaptureJob) do
        create(:copilot_seat_assignment, :organization, organization: org)
      end
    end

    test "enqueues A&C only once if the flag copilot_delayed_auth_on_seat_assignment_creation is enabled but org is trusted" do
      enable_feature_flag(:copilot_auth_on_seat_assignment_creation)
      enable_feature_flag(:copilot_delayed_auth_on_seat_assignment_creation)

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

  context "#access_revoked?" do
    test "returns true when access_revoked_at is set" do
      seat_assignment = create(:copilot_seat_assignment, :user, access_revoked_at: 1.day.ago.utc)
      assert seat_assignment.access_revoked?
    end

    test "returns false when access_revoked_at is nil" do
      seat_assignment = create(:copilot_seat_assignment, :user, access_revoked_at: nil)
      refute seat_assignment.access_revoked?
    end
  end

  context "requires_conversion/assignable_member_seat_count" do
    test "does nothing for organizationinvitations" do
      assignment = create(:copilot_seat_assignment, :organization_invitation)
      assert_equal 0, assignment.assignable_member_seat_count
      refute assignment.requires_conversion?
    end

    test "requires conversion for user without seat" do
      assignment = create(:copilot_seat_assignment, :user)
      assert_equal 0, assignment.assignable_member_seat_count
      assert_equal 1, assignment.seat_member_difference
      assert_equal 1, assignment.assignable_members_eligible_for_seats_count
      assert assignment.requires_conversion?
    end

    test "does not require conversion for user with a single seat" do
      seat = create(:copilot_seat)
      assert_equal 0, seat.seat_assignment.seat_member_difference
      assert_equal 1, seat.seat_assignment.assignable_member_seat_count
      assert_equal 1, seat.seat_assignment.assignable_members_eligible_for_seats_count
      refute seat.seat_assignment.requires_conversion?
    end

    test "does not require conversion when user is suspended" do
      assignment = create(:copilot_seat_assignment, :user)
      assignment.assignable.update_column(:suspended_at, Time.current)

      assert_equal 0, assignment.assignable_member_seat_count
      assert_equal 0, assignment.assignable_members_eligible_for_seats_count
      assert_equal 0, assignment.seat_member_difference
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
      assert_equal 0, assignment.seat_member_difference
      assert_equal 2, assignment.assignable_member_ids.count
      assert_equal 2, assignment.assignable_count
      assert_equal team.member_ids, assignment.assignable_member_ids

      refute assignment.requires_conversion?
    end

    test "does not require conversion when child team includes suspended member and other members have seats, with child team feature flag enabled" do
      org = create(:organization)
      enable_feature_flag(:copilot_child_teams)
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
      assert_equal 0, assignment.seat_member_difference
      assert_equal 2, assignment.assignable_member_ids.count
      assert_equal 2, assignment.assignable_count
      assert_equal team.member_ids + child_team.member_ids, assignment.assignable_member_ids

      refute assignment.requires_conversion?
    end

    test "requires conversion when child team member does not have a seat, with child team feature flag enabled" do
      org = create(:organization)
      enable_feature_flag(:copilot_child_teams)
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
      assert_equal 1, assignment.seat_member_difference
      assert_equal 2, assignment.assignable_member_ids.count
      assert_equal 2, assignment.assignable_count
      assert_equal [user.id, child_team_member.id], assignment.assignable_member_ids

      assert assignment.requires_conversion?
    end

    test "does not require conversion when child team member does not have a seat, with child team feature flag disabled" do
      org = create(:organization)
      disable_feature_flag(:copilot_child_teams)
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
      assert_equal 0, assignment.seat_member_difference
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
      assert_equal 0, assignment.seat_member_difference
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
      assert_equal 1, assignment.seat_member_difference
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
      assert_equal 0, assignment.seat_member_difference
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

      assert_equal 0, team_assignment.seat_member_difference
      refute team_assignment.requires_conversion?

      assert_no_changes -> { Copilot::Seat.count } do
        team_assignment.convert_to_seats
      end
    end

    test "requires conversion for enterprise team" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      assert_equal assignment.assignable.member_user_ids, assignment.assignable_member_ids
      assert_equal assignment.assignable_member_ids.count, assignment.seat_member_difference
      assert assignment.requires_conversion?
    end

    test "doesn't require conversion for enterprise team with seats" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      assignment.convert_to_seats
      assert_equal 0, assignment.seat_member_difference
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

      seat = Copilot::Seat.for_assigned_user_and_owner(organization.admins.first, organization).first!
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
      assert_equal seat.seat_assignment&.id, org_assignment.id
    end
  end

  context "batch_methods" do
    context "copilot_plan" do
      test "gets business by default" do
        seat_assignment = create(:copilot_seat_assignment, :organization)
        assert_equal :COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT, seat_assignment.copilot_sku
      end

      test "gets enterprise when passed" do
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
    end
  end

  context "access revocation and reinstatement" do
    context "#unassign_and_revoke_access!" do
      test "unassigns and revokes access" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: org)
        assert assignment.includes_user?(user)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once
        Copilot::Instrumenter.expects(:instrument_copilot_user_access_revoked).once
        assert_no_changes("Copilot::SeatAssignment.count") do
          assignment.unassign_and_revoke_access!(org.admins.first, :see_yaaa)

          assert assignment.reload.access_revoked_at.present?
          assert assignment.reload.pending_cancellation?
        end
      end

      test "does not revoke access when assignment is an OrganizationInvitation" do
        org = create(:organization)
        assignment = create(:copilot_seat_assignment, :organization_invitation, organization: org)

        assert_changes("Copilot::SeatAssignment.count", -1) do
          assignment.expects(:revoke_access!).never
          assignment.unassign_and_revoke_access!(org.admins.first, :see_yaaa)
        end
      end

      test "raises error and bails when assignment is not a user and force is not passed" do
        org = create(:organization)
        assignment = create(:copilot_seat_assignment, assignable: org, owner: org, assigning_user: org.admins.first)

        assert_raises(Copilot::Errors::SeatAssignmentError) do
          assignment.unassign_and_revoke_access!(org.admins.first, :see_yaaa)
        end
        assert_nil assignment.access_revoked_at
      end
    end

    context "#revoke_access!" do
      test "happy path revocation" do
        travel_to Time.current do
          org = create(:organization)
          assignment = create(:copilot_seat_assignment, :user, assignable: org.admins.first, owner: org, assigning_user: org.admins.first)
          reason = :just_because
          details = { shark: "nado" }
          Copilot::Instrumenter.expects(:instrument_copilot_user_access_revoked).once.with(assignment, reason, details)


          assignment.revoke_access!(reason, details)
          assert_equal Time.now, assignment.access_revoked_at
          assert_equal assignment.updated_at, Time.now
          assert_dogstats_increment(1, "copilot.seat_assignment.access_revoked")
        end
      end

      test "raises an error if assignable type is not a user" do
        Copilot::ErrorReporter
          .expects(:report!)
          .with(
            instance_of(Copilot::Errors::SeatAssignmentError),
            copilot_seat_assignment: instance_of(Copilot::SeatAssignment)
          )
          .times(3)

        [:team, :organization, :enterprise_team].each do |assignable_type|
          assignment = create(:copilot_seat_assignment, assignable_type, access_revoked_at: Time.now)
          assert_raises(Copilot::Errors::SeatAssignmentError) do
            assignment.revoke_access!(:naughty)
          end
        end

        assignment = create(:copilot_seat_assignment, :user)
        assert_nothing_raised do
          assignment.revoke_access!(:naughty)
        end
      end

      test "is a no-op if access is already revoked" do
        assignment = create(:copilot_seat_assignment, :user, access_revoked_at: Time.now)

        Copilot::Instrumenter.expects(:instrument_copilot_user_access_revoked).never

        assert_no_changes -> { assignment.access_revoked_at } do
          assignment.revoke_access!(:naughty)
        end
      end
    end

    context "#reinstate_access!" do
      test "happy path reinstatement" do
        travel_to Time.current do
          org = create(:organization)
          assignment = create(:copilot_seat_assignment, :user, assignable: org.admins.first, owner: org, assigning_user: org.admins.first, access_revoked_at: 1.day.ago.utc)
          reason = :just_because
          details = { shark: "nado" }
          Copilot::Instrumenter.expects(:instrument_copilot_user_access_reinstated).once.with(assignment, reason, details)

          assignment.reinstate_access!(reason, details)
          assert_nil assignment.access_revoked_at
          assert_equal assignment.updated_at, Time.now
          assert_dogstats_increment(1, "copilot.seat_assignment.access_reinstated")
        end
      end

      test "raises an error if assignable type is not a user" do
        Copilot::ErrorReporter
          .expects(:report!)
          .with(
            instance_of(Copilot::Errors::SeatAssignmentError),
            copilot_seat_assignment: instance_of(Copilot::SeatAssignment)
          )
          .times(3)

        [:team, :organization, :enterprise_team].each do |assignable_type|
          assignment = create(:copilot_seat_assignment, assignable_type, access_revoked_at: nil)
          assert_raises(Copilot::Errors::SeatAssignmentError) do
            assignment.reinstate_access!(:nice)
          end
        end

        assignment = create(:copilot_seat_assignment, :user, access_revoked_at: nil)
        assert_nothing_raised do
          assignment.reinstate_access!(:nice)
        end
      end

      test "is a no-op if access is already reinstated" do
        assignment = create(:copilot_seat_assignment, :user, access_revoked_at: nil)

        Copilot::Instrumenter.expects(:instrument_copilot_user_access_reinstated).never

        assert_no_changes -> { assignment.access_revoked_at } do
          assignment.reinstate_access!(:nice)
        end
      end
    end
  end
end if GitHub.copilot_enabled?

class CopilotSeatAssignmentCooldownDestructionTest < GitHub::TestCase
  include DogstatsTestHelpers

  setup do
    enable_feature_flag(:copilot_destroy_seat_assignment_in_cooldown_period)

    # we need to do this otherwise the delay is set to 0 for all types in the test environment
    silence_warnings do
      ::Copilot::COPILOT_SEAT_COOLDOWN_PERIODS = T.let({
        ENTERPRISE_TEAM: 15.minutes,
        ORGANIZATION: 30.minutes,
        TEAM: 15.minutes,
        USER: 1.minute,
      }, T::Hash[Symbol, ActiveSupport::Duration])
    end
  end

  context "#unassign!" do
    test "destroys seat assignment if in cooldown period" do
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)

      freeze_time do
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization, created_at: 30.seconds.ago)
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once.with(seat_assignment, organization.admins.first, :unassigned_during_cooldown, { unassigned_during_cooldown: true })
        seat_assignment.unassign!(organization.admins.first)

        refute Copilot::SeatAssignment.exists?(seat_assignment.id)
        assert_dogstats_increment(1, "copilot.seat_assignment.unassigned_within_cooldown")
      end
    end

    test "unassigns seat assignment if in cooldown period with copilot_destroy_seat_assignment_in_cooldown disabled" do
      disable_feature_flag(:copilot_destroy_seat_assignment_in_cooldown_period)
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)

      freeze_time do
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization, created_at: 30.seconds.ago)
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once.with(seat_assignment, organization.admins.first, :updated)
        seat_assignment.unassign!(organization.admins.first)

        assert Copilot::SeatAssignment.exists?(seat_assignment.id)
        refute_nil seat_assignment.pending_cancellation_date
        assert_dogstats_increment(1, "copilot.seat_assignment.unassigned_within_cooldown")
      end
    end

    test "unassigns and revokes access within cooldown with feature flag disabled" do
      disable_feature_flag(:copilot_destroy_seat_assignment_in_cooldown_period)
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)

      freeze_time do
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization, created_at: 30.seconds.ago)
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once.with(seat_assignment, organization.admins.first, :adios)

        seat_assignment.unassign_and_revoke_access!(organization.admins.first, :adios)

        assert Copilot::SeatAssignment.exists?(seat_assignment.id)
        refute_nil seat_assignment.pending_cancellation_date
        refute_nil seat_assignment.access_revoked_at
        assert_dogstats_increment(1, "copilot.seat_assignment.unassigned_within_cooldown")
      end
    end

    test "can't revoke access when seat assignment is destroyed within cooldown" do
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)

      freeze_time do
        seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization, created_at: 30.seconds.ago)
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once.with(seat_assignment, organization.admins.first, :unassigned_during_cooldown, { unassigned_during_cooldown: true })
        seat_assignment.expects(:revoke_access!).never
        seat_assignment.unassign_and_revoke_access!(organization.admins.first, :adios)

        refute Copilot::SeatAssignment.exists?(seat_assignment.id)
        assert_dogstats_increment(1, "copilot.seat_assignment.unassigned_within_cooldown")
      end
    end

    test "unassigns and does not destroy if not in cooldown period" do
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)
      seat_assignment = create(:copilot_seat_assignment, :user, assignable: user, organization: organization, created_at: 11.minutes.ago)

      freeze_time do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once
        seat_assignment.unassign!(organization.admins.first)

        assert Copilot::SeatAssignment.exists?(seat_assignment.id)
        refute_nil seat_assignment.pending_cancellation_date
        refute_dogstats_increment("copilot.seat_assignment.unassigned_within_cooldown")
      end
    end
  end

  context "#in_cooldown_period?" do
    test "user seat assignment respects cooldown period" do
      freeze_time do
        seat_assignment = create(:copilot_seat_assignment, :user, created_at: 30.seconds.ago)
        assert seat_assignment.in_cooldown_period?

        seat_assignment = create(:copilot_seat_assignment, :user, created_at: 2.minutes.ago)
        refute seat_assignment.in_cooldown_period?
        assert_dogstats_increment(1, "copilot.seat_assignment.unassigned_within_cooldown")
      end
    end

    test "team seat assignment respects cooldown period" do
      freeze_time do
        seat_assignment = create(:copilot_seat_assignment, :team, created_at: 14.minutes.ago)
        assert seat_assignment.in_cooldown_period?

        seat_assignment = create(:copilot_seat_assignment, :team, created_at: 16.minutes.ago)
        refute seat_assignment.in_cooldown_period?

        assert_dogstats_increment(1, "copilot.seat_assignment.unassigned_within_cooldown")
      end
    end

    test "organization seat assignment respects cooldown period" do
      freeze_time do
        seat_assignment = create(:copilot_seat_assignment, :organization, created_at: 29.minutes.ago)
        assert seat_assignment.in_cooldown_period?

        seat_assignment = create(:copilot_seat_assignment, :organization, created_at: 31.minutes.ago)
        refute seat_assignment.in_cooldown_period?

        assert_dogstats_increment(1, "copilot.seat_assignment.unassigned_within_cooldown")
      end
    end

    test "enterprise team seat assignment respects cooldown period" do
      freeze_time do
        seat_assignment = create(:copilot_seat_assignment, :enterprise_team, created_at: 14.minutes.ago)
        assert seat_assignment.in_cooldown_period?

        seat_assignment = create(:copilot_seat_assignment, :enterprise_team, created_at: 16.minutes.ago)
        refute seat_assignment.in_cooldown_period?

        assert_dogstats_increment(1, "copilot.seat_assignment.unassigned_within_cooldown")
      end
    end

    test "always returns false for organization invitation seat assignment" do
      freeze_time do
        seat_assignment = create(:copilot_seat_assignment, :organization_invitation, created_at: 30.seconds.ago)
        refute seat_assignment.in_cooldown_period?

        seat_assignment = create(:copilot_seat_assignment, :organization_invitation, created_at: 45.minutes.ago)
        refute seat_assignment.in_cooldown_period?

        refute_dogstats_increment("copilot.seat_assignment.unassigned_within_cooldown")
      end
    end
  end
end if GitHub.copilot_enabled?
