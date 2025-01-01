# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::SeatManagement::AssignerTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @business = create(:business)
    @organization = create(:organization, business: @business)
    @business_admin = @business.admins.first
    @organization_admin = @organization.admins.first
  end

  context "#assign" do
    context "when assigning an organization" do
      context "when the org seat assignment already exists" do
        test "returns the org seat assignment and instruments refreshed if the assignment was pending cancellation" do
          org_assignment = create(:copilot_seat_assignment, :user, assignable: @organization, owner: @organization, assigning_user: @organization_admin, pending_cancellation_date: Date.today)

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).once
          result = Copilot::SeatManagement::Assigner.new(@organization).assign(@organization, @organization_admin)

          assert_equal org_assignment, result.value!
          assert_nil result.value!.pending_cancellation_date
        end

        test "returns the org seat assignment and instruments reused if the assignment wasn't pending cancellation" do
          org_assignment = create(:copilot_seat_assignment, :user, assignable: @organization, owner: @organization, assigning_user: @organization_admin)

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_reused).once
          result = Copilot::SeatManagement::Assigner.new(@organization).assign(@organization, @organization_admin)

          assert_equal org_assignment, result.value!
        end
      end

      context "when the org seat assignment does not already exist" do
        test "raises an error if the owner is a business" do
          result = Copilot::SeatManagement::Assigner.new(@business).assign(@organization, @business_admin)

          assert_equal "Businesses cannot assign seats to orgs", result.error.message
        end

        test "creates a seat assignment for the org" do
          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once

          assert_changes -> { Copilot::SeatAssignment.count }, from: 0, to: 1 do
            result = Copilot::SeatManagement::Assigner.new(@organization).assign(@organization, @organization_admin)

            assert result.ok?
            assert_equal @organization, result.value!.assignable
            assert_equal @organization, result.value!.owner
            assert_equal @organization_admin, result.value!.assigning_user
          end
        end

        test "queues background job after cooling off period" do
          GitHub.flipper[:copilot_seat_assignment_job].enable

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once
          Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).once
          Copilot::SeatManagement::SeatAssignmentConverterJob
            .expects(:set)
            .with(wait: Copilot::COPILOT_FOR_BUSINESS_SEAT_DELAYS[:ORGANIZATION])
            .returns(Copilot::SeatManagement::SeatAssignmentConverterJob)
            .once

          result = Copilot::SeatManagement::Assigner.new(@organization).assign(@organization, @organization_admin)
          assert result.ok?
        end
      end
    end

    context "when assigning a user" do
      test "requires the assigning user to be an admin of the organization" do
        assigning_user = create(:user)
        assignee = create(:user)
        @organization.add_member(assignee)
        result = Copilot::SeatManagement::Assigner.new(@organization).assign(assignee, assigning_user)

        assert_equal "Inviting User is not an admin of the Organization", result.error.message
      end

      context "when the user seat assignment already exists" do
        test "returns the user seat assignment and instruments refreshed if the assignment was pending cancellation" do
          assignee = create(:user)
          @organization.add_member(assignee)
          user_assignment = create(:copilot_seat_assignment, :user, assignable: assignee, owner: @organization, assigning_user: @organization_admin, pending_cancellation_date: Date.today)

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).once
          result = Copilot::SeatManagement::Assigner.new(@organization).assign(assignee, @organization_admin)

          assert_equal user_assignment, result.value!
          assert_nil result.value!.pending_cancellation_date
        end

        test "returns the user seat assignment and instruments reused if the assignment wasn't pending cancellation" do
          assignee = create(:user)
          @organization.add_member(assignee)
          user_assignment = create(:copilot_seat_assignment, :user, assignable: assignee, owner: @organization, assigning_user: @organization_admin)

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_reused).once
          result = Copilot::SeatManagement::Assigner.new(@organization).assign(assignee, @organization_admin)

          assert_equal user_assignment, result.value!
        end
      end

      context "when the user seat assignment does not already exist" do
        test "creates a new user seat assignment if the user is in the org" do
          assignee = create(:user)
          @organization.add_member(assignee)

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once

          assert_changes -> { Copilot::SeatAssignment.count }, from: 0, to: 1 do
            result = Copilot::SeatManagement::Assigner.new(@organization).assign(assignee, @organization_admin)

            assert result.ok?
            assert_equal assignee, result.value!.assignable
            assert_equal @organization, result.value!.owner
            assert_equal @organization_admin, result.value!.assigning_user
          end
        end

        test "queues background job after cooling off period" do
          GitHub.flipper[:copilot_seat_assignment_job].enable
          assignee = create(:user)
          @organization.add_member(assignee)

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once
          Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).once
          Copilot::SeatManagement::SeatAssignmentConverterJob
            .expects(:set)
            .with(wait: Copilot::COPILOT_FOR_BUSINESS_SEAT_DELAYS[:USER])
            .returns(Copilot::SeatManagement::SeatAssignmentConverterJob)
            .once

          result = Copilot::SeatManagement::Assigner.new(@organization).assign(assignee, @organization_admin)
          assert result.ok?
        end

        test "sends an invite if the user is not in the org" do
          assignee = create(:user)

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once

          assert_changes -> { Copilot::SeatAssignment.count }, from: 0, to: 1 do
            assert_changes -> { OrganizationInvitation.count }, from: 0, to: 1 do
              result = Copilot::SeatManagement::Assigner.new(@organization).assign(assignee, @organization_admin)

              assert result.ok?
              assert result.value!.assignable.is_a?(OrganizationInvitation)
            end
          end
        end

        test "returns a non-ok result if the user is an org member and suspended" do
          assignee = create(:user)
          @organization.add_member(assignee)
          assignee.suspend("bad boy")
          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never

          assert_no_changes -> { Copilot::SeatAssignment.count } do
            result = Copilot::SeatManagement::Assigner.new(@organization).assign(assignee, @organization_admin)

            refute result.ok?
          end
        end

        test "returns a non-ok result if the user is not an org member and suspended" do
          assignee = create(:user)
          assignee.suspend("bad boy")
          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never

          assert_no_changes -> { Copilot::SeatAssignment.count } do
            result = Copilot::SeatManagement::Assigner.new(@organization).assign(assignee, @organization_admin)

            refute result.ok?
          end
        end

        context "when the org is on a trial" do
          test "requires the assignee be a member of the organization" do
            create(:copilot_business_trial, :organization, trialable: @organization)
            assignee = create(:user)
            result = Copilot::SeatManagement::Assigner.new(@organization).assign(assignee, @organization_admin)

            assert_equal "User is not a member of the organization", result.error.message
          end

          test "fails if the assignee has CFI access" do
            create(:copilot_business_trial, :organization, trialable: @organization)
            assignee = create(:copilot_free_user, subscribed: true, subscribed_at: Time.now).user
            @organization.add_member(assignee)
            result = Copilot::SeatManagement::Assigner.new(@organization).assign(assignee, @organization_admin)

            assert_equal "User already has Copilot access and cannot be assigned to a seat during a trial", result.error.message
          end

          test "creates a new user seat assignment if user is valid for a trial org" do
            create(:copilot_business_trial, :organization, trialable: @organization)
            assignee = create(:user)
            @organization.add_member(assignee)

            Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once

            assert_changes -> { Copilot::SeatAssignment.count }, from: 0, to: 1 do
              result = Copilot::SeatManagement::Assigner.new(@organization).assign(assignee, @organization_admin)

              assert result.ok?
              assert_equal assignee, result.value!.assignable
              assert_equal @organization, result.value!.owner
              assert_equal @organization_admin, result.value!.assigning_user
            end
          end
        end

        context "when the org is an EMU org" do
          test "creates a new user seat assignment if the user is in the org" do
            emu = create(:emu)
            emu_business = emu.enterprise_managed_business
            emu_org = create :enterprise_linked_organization, business: emu_business, admin: emu

            Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once

            assert_changes -> { Copilot::SeatAssignment.count }, from: 0, to: 1 do
              result = Copilot::SeatManagement::Assigner.new(emu_org).assign(emu, emu)

              assert_equal emu, result.value!.assignable
              assert_equal emu_org, result.value!.owner
              assert_equal emu, result.value!.assigning_user
            end
          end

          test "does not send an invite if the user is not in the org" do
            emu = create(:emu)
            emu_business = emu.enterprise_managed_business
            emu_org = create :enterprise_linked_organization, business: emu_business, admin: emu
            outside_user = create(:user)
            result = Copilot::SeatManagement::Assigner.new(emu_org).assign(outside_user, emu)

            assert_equal "EMUs must be added to the organization before they can be assigned seats", result.error.message
          end
        end
      end
    end

    context "when assigning a team" do
      context "when the team seat assignment already exists" do
        test "returns the team seat assignment and instruments refreshed if the assignment was pending cancellation" do
          team = create(:team, organization: @organization)
          team_assignment = create(:copilot_seat_assignment, :team, assignable: team, owner: @organization, assigning_user: @organization_admin, pending_cancellation_date: Date.today)

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).once
          result = Copilot::SeatManagement::Assigner.new(@organization).assign(team, @organization_admin)

          assert_equal team_assignment, result.value!
          assert_nil result.value!.pending_cancellation_date
        end

        test "returns the team seat assignment and instruments reused if the assignment wasn't pending cancellation" do
          team = create(:team, organization: @organization)
          team_assignment = create(:copilot_seat_assignment, :team, assignable: team, owner: @organization, assigning_user: @organization_admin)

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_reused).once
          result = Copilot::SeatManagement::Assigner.new(@organization).assign(team, @organization_admin)

          assert_equal team_assignment, result.value!
        end
      end

      context "when the team seat assignment does not already exist" do
        test "raises an error if the owner is a business" do
          team = create(:team, organization: @organization)
          result = Copilot::SeatManagement::Assigner.new(@business).assign(team, @business_admin)

          assert_equal "Businesses cannot assign seats to teams", result.error.message
        end

        test "creates a seat assignment for the team" do
          team = create(:team, organization: @organization)
          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once

          assert_changes -> { Copilot::SeatAssignment.count }, from: 0, to: 1 do
            result = Copilot::SeatManagement::Assigner.new(@organization).assign(team, @organization_admin)

            assert result.ok?
            assert_equal team, result.value!.assignable
            assert_equal @organization, result.value!.owner
            assert_equal @organization_admin, result.value!.assigning_user
          end
        end

        test "queues background job after cooling off period" do
          GitHub.flipper[:copilot_seat_assignment_job].enable
          team = create(:team, organization: @organization)

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once
          Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).once
          Copilot::SeatManagement::SeatAssignmentConverterJob
            .expects(:set)
            .with(wait: Copilot::COPILOT_FOR_BUSINESS_SEAT_DELAYS[:TEAM])
            .returns(Copilot::SeatManagement::SeatAssignmentConverterJob)
            .once

          result = Copilot::SeatManagement::Assigner.new(@organization).assign(team, @organization_admin)
          assert result.ok?
        end
      end
    end

    context "when assigning an organization invitation" do
      context "when the invite seat assignment already exists" do
        test "returns the invite seat assignment and instruments refreshed if the assignment was pending cancellation" do
          org_invite = create(:organization_invitation, organization: @organization, inviter: @organization_admin)
          invite_assignment = create(:copilot_seat_assignment, :organization_invitation, assignable: org_invite, owner: @organization, assigning_user: @organization_admin, pending_cancellation_date: Date.today)

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).once
          result = Copilot::SeatManagement::Assigner.new(@organization).assign(org_invite, @organization_admin)

          assert_equal invite_assignment, result.value!
          assert_nil result.value!.pending_cancellation_date
        end

        test "returns the invite seat assignment and instruments reused if the assignment wasn't pending cancellation" do
          org_invite = create(:organization_invitation, organization: @organization, inviter: @organization_admin)
          invite_assignment = create(:copilot_seat_assignment, :organization_invitation, assignable: org_invite, owner: @organization, assigning_user: @organization_admin)

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_reused).once
          result = Copilot::SeatManagement::Assigner.new(@organization).assign(org_invite, @organization_admin)

          assert_equal invite_assignment, result.value!
        end
      end

      context "when the invite seat assignment does not already exist" do
        test "raises an error if the owner is a business" do
          org_invite = create(:organization_invitation, organization: @organization, inviter: @organization_admin)
          result = Copilot::SeatManagement::Assigner.new(@business).assign(org_invite, @business_admin)

          assert_equal "Businesses cannot assign seats to organization invitations", result.error.message
        end

        test "creates a seat assignment for the invitation" do
          org_invite = create(:organization_invitation, organization: @organization, inviter: @organization_admin)
          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never

          assert_changes -> { Copilot::SeatAssignment.count }, from: 0, to: 1 do
            result = Copilot::SeatManagement::Assigner.new(@organization).assign(org_invite, @organization_admin)

            assert result.ok?
            assert_equal org_invite, result.value!.assignable
            assert_equal @organization, result.value!.owner
            assert_equal @organization_admin, result.value!.assigning_user
          end
        end

        test "does not queue background job for organization invitation" do
          GitHub.flipper[:copilot_seat_assignment_job].enable
          assignable = create(:user)
          assigning_user = @organization.admins.first

          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once
          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).never
          Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).never
          Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:set).never
          assigner = Copilot::SeatManagement::Assigner.new(@organization)

          result = assigner.assign(assignable, assigning_user)
          assert result.ok?
        end
      end
    end

    context "when assigning an enterprise team" do
      test "requires the assigning user to be an admin of the business" do
        assigning_user = create(:user)
        enterprise_team = create(:enterprise_team, business: @business)
        result = Copilot::SeatManagement::Assigner.new(@business).assign(enterprise_team, assigning_user)

        assert_equal "Inviting User is not an admin of the Business", result.error.message
      end

      context "when the enterprise team assignment already exists" do
        test "returns the enterprise team assignment" do
          enterprise_team = create(:enterprise_team, business: @business)
          ent_team_assignment = EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: "copilot")
          events = subscribe("enterprise_team.copilot.assignment")
          result = Copilot::SeatManagement::Assigner.new(@business).assign(enterprise_team, @business_admin)

          assert_equal ent_team_assignment, result.value!

          event = events.pop
          assert_nil event
        end
      end

      context "when the enterprise team assignment does not exist" do
        test "creates a new enterprise team assignment and emits the assignment" do
          enterprise_team = create(:enterprise_team, business: @business)
          events = subscribe("enterprise_team.copilot.assignment")

          assert_changes -> { EnterpriseTeamAssignment.count }, from: 0, to: 1 do
            result = Copilot::SeatManagement::Assigner.new(@business).assign(enterprise_team, @business_admin)

            assert result.ok?
            assert_equal enterprise_team, result.value!.enterprise_team

            event = events.pop
            assert_equal "enterprise_team.copilot.assignment", event.name
            assert_equal({ id: enterprise_team.id }, event.payload)
          end
        end
      end
    end
  end

  context "#unassign" do
    context "when unassigning a user, team, org, or invite" do
      context "when the seat assignment exists" do
        test "unassigns the seat assignment" do
          assignee = create(:user)
          @organization.add_member(assignee)
          user_assignment = create(:copilot_seat_assignment, :user, assignable: assignee, owner: @organization, assigning_user: @organization_admin)
          Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once

          result = Copilot::SeatManagement::Assigner.new(@organization).unassign(assignee, @organization_admin)

          assert result.ok?
          assert user_assignment.reload.pending_cancellation_date
        end
      end

      context "when the assignment does not exist" do
        test "returns an error" do
          assignee = create(:user)
          @organization.add_member(assignee)

          result = Copilot::SeatManagement::Assigner.new(@organization).unassign(assignee, @organization_admin)

          assert_equal "User is not assigned to a seat", result.error.message
        end
      end
    end

    context "when unassigning an enterprise team" do
      context "when the enterprise team assignment exists" do
        test "destroys the enterprise team assignment and emits the unassignment" do
          enterprise_team = create(:enterprise_team, business: @business)
          ent_team_assignment = EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: "copilot")
          events = subscribe("enterprise_team.copilot.unassignment")

          assert_changes -> { EnterpriseTeamAssignment.count }, from: 1, to: 0 do
            result = Copilot::SeatManagement::Assigner.new(@business).unassign(enterprise_team, @business_admin)

            assert result.ok?

            event = events.pop
            assert_equal "enterprise_team.copilot.unassignment", event.name
            assert_equal({ id: enterprise_team.id }, event.payload)
          end
          assert_nil EnterpriseTeamAssignment.find_by(id: ent_team_assignment.id)
        end
      end

      context "when the assignment does not exist" do
        test "returns an error" do
          enterprise_team = create(:enterprise_team, business: @business)

          result = Copilot::SeatManagement::Assigner.new(@business).unassign(enterprise_team, @business_admin)

          assert_equal "EnterpriseTeam is not assigned to a seat", result.error.message
        end
      end
    end
  end

  context "#assign_email_address" do
    test "raises an error if a business tries to assign an email" do
      assignable = create(:user)
      assignable.emails.map(&:verify!)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never

      assigner = Copilot::SeatManagement::Assigner.new(@business)
      result = assigner.assign_email_address(assignable.email, @business_admin)

      assert_equal "Businesses cannot invite users", result.error.message
    end


    test "raises an error if an EMU org tries to assign an email" do
      emu = create(:emu)
      emu_business = emu.enterprise_managed_business
      emu_org = create :enterprise_linked_organization, business: emu_business, admin: emu
      outside_user = create(:user)
      outside_user.emails.map(&:verify!)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never

      assigner = Copilot::SeatManagement::Assigner.new(emu_org)
      result = assigner.assign_email_address(outside_user.email, emu_org.admins.first)

      assert_equal "EMUs must be added to the organization before they can be assigned seats", result.error.message
    end

    test "finds email address for existing user and assigns that invite" do
      assignable = create(:user)
      assignable.emails.map(&:verify!)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once
      Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).never
      Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:set).never

      assigner = Copilot::SeatManagement::Assigner.new(@organization)
      result = assigner.assign_email_address(assignable.email, @organization_admin)

      seat_assignment = result.value!
      assert_equal @organization, seat_assignment.organization

      organization_invitation = seat_assignment.assignable
      assert_equal assignable, organization_invitation.invitee
      assert_equal "member", organization_invitation.invitation_source
    end

    test "creates organization invitation for email address and assigns that" do
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once
      Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).never
      Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:set).never

      email = "email@example.com"
      assigner = Copilot::SeatManagement::Assigner.new(@organization)
      result = assigner.assign_email_address(email, @organization_admin)

      seat_assignment = result.value!
      assert_equal @organization, seat_assignment.organization

      organization_invitation = seat_assignment.assignable
      assert_equal email, organization_invitation.email
      assert_equal "member", organization_invitation.invitation_source
    end

    test "finds email address for existing organization member and assigns that user" do
      assignable = create(:user)
      assignable.emails.map(&:verify!)
      @organization.add_member(assignable)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once
      Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:perform_later).once
      Copilot::SeatManagement::SeatAssignmentConverterJob.expects(:set).with(wait: Copilot::COPILOT_FOR_BUSINESS_SEAT_DELAYS[:USER]).returns(Copilot::SeatManagement::SeatAssignmentConverterJob).once

      assigner = Copilot::SeatManagement::Assigner.new(@organization)
      result = assigner.assign_email_address(assignable.email, @organization_admin)

      seat_assignment = result.value!
      assert_equal @organization, seat_assignment.organization
      assert_equal assignable, seat_assignment.assignable
    end
  end

  context "#unassign_email_address" do
    test "unassigns an organization invitation immediately" do
      organization = create(:organization)
      assigning_user = organization.admins.first
      email = "email@example.com"
      invitation = organization.invite(email: email, inviter: assigning_user)

      seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: invitation)
      assigner = Copilot::SeatManagement::Assigner.new(organization)
      result = assigner.unassign_email_address(email, assigning_user)

      assert result.ok?
      refute Copilot::SeatAssignment.exists?(seat_assignment.id)
    end

    test "gives an error when the email isn't a user or invitation" do
      organization = create(:organization)
      assigning_user = organization.admins.first
      email = "email@example.com"

      assigner = Copilot::SeatManagement::Assigner.new(organization)
      result = assigner.unassign_email_address(email, assigning_user)
      refute result.ok?
      assert result.error
    end

    test "defers unassigning user invited" do
      organization = create(:organization)
      assigning_user = organization.admins.first
      user = create(:user)
      user.emails.map(&:verify!)
      organization.add_member(user)

      create(:copilot_seat_assignment, organization: organization, assignable: user)
      Copilot::SeatAssignment.any_instance.expects(:unassign!).once
      assigner = Copilot::SeatManagement::Assigner.new(organization)
      result = assigner.unassign_email_address(user.email, assigning_user)
      assert result.ok?
    end
  end
end if GitHub.copilot_enabled?
