# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotOrganizationsSeatManagementTest < GitHub::TestCase
  fixtures do
    @org = T.let(create(:business_organization), T.untyped) # rubocop:disable Sorbet/ForbidTUntyped
    @admin = T.let(@org.admins.first, T.untyped)  # rubocop:disable Sorbet/ForbidTUntyped
  end

  setup do
    @copilot_org = T.let(Copilot::Organization.new(@org), T.untyped)  # rubocop:disable Sorbet/ForbidTUntyped
  end

  context "#assign" do
    context "email address" do
      test "fails if assigning user is not admin" do
        assigning_user = create(:user)
        email_address = "monalisa@github.com"

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never
        result = @copilot_org.assign([email_address], assigning_user)
        refute result.ok?
        assert_equal "Inviter has insufficient permissions", result.error.message
      end

      test "fails it the email is empty" do
        assigning_user = create(:user)
        @org.add_admin(assigning_user)
        email_address = ""

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never
        result = @copilot_org.assign([email_address], assigning_user)
        refute result.ok?
        assert_equal "Invite requires either user or email", result.error.message
      end

      test "creates a SeatAssignment" do
        assigning_user = create(:user)
        @org.add_admin(assigning_user)
        email_address = "monalisa@github.com"

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once
        assert_changes -> { Copilot::SeatAssignment.count }, from: 0, to: 1 do
          result = @copilot_org.assign([email_address], assigning_user)
          assert result.ok?
        end
      end

      test "creates a SeatAssignment if the email belongs to a user too" do
        assigning_user = create(:user)
        @org.add_admin(assigning_user)
        user = create(:user)
        user.emails.map(&:verify!)
        email_address = user.email

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once
        assert_changes -> { Copilot::SeatAssignment.count }, from: 0, to: 1 do
          result = @copilot_org.assign([email_address], assigning_user)
          assert result.ok?
        end
      end

      test "creates a SeatAssignemt if the email belongs to an organization member too" do
        assigning_user = create(:user)
        @org.add_admin(assigning_user)
        user = create(:user)
        user.emails.map(&:verify!)
        email_address = user.email
        @org.add_member(user)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once
        assert_changes -> { Copilot::SeatAssignment.count }, from: 0, to: 1 do
          result = @copilot_org.assign([email_address], assigning_user)
          assert result.ok?
        end
      end

      test "reuses a SeatAssignment even" do
        assigning_user = create(:user)
        @org.add_admin(assigning_user)
        user = create(:user)
        user.emails.map(&:verify!)
        email_address = user.email
        @org.add_member(user)
        assignment = create(:copilot_seat_assignment, organization: @org, assignable: user, assigning_user: assigning_user, pending_cancellation_date: nil)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_reused).with(assignment, assigning_user).once
        assert_no_changes -> { Copilot::SeatAssignment.count } do
          result = @copilot_org.assign([email_address], assigning_user)
          assert result.ok?
        end
      end

      test "refreshes a SeatAssignment even" do
        assigning_user = create(:user)
        @org.add_admin(assigning_user)
        user = create(:user)
        user.emails.map(&:verify!)
        email_address = user.email
        @org.add_member(user)
        assignment = create(:copilot_seat_assignment, organization: @org, assignable: user, assigning_user: assigning_user, pending_cancellation_date: 2.weeks.from_now)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).with(assignment, assigning_user, pending_cancellation_date_was: assignment.pending_cancellation_date.iso8601).once
        assert_no_changes -> { Copilot::SeatAssignment.count } do
          result = @copilot_org.assign([email_address], assigning_user)
          assert result.ok?
        end
      end
    end

    context "user" do
      test "fails if assigning user is not admin" do
        assigning_user = create(:user)
        user = create(:user)

        result = @copilot_org.assign([user], assigning_user)

        refute result.ok?
        assert_equal "Inviting User is not an admin of the Organization", result.error.message
      end

      test "adding a user that is already added returns true" do
        user = create(:user)
        @org.add_member(user)

        seat_assignment = create(:copilot_seat_assignment, assignable: user, organization: @org)
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_reused).with(seat_assignment, @admin).once
        result = @copilot_org.assign([user], @admin)

        assert result.ok?
        assert_equal seat_assignment, result.value!.first
      end

      test "adding multiple users already added returns them" do
        users = 5.times.map do |_i|
          user = create(:user)
          @org.add_member(user)

          create(:copilot_seat_assignment, assignable: user, organization: @org)
          user
        end

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_reused).times(5)
        result = @copilot_org.assign(users, @org.admin)

        assert result.ok?
        assert_equal users.count, result.value!.count
      end

      test "adding multiple users already added refreshes them" do
        users = 5.times.map do |_i|
          user = create(:user)
          @org.add_member(user)

          create(:copilot_seat_assignment, assignable: user, organization: @org, pending_cancellation_date: 2.weeks.from_now)
          user
        end

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).times(5)
        result = @copilot_org.assign(users, @org.admin)

        assert result.ok?
        assert_equal users.count, result.value!.count
      end

      test "adding a user that doesn't already exist creates and returns true" do
        user = create(:user)
        @org.add_member(user)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once

        assert_difference "Copilot::SeatAssignment.count", 1 do
          result = @copilot_org.assign([user], @org.admin)
          assert result.ok?
          seat_assignment = result.value!.first
          assert_equal user, seat_assignment.assignable
        end
      end
    end

    context "team" do
      test "adding a team doesn't work if called on the wrong organization" do
        organization = create(:business_organization)
        team = create(:team, organization: organization)

        copilot_organization = Copilot::Organization.new(create(:business_organization))
        result = copilot_organization.assign([team], organization.admin)

        refute result.ok?
        refute_nil result.error
        assert_equal "Inviting User is not an admin of the Organization", result.error.message
      end

      test "adding a team doesn't work if called on the wrong organization even with valid team" do
        organization_team = create(:team, organization: @org)
        team = create(:team, organization: create(:business_organization))

        result = @copilot_org.assign([team, organization_team], @org.admin)

        refute result.ok?
        refute_nil result.error
        assert_equal "Validation failed: Assignable must belong to the organization", result.error.message
      end

      test "adding a team doesn't work if the assigning user is not an admin in the organization" do
        team = create(:team, organization: @org)
        user = create(:user)
        @org.add_member(user)

        result = @copilot_org.assign([team], user)

        refute result.ok?
        refute_nil result.error
        assert_equal "Inviting User is not an admin of the Organization", result.error.message
      end

      test "adding a team that is already added returns true" do
        team = create(:team, organization: @org)

        seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: @org)
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_reused).with(seat_assignment, @admin).once
        result = @copilot_org.assign([team], @admin)

        assert result.ok?
        assert_equal seat_assignment, result.value!.first
      end

      test "adding multiple already added returns them" do
        teams = create_list(:team, 5, organization: @org)
        seat_assignments = teams.map do |team|
          create(:copilot_seat_assignment, assignable: team, organization: @org)
        end

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_reused).times(5)
        result = @copilot_org.assign(teams, @org.admin)

        assert result.ok?
        assert_equal seat_assignments.count, result.value!.count
      end

      test "adding a team that is doesn't already exist creates and returns true" do
        team = create(:team, organization: @org)


        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once
        assert_difference "Copilot::SeatAssignment.count", 1 do
          result = @copilot_org.assign([team], @org.admin)
          assert result.ok?
          seat_assignments = result.value!
          assert_equal team, seat_assignments.first.assignable
        end
      end
    end

    context "organizationinvitation" do
      test "invites non-member to organization" do
        user = create(:user)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once


        assert_difference "Copilot::SeatAssignment.count", 1 do
          result = @copilot_org.assign([user], @admin)
          assert result.ok?
        end
      end

      test "doesn't invite blocked user organization" do
        user = create(:user)

        @org.block(user)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never

        result = @copilot_org.assign([user], @admin)
        refute result.ok?
      end

      test "doesn't add a user who opted out" do
        org_admin     = create(:user, login: "org-admin")
        organization  = create(:organization, admin: org_admin)

        invitee = create(:user, email: "invitee@example.com")
        invitee.emails.each(&:verify!)

        invitation = organization.invite(invitee, inviter: org_admin, role: :direct_member)
        invitation.opt_out(actor: invitee)

        assert OrganizationInvitation::OptOut.opted_out?(org: organization, invitee: invitee),
          "should say that '#{invitee}' is opted_out of this org"

        copilot_organization = Copilot::Organization.new(organization)

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never

        result = copilot_organization.assign([invitee], org_admin)
        refute result.ok?
      end

      test "doesn't invite member to organization - assigns user" do
        user = create(:user)
        @org.add_member(user)


        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once

        assert_difference "Copilot::SeatAssignment.count", 1 do
          result = @copilot_org.assign([user], @admin)
          assert result.ok?
          assert result.value!.first.assignable_type == "User"
        end
      end
    end

    context "organization" do
      test "fails if assigning user is not admin" do
        assigning_user = create(:user)

        result = @copilot_org.assign([@org], assigning_user)

        refute result.ok?
        assert_equal "Inviting User is not an admin of the Organization", result.error.message
      end

      test "adds the organization" do

        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).never
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once

        assert_difference "Copilot::SeatAssignment.count", 1 do
          result = @copilot_org.assign([@org], @org.admin)
          assert result.ok?
          seat_assignment = result.value!.first
          assert_equal @org, seat_assignment.assignable
        end
      end
    end
  end

  context "#unassign" do
    context "email address" do
      test "removes the email address immediately" do
        organization_invitation = create(:organization_invitation, organization: @org)
        create(:copilot_seat_assignment, assignable: organization_invitation, organization: @org)

        @copilot_org.assign([organization_invitation], @org.admin)
        assert_changes -> { Copilot::SeatAssignment.count }, from: 1, to: 0 do
          result = @copilot_org.unassign([organization_invitation], @admin)
          assert result.ok?
        end
      end

      test "doesn't do anything for unknown email address" do
        result = @copilot_org.unassign(["email@domain.com"], @admin)
        refute result.ok?
      end
    end

    context "organizationinvitation" do
      test "can't unassign a organizationinvitation that isn't assigned" do
        user = create(:user)
        invitation = create(:organization_invitation, organization: @org, inviter: @org.admin, invitee: user)

        result = @copilot_org.unassign([invitation], @admin)
        refute result.ok?
      end

      test "unassign a organizationinvitation that is assigned" do
        user = create(:user)
        invitation = create(:organization_invitation, organization: @org, inviter: @org.admin, invitee: user)

        seat_assignment = create(:copilot_seat_assignment, assignable: invitation, organization: @org)
        assert_nil seat_assignment.pending_cancellation_date

        @copilot_org.assign([invitation], @org.admin)
        assert_changes -> { Copilot::SeatAssignment.count }, from: 1, to: 0 do
          result = @copilot_org.unassign([invitation], @admin)
          assert result.ok?
        end
      end

      test "unassign a user that is assigned" do
        user = create(:user)
        @org.add_member(user)

        seat_assignment = create(:copilot_seat_assignment, assignable: user, organization: @org)
        assert_nil seat_assignment.pending_cancellation_date

        result = @copilot_org.unassign([user], @admin)
        assert result.ok?
        seat_assignment.reload
        refute_nil seat_assignment.pending_cancellation_date
      end
    end

    context "team" do
      test "can't unassign a team that isn't assigned" do
        team = create(:team, organization: @org)

        result = @copilot_org.unassign([team], @admin)
        refute result.ok?
      end

      test "unassign a user that is assigned" do
        team = create(:team, organization: @org)

        seat_assignment = create(:copilot_seat_assignment, assignable: team, organization: @org)
        assert_nil seat_assignment.pending_cancellation_date

        result = @copilot_org.unassign([team], @admin)
        assert result.ok?
        seat_assignment.reload
        refute_nil seat_assignment.pending_cancellation_date
      end
    end

    context "organization" do
      test "can't unassign an organization that isn't assigned" do
        result = @copilot_org.unassign([@org], @admin)
        refute result.ok?
      end

      test "unassign an organization that is assigned" do
        seat_assignment = create(:copilot_seat_assignment, assignable: @org, organization: @org)

        assert_nil seat_assignment.pending_cancellation_date

        result = @copilot_org.unassign([@org], @admin)

        assert result.ok?
        seat_assignment.reload
        refute_nil seat_assignment.pending_cancellation_date
      end
    end
  end

  context "#seat_assignments" do
    test "handles when teams go bye bye" do
      team = create(:team, organization: @org)
      team_sa = create(:copilot_seat_assignment, assignable: team, organization: @org, assigning_user: @admin)
      team.reload.destroy

      team_sa.reload
      seat_assignments = Copilot::Organization.new(@org).seat_assignments
      assert_equal 0, seat_assignments.count
    end

    test "handles when invites go bye bye" do
      invitation = @org.invite(create(:user), inviter: @admin)
      invitation.expire
      invitation_sa = create(:copilot_seat_assignment, assignable: invitation, organization: @org, assigning_user: @admin)
      invitation.destroy

      invitation_sa.reload
      seat_assignments = Copilot::Organization.new(@org).seat_assignments
      assert_equal 0, seat_assignments.count
    end

    test "it creates Copilot::Organizations::SeatManagement::Detail for all users, teams, and invites in the org" do
      user = create(:user)
      @org.add_member(user)
      user_sa = create(:copilot_seat_assignment, assignable: user, organization: @org, assigning_user: @admin)

      team = create(:team, organization: @org)
      team_sa = create(:copilot_seat_assignment, assignable: team, organization: @org, assigning_user: @admin)

      invitation = @org.invite(create(:user), inviter: @admin)
      invitation.expire
      invitation_sa = create(:copilot_seat_assignment, assignable: invitation, organization: @org, assigning_user: @admin)

      latest_invitation = @org.invite(create(:user), inviter: @admin)
      latest_invitation_sa = create(:copilot_seat_assignment, assignable: latest_invitation, organization: @org, assigning_user: @admin)

      seat_assignments = Copilot::Organization.new(@org).seat_assignments
      assert_equal 3, seat_assignments.count
      assert_equal user, seat_assignments.find { |sa| sa.seat_assignment_id == user_sa.id }&.assignable
      assert_equal team, seat_assignments.find { |sa| sa.seat_assignment_id == team_sa.id }&.assignable
      refute seat_assignments.any? { |sa| sa.seat_assignment_id == invitation_sa.id }
      assert_equal latest_invitation, seat_assignments.find { |sa| sa.seat_assignment_id == latest_invitation_sa.id }&.assignable
    end

    test "it includes expired invitations if there isn't an unexpired one for the same user" do
      user = create(:user)
      @org.add_member(user)
      create(:copilot_seat_assignment, assignable: user, organization: @org, assigning_user: @admin)

      invitation = @org.invite(create(:user), inviter: @admin)
      invitation.expire
      invitation_sa = create(:copilot_seat_assignment, assignable: invitation, organization: @org, assigning_user: @admin)

      seat_assignments = Copilot::Organization.new(@org).seat_assignments
      assert_equal 2, seat_assignments.count
      assert_equal invitation, seat_assignments.find { |sa| sa.seat_assignment_id == invitation_sa.id }&.assignable
    end

    test "it includes expired invitations if there isn't an unexpired one for the same invitee email" do
      user = create(:user)
      @org.add_member(user)
      create(:copilot_seat_assignment, assignable: user, organization: @org, assigning_user: @admin)

      invitation = @org.invite(nil, email: "test@test.com", inviter: @admin)
      invitation.expire
      invitation_sa = create(:copilot_seat_assignment, assignable: invitation, organization: @org, assigning_user: @admin)

      seat_assignments = Copilot::Organization.new(@org).seat_assignments
      assert_equal 2, seat_assignments.count
      assert_equal invitation, seat_assignments.find { |sa| sa.seat_assignment_id == invitation_sa.id }&.assignable
    end

    test "it does not include seat assignments with deleted invitations" do
      user = create(:user)
      @org.add_member(user)
      create(:copilot_seat_assignment, assignable: user, organization: @org, assigning_user: @admin)

      invitation = @org.invite(nil, email: "test@test.com", inviter: @admin)
      invitation_sa = create(:copilot_seat_assignment, assignable_type: "OrganizationInvitation", assignable: invitation, organization: @org, assigning_user: @admin)
      invitation.destroy

      seat_assignments = Copilot::Organization.new(@org).seat_assignments
      assert_equal 1, seat_assignments.count
      assert_nil seat_assignments.find { |sa| sa.seat_assignment_id == invitation_sa.id }
    end

    test "last_activity_at timestamp is set to the most recent activity for users, Time.at(0) for teams" do
      first_user = create(:user)
      @org.add_member(first_user)
      assignment = create(:copilot_seat_assignment, assignable: first_user, organization: @org, assigning_user: @admin)
      create(:copilot_seat, organization: @org, seat_assignment: assignment, assigned_user: first_user)
      first_user_most_recent = create(:copilot_aggregate_usage_detail, user: first_user, usage_date: Date.today, usage_hour: 1)
      create(:copilot_aggregate_usage_detail, user: first_user, usage_date: Date.today - 1.day, usage_hour: 1)

      second_user = create(:user)
      @org.add_member(second_user)
      assignment = create(:copilot_seat_assignment, assignable: second_user, organization: @org, assigning_user: @admin)
      create(:copilot_seat, organization: @org, seat_assignment: assignment, assigned_user: second_user)
      second_user_most_recent = create(:copilot_aggregate_usage_detail, user: second_user, usage_date: Date.today - 1.day, usage_hour: 2)
      create(:copilot_aggregate_usage_detail, user: second_user, usage_date: Date.today - 2.days, usage_hour: 2)

      team = create(:team, organization: @org)
      team.add_member(first_user)
      team.add_member(second_user)
      create(:copilot_seat_assignment, assignable: team, organization: @org, assigning_user: @admin)

      seat_assignments = Copilot::Organization.new(@org).seat_assignments

      first_user_last_activity_at = T.must(seat_assignments.find { |sa| T.must(sa.assignable).id == first_user.id }).last_activity_at
      second_user_last_activity_at = T.must(seat_assignments.find { |sa| T.must(sa.assignable).id == second_user.id }).last_activity_at
      team_last_activity_at = T.must(seat_assignments.find { |sa| T.must(sa.assignable).id == team.id }).last_activity_at
      assert_equal 3, seat_assignments.count
      assert_equal first_user_last_activity_at, first_user_most_recent.updated_at
      assert_equal second_user_last_activity_at, second_user_most_recent.updated_at
      assert_equal Time.at(0), team_last_activity_at
    end

    context "when passing in a query string" do
      test "find all applicable seats based on their case insensitive sortable_name" do
        user = create(:user, login: "find-this")
        @org.add_member(user)
        user_sa = create(:copilot_seat_assignment, assignable: user, organization: @org, assigning_user: @admin)

        team = create(:team, name: "also-FIND-this", organization: @org)
        team_sa = create(:copilot_seat_assignment, assignable: team, organization: @org, assigning_user: @admin)

        invitation = @org.invite(create(:user, login: "but-not-this"), inviter: @admin)
        invitation_sa = create(:copilot_seat_assignment, assignable: invitation, organization: @org, assigning_user: @admin)

        seat_assignments = Copilot::Organization.new(@org).seat_assignments(query: "find")
        assert_equal 2, seat_assignments.count
        assert_equal user, seat_assignments.find { |sa| sa.seat_assignment_id == user_sa.id }&.assignable
        assert_equal team, seat_assignments.find { |sa| sa.seat_assignment_id == team_sa.id }&.assignable
        assert_nil seat_assignments.find { |sa| sa.seat_assignment_id == invitation_sa.id }&.assignable
      end
    end

    context "when passing in a type filter" do
      test "it properly filters users" do
        user = create(:user)
        @org.add_member(user)
        user_sa = create(:copilot_seat_assignment, assignable: user, organization: @org, assigning_user: @admin)

        team = create(:team, organization: @org)
        team_sa = create(:copilot_seat_assignment, assignable: team, organization: @org, assigning_user: @admin)

        invitation = @org.invite(create(:user), inviter: @admin)
        invitation_sa = create(:copilot_seat_assignment, assignable: invitation, organization: @org, assigning_user: @admin)

        seat_assignments = Copilot::Organization.new(@org).seat_assignments(type: :users)
        assert_equal 1, seat_assignments.count
        assert_equal user, seat_assignments.find { |sa| sa.seat_assignment_id == user_sa.id }&.assignable
        assert_nil seat_assignments.find { |sa| sa.seat_assignment_id == team_sa.id }&.assignable
        assert_nil seat_assignments.find { |sa| sa.seat_assignment_id == invitation_sa.id }&.assignable
      end

      test "it properly filters teams" do
        user = create(:user)
        @org.add_member(user)
        user_sa = create(:copilot_seat_assignment, assignable: user, organization: @org, assigning_user: @admin)

        team = create(:team, organization: @org)
        team_sa = create(:copilot_seat_assignment, assignable: team, organization: @org, assigning_user: @admin)

        invitation = @org.invite(create(:user), inviter: @admin)
        invitation_sa = create(:copilot_seat_assignment, assignable: invitation, organization: @org, assigning_user: @admin)

        seat_assignments = Copilot::Organization.new(@org).seat_assignments(type: :teams)
        assert_equal 1, seat_assignments.count
        assert_nil seat_assignments.find { |sa| sa.seat_assignment_id == user_sa.id }&.assignable
        assert_equal team, seat_assignments.find { |sa| sa.seat_assignment_id == team_sa.id }&.assignable
        assert_nil seat_assignments.find { |sa| sa.seat_assignment_id == invitation_sa.id }&.assignable
      end

      test "it properly filters invitations" do
        user = create(:user)
        @org.add_member(user)
        user_sa = create(:copilot_seat_assignment, assignable: user, organization: @org, assigning_user: @admin)

        team = create(:team, organization: @org)
        team_sa = create(:copilot_seat_assignment, assignable: team, organization: @org, assigning_user: @admin)

        invitation = @org.invite(create(:user), inviter: @admin)
        invitation_sa = create(:copilot_seat_assignment, assignable: invitation, organization: @org, assigning_user: @admin)

        seat_assignments = Copilot::Organization.new(@org).seat_assignments(type: :organizationinvitations)
        assert_equal 1, seat_assignments.count
        assert_nil seat_assignments.find { |sa| sa.seat_assignment_id == user_sa.id }&.assignable
        assert_nil seat_assignments.find { |sa| sa.seat_assignment_id == team_sa.id }&.assignable
        assert_equal invitation, seat_assignments.find { |sa| sa.seat_assignment_id == invitation_sa.id }&.assignable
      end
    end

    context "when passing in a sort" do
      test "sorts by last_activity_at" do
        freeze_time do
          first_user = create(:user)
          @org.add_member(first_user)
          assignment = create(:copilot_seat_assignment, assignable: first_user, organization: @org, assigning_user: @admin)
          create(:copilot_seat, organization: @org, seat_assignment: assignment, assigned_user: first_user)
          create(:copilot_aggregate_usage_detail, user: first_user, usage_date: Date.today - 1.day)

          second_user = create(:user)
          @org.add_member(second_user)
          assignment = create(:copilot_seat_assignment, assignable: second_user, organization: @org, assigning_user: @admin)
          create(:copilot_seat, organization: @org, seat_assignment: assignment, assigned_user: second_user)
          create(:copilot_aggregate_usage_detail, user: second_user, usage_date: Date.today - 2.days)

          results = Copilot::Organization.new(@org).seat_assignments(sort: :last_activity_at, direction: :desc)
          assert_equal 2, results.count
          assert_equal first_user, T.must(results.first).assignable
          assert_equal second_user, results.second.assignable

          results = Copilot::Organization.new(@org).seat_assignments(sort: :last_activity_at, direction: :asc)
          assert_equal 2, results.count
          assert_equal second_user, T.must(results.first).assignable
          assert_equal first_user, results.second.assignable
        end
      end

      test "sorts by sortable_name" do
        first_user = create(:user, login: "alphabet")
        @org.add_member(first_user)
        assignment = create(:copilot_seat_assignment, assignable: first_user, organization: @org, assigning_user: @admin)
        create(:copilot_seat, organization: @org, seat_assignment: assignment, assigned_user: first_user)

        second_user = create(:user, login: "zoolander")
        @org.add_member(second_user)
        assignment = create(:copilot_seat_assignment, assignable: second_user, organization: @org, assigning_user: @admin)
        create(:copilot_seat, organization: @org, seat_assignment: assignment, assigned_user: second_user)

        results = Copilot::Organization.new(@org).seat_assignments(sort: :sortable_name, direction: :desc)
        assert_equal 2, results.count
        assert_equal second_user, T.must(results.first).assignable
        assert_equal first_user, results.second.assignable

        results = Copilot::Organization.new(@org).seat_assignments(sort: :sortable_name, direction: :asc)
        assert_equal 2, results.count
        assert_equal first_user, T.must(results.first).assignable
        assert_equal second_user, results.second.assignable
      end
    end
  end

  context "#all_org_seat_assignments" do
    test "it creates Copilot::Organizations::SeatManagement::Detail for all users, teams, and invites in the org" do
      freeze_time do
        assignment = create(:copilot_seat_assignment, :organization, organization: @org, assigning_user: @admin)
        assignment.convert_to_seats

        assert_equal 0, Copilot::AggregateUsageDetail.count
        create(:copilot_aggregate_usage_detail, user: @admin)
        Copilot::AggregateUsageDetail.create_for_user(@admin, "editor")

        usage_detail = Copilot::AggregateUsageDetail.latest_for_users(@admin)

        create(:copilot_aggregate_usage_detail, user: @admin, usage_date: Date.today - 2.days, usage_hour: 2, updated_at: Date.today - 2.days) #older one

        details = Copilot::Organization.new(@org).all_org_seat_assignments
        assert_equal 1, details.count #includes admin
        assert_equal @admin, T.must(details.first).assigned_user
        assert_equal assignment.id, T.must(details.first).seat_assignment_id
        assert_equal T.must(usage_detail).updated_at, T.must(details.first).last_activity_at
      end
    end

    context "when passing in a query string" do
      test "find all applicable seats based on their case insensitive sortable_name" do
        user = create(:user, login: "find-this")
        @org.add_member(user)

        assert_equal 0, Copilot::AggregateUsageDetail.count
        Copilot::AggregateUsageDetail.create_for_user(user, "editor")
        usage_detail = Copilot::AggregateUsageDetail.latest_for_users(user)

        assignment = create(:copilot_seat_assignment, :organization, organization: @org, assigning_user: @admin)
        assignment.convert_to_seats

        create(:copilot_aggregate_usage_detail, user: user, usage_date: Date.today - 2.days, usage_hour: 2, updated_at: Date.today - 2.days) #older one


        details = Copilot::Organization.new(@org).all_org_seat_assignments(query: "find")
        assert_equal 1, details.count # only this user
        assert_equal user, T.must(details.first).assigned_user
        assert_equal T.must(usage_detail).updated_at, T.must(details.first).last_activity_at
      end
    end

    context "when passing in a sort" do
      test "sorts by last_activity_at" do
        first_user = create(:user)
        @org.add_member(first_user)

        second_user = @admin

        assignment = create(:copilot_seat_assignment, :organization, organization: @org, assigning_user: @admin)
        assignment.convert_to_seats

        create(:copilot_aggregate_usage_detail, user: first_user, usage_date: Date.today - 1.day, usage_hour: 2)
        create(:copilot_aggregate_usage_detail, user: second_user, usage_date: Date.today - 2.days, usage_hour: 2) #older one

        results = Copilot::Organization.new(@org).all_org_seat_assignments(sort: :last_activity_at, direction: :desc)
        assert_equal 2, results.count
        assert_equal first_user.id, T.must(results.first).assigned_user.id
        assert_equal second_user.id, results.second.assigned_user.id

        results = Copilot::Organization.new(@org).all_org_seat_assignments(sort: :last_activity_at, direction: :asc)
        assert_equal 2, results.count
        assert_equal second_user.id, T.must(results.first).assigned_user.id
        assert_equal first_user.id, results.second.assigned_user.id
      end

      test "sorts by sortable_name" do
        first_user = create(:user, login: "alphabet")
        @org.add_member(first_user)

        second_user = create(:user, login: "zoolander")
        @org.add_member(second_user)

        assignment = create(:copilot_seat_assignment, :organization, organization: @org, assigning_user: @admin)
        assignment.convert_to_seats

        results = Copilot::Organization.new(@org).all_org_seat_assignments(sort: :sortable_name, direction: :desc)
        assert_equal 3, results.count
        assert_equal second_user.id, T.must(results.first).assigned_user.id
        assert_equal first_user.id, T.must(results.last).assigned_user.id # need to account for admin

        results = Copilot::Organization.new(@org).all_org_seat_assignments(sort: :sortable_name, direction: :asc)
        assert_equal 3, results.count
        assert_equal first_user.id, T.must(results.first).assigned_user.id
        assert_equal second_user.id, T.must(results.last).assigned_user.id
      end
    end
  end

  context "#all_copilot_seats_and_assignments_by_type_and_identifier" do
    test "returns empty arrays for all types when no seats or assignments exist" do
      results = @copilot_org.all_copilot_seats_and_assignments_by_type_and_identifier

      assert_equal 0, results[:user_ids].count
      assert_equal 0, results[:team_ids].count
      assert_equal 0, results[:invite_user_ids].count
      assert_equal 0, results[:invite_emails].count
    end

    test "returns the identifier for copilot seats and assignments by type" do
      # Create a user Seat assignment
      user = create(:user)
      @org.add_member(user)
      user_sa = create(:copilot_seat_assignment, assignable: user, organization: @org, assigning_user: @admin)
      user_sa.convert_to_seats

      # Create a team seat assignment (this creates two seats)
      team = create(:team, organization: @org)
      team_user_1 = create(:user)
      team_user_2 = create(:user)
      team.add_member(team_user_1)
      team.add_member(team_user_2)
      team_sa = create(:copilot_seat_assignment, assignable: team, organization: @org, assigning_user: @admin)
      team_sa.convert_to_seats

      # Create a email invitation and non-org user invitation (no seats)
      @org.seats = 10000
      @org.save
      non_org_user = create(:user)
      @copilot_org.assign(["invitee@example.com", @org.invite(non_org_user, inviter: @admin)], @admin)

      results = @copilot_org.all_copilot_seats_and_assignments_by_type_and_identifier

      assert_equal 3, results[:user_ids].count
      assert_equal [user.id, team_user_1.id, team_user_2.id], results[:user_ids]
      assert_equal 1, results[:team_ids].count
      assert_equal [team.id], results[:team_ids]
      assert_equal 1, results[:invite_user_ids].count
      assert_equal [non_org_user.id], results[:invite_user_ids]
      assert_equal 1, results[:invite_emails].count
      assert_equal ["invitee@example.com"], results[:invite_emails]
    end
  end
end if GitHub.copilot_enabled?
