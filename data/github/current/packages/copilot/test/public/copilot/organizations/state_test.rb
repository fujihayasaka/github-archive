# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::Organizations::StateTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @organization = T.let(create(:copilot_for_business_enabled_organization), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @user = T.let(create(:user), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped

    # For CfB migration stuff
    @enterprise_team = T.let(create(:enterprise_team, business: @organization.business), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @enterprise_team.enterprise_team_assignments.create!(assignment_type: :copilot)
    @enterprise_team_seat_assignment = T.let(Copilot::SeatAssignment.create_for_enterprise_team!(@enterprise_team), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
  end

  setup do
    @copilot_organization = T.let(Copilot::Organization.new(@organization), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @configuration = T.let(Copilot::Configuration.find_by(configurable_id: @organization.id, configurable_type: "Organization"), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
  end

  context "#seat_management_disable!" do
    context "coming from allow all" do
      test "has an existing organization seat assignment that gets updated" do
        seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @organization, assigning_user: @organization.admins.first)
        assert_nil seat_assignment.pending_cancellation_date

        assert @copilot_organization.organization_seat_assignment.present?

        logs = capture_logs do
          @copilot_organization.seat_management_disable!
        end

        assert_match "seat_management_disable!", logs
        assert_match "Existing Organization SeatAssignment Found", logs
        assert_match "Deleting any other SeatAssignments", logs
        seat_assignment.reload
        refute_nil seat_assignment.pending_cancellation_date
      end

      test "has an existing organization seat assignment with seats" do
        @organization.add_member(create(:user))
        @organization.add_member(@user)
        seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @organization, assigning_user: @organization.admins.first)
        seat_assignment.convert_to_seats
        assert_nil seat_assignment.pending_cancellation_date

        # let's mess up one of the seats (this shouldn't ever happen)
        seat = Copilot::Seat.where(organization: @organization, assigned_user: @user).first!
        seat.update_column(:copilot_seat_assignment_id, 1234589)
        refute seat_assignment.seats.include?(seat)

        assert @copilot_organization.organization_seat_assignment.present?

        @copilot_organization.seat_management_disable!
        seat_assignment.reload
        refute_nil seat_assignment.pending_cancellation_date
        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end
        seat.reload
        assert_equal seat.copilot_seat_assignment_id, seat_assignment.id
      end
    end

    context "coming from selected team/users" do
      test "created seat assignment gets proper assigning_user" do
        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

        other_admin = create(:user)
        @organization.add_admin(other_admin)

        @copilot_organization.seat_management_disable!(other_admin)

        seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))

        assert_equal other_admin, seat_assignment.assigning_user
      end

      test "has existing teams and users assigned" do
        @organization.add_member(@user)
        user_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @user, assigning_user: @organization.admins.first)
        user_seat_assignment.convert_to_seats

        assert_nil user_seat_assignment.pending_cancellation_date

        team = create(:team, organization: @organization)
        team.add_member(create(:user))
        team_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: team, assigning_user: @organization.admins.first)
        team_seat_assignment.convert_to_seats

        assert_nil team_seat_assignment.pending_cancellation_date

        logs = capture_logs do
          @copilot_organization.seat_management_disable!
        end

        assert_match "seat_management_disable!", logs
        assert_match "Creating Organization SeatAssignment", logs
        assert_match "Updating existing Seats to point to Org SeatAssignment", logs
        assert_match "Deleting any other SeatAssignments", logs

        refute Copilot::SeatAssignment.where(id: user_seat_assignment.id).exists?
        refute Copilot::SeatAssignment.where(id: team_seat_assignment.id).exists?

        organization_seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal organization_seat_assignment.id, seat.copilot_seat_assignment_id
        end
      end

      test "does not remove users and teams when all are pending cancellation" do
        @organization.add_member(@user)
        user_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @user, assigning_user: @organization.admins.first)
        user_seat_assignment.convert_to_seats
        @copilot_organization.unassign([@user], @organization.admins.first)
        user_seat_assignment.reload

        refute_nil user_seat_assignment.pending_cancellation_date

        team = create(:team, organization: @organization)
        team.add_member(create(:user))
        team_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: team, assigning_user: @organization.admins.first)
        team_seat_assignment.convert_to_seats
        @copilot_organization.unassign([team], @organization.admins.first)
        team_seat_assignment.reload

        refute_nil team_seat_assignment.pending_cancellation_date

        @copilot_organization.seat_management_disable!

        assert Copilot::SeatAssignment.where(id: user_seat_assignment.id).exists?
        assert Copilot::SeatAssignment.where(id: team_seat_assignment.id).exists?
      end

      test "has existing disabled organization assigned" do
        @organization.add_member(@user)

        seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @organization, assigning_user: @organization.admins.first)
        assert_nil seat_assignment.pending_cancellation_date
        seat_assignment.update_column(:pending_cancellation_date, @copilot_organization.pending_cancellation_date)

        other_user = create(:user)
        @organization.add_member(other_user)
        user_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: other_user, assigning_user: @organization.admins.first)
        user_seat_assignment.convert_to_seats

        logs = capture_logs do
          @copilot_organization.seat_management_disable!
        end

        assert_match "seat_management_disable!", logs
        assert_match "Existing Organization SeatAssignment Found", logs

        seat_assignment.reload

        refute_nil seat_assignment.pending_cancellation_date

        refute Copilot::SeatAssignment.where(id: user_seat_assignment.id).exists?

        organization_seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal organization_seat_assignment.id, seat.copilot_seat_assignment_id
        end
      end

      test "wont override seats that have already been cancelled" do
        user2 = create(:user)

        @organization.add_member(@user)
        @organization.add_member(user2)

        user_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @user, assigning_user: @organization.admins.first)
        user_seat_assignment.convert_to_seats
        user_seat_assignment.reload

        user2_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: user2, assigning_user: @organization.admins.first)
        user2_seat_assignment.convert_to_seats
        user2_seat_assignment.reload

        user2_seat_assignment.update_column(:pending_cancellation_date, Date.today)

        user2_seat = user2_seat_assignment.seats.first

        @copilot_organization.seat_management_disable!

        # The first seat assignment should have been removed as it's now pointing at an org-level seat assignment
        refute Copilot::SeatAssignment.where(id: user_seat_assignment.id).exists?
        # The second seat assignment should not have been removed as it's already pending cancellation
        assert Copilot::SeatAssignment.where(id: user2_seat_assignment.id).exists?
        # Make sure that the cancelled Seat is still pointing at the correct SeatAssignment
        user2_seat.reload
        assert_equal user2_seat_assignment.id, user2_seat.copilot_seat_assignment_id
      end
    end
  end

  context "#seat_management_allow_all!" do
    test "created seat assignment gets proper assigning_user" do
      refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

      other_admin = create(:user)
      @organization.add_admin(other_admin)

      @copilot_organization.seat_management_allow_all!(other_admin)

      seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))

      assert_equal other_admin, seat_assignment.assigning_user
    end

    context "coming from disabled" do
      test "starting for the first time" do
        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

        @copilot_organization.seat_management_allow_all!

        seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))
        seat_assignment.convert_to_seats

        assert_nil seat_assignment.pending_cancellation_date
        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count
      end

      context "disabled -> allow_all -> disabled -> allow_all" do
        test "gets everything" do
          refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

          @copilot_organization.seat_management_allow_all!

          seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))
          seat_assignment.convert_to_seats

          assert_nil seat_assignment.pending_cancellation_date
          Copilot::Seat.where(organization: @organization).each do |seat|
            assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
          end
          assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count

          @copilot_organization.seat_management_disable!

          assert Copilot::SeatAssignment.organization_seat_assignment(@organization)
          refute_nil T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization)).pending_cancellation_date
        end
      end

      test "has an existing pending organization seat assignment that gets updated" do
        @configuration.seat_management_disabled!
        seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @organization, assigning_user: @organization.admins.first)
        seat_assignment.convert_to_seats
        seat_assignment.update_column(:pending_cancellation_date, @organization.next_metered_billing_cycle_starts_at)
        refute_nil seat_assignment.pending_cancellation_date

        assert @copilot_organization.seat_management_disabled?
        assert @copilot_organization.organization_seat_assignment.present?

        newly_added_user = create(:user)
        @organization.add_member(newly_added_user)

        capture_logs do
          @copilot_organization.seat_management_allow_all!
          seat_assignment.reload
          seat_assignment.convert_to_seats
          assert_nil seat_assignment.pending_cancellation_date
          assert Copilot::Seat.where(organization: @organization, assigned_user: newly_added_user).exists?

          Copilot::Seat.where(organization: @organization).each do |seat|
            assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
          end

          assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count
        end
      end
    end

    context "coming from selected team/users" do
      test "it clears all of the seat assignments and assigns all users" do
        # let's add an unassigned user
        @organization.add_member(create(:user))
        team = create(:team, organization: @organization)
        user = create(:user)
        team.add_member(user)
        team_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: team, assigning_user: @organization.admins.first)
        team_seat_assignment.convert_to_seats

        user = create(:user)
        @organization.add_member(user)
        user_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: user, assigning_user: @organization.admins.first)
        user_seat_assignment.convert_to_seats

        user = create(:user)
        invitation = @organization.invite(user, inviter: @organization.admin)
        invitation_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: invitation, assigning_user: @organization.admins.first)

        assert_equal 3, Copilot::SeatAssignment.where(organization: @organization).count
        assert_equal 2, Copilot::Seat.where(organization: @organization).count
        @copilot_organization.seat_management_allow_all!

        refute Copilot::SeatAssignment.where(id: user_seat_assignment.id).exists?
        refute Copilot::SeatAssignment.where(id: team_seat_assignment.id).exists?
        refute Copilot::SeatAssignment.where(id: invitation_seat_assignment.id).exists?

        org_assignment = Copilot::SeatAssignment.organization_seat_assignment(@organization)
        assert org_assignment.present?
        T.must(org_assignment).convert_to_seats

        # the random user above should get a seat too.
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal T.must(org_assignment).id, seat.copilot_seat_assignment_id
        end
      end
    end
  end

  context "#seat_management_selected_teams_and_users!" do
    context "coming from disabled" do
      test "brand new user" do
        # not much to do here
        @configuration.seat_management_disabled!

        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)
        assert @copilot_organization.seat_management_disabled?

        @copilot_organization.seat_management_selected_teams_and_users!

        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)
        assert_equal 0, Copilot::Seat.where(organization: @organization).count
        assert_equal 0, Copilot::SeatAssignment.where(organization: @organization).count
      end

      test "existing user with a pending seat assignment" do
        @configuration.seat_management_disabled!
        @organization.add_member(@user)

        seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @user, assigning_user: @organization.admins.first)
        seat_assignment.convert_to_seats

        assert_equal 1, Copilot::Seat.where(organization: @organization).count
        assert_equal 1, Copilot::SeatAssignment.where(organization: @organization).count

        @copilot_organization.seat_management_disable! # test against the method here too

        refute Copilot::SeatAssignment.where(id: seat_assignment.id).exists?
        org_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))

        refute_nil org_assignment
        refute_nil org_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat.copilot_seat_assignment_id, org_assignment.id
        end

        @copilot_organization.seat_management_selected_teams_and_users!

        org_assignment.reload
        refute_nil org_assignment.pending_cancellation_date # still pending cancellation

        assert_equal 1, Copilot::Seat.where(organization: @organization).count
        assert_equal Copilot::Seat.where(organization: @organization).first!.copilot_seat_assignment_id, org_assignment.id
        assert_equal 1, Copilot::SeatAssignment.where(organization: @organization).count

        # let's recreate that user seat assignment and see what happens
        seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @user, assigning_user: @organization.admins.first)
        seat_assignment.convert_to_seats

        # org assignment should be deleted
        refute Copilot::SeatAssignment.where(id: org_assignment.id).exists?

        assert_equal 1, Copilot::Seat.where(organization: @organization).count
        assert_equal Copilot::Seat.where(organization: @organization).first!.copilot_seat_assignment_id, seat_assignment.id
        assert_equal 1, Copilot::SeatAssignment.where(organization: @organization).count
      end
    end

    context "coming from allow all" do
      context "keep assignments" do
        context "organization job has run to create seats" do
          test "it keeps the existing seats" do
            @configuration.seat_management_enabled_for_all!
            @organization.add_member(@user)

            organization_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @organization, assigning_user: @organization.admins.first)
            organization_seat_assignment.convert_to_seats # this is all the job does

            assert_equal 2, Copilot::Seat.where(organization: @organization).count
            assert_equal 1, Copilot::SeatAssignment.where(organization: @organization).count
            assert @copilot_organization.organization_seat_assignment.present?

            assert @copilot_organization.seat_management_enabled_for_all?

            @copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: true)

            # it should delete the organization seat assignment because we've reassigned to user seat assignments
            refute @copilot_organization.organization_seat_assignment

            # # good bye to organization seat assignment, hello user seat assignments
            assert_equal 2, Copilot::SeatAssignment.where(organization: @organization).count
            assert_equal 2, Copilot::Seat.where(organization: @organization).count

            # # all of the seats should be updated to point to new user seat assignments
            Copilot::Seat.where(organization: @organization).each do |seat|
              assignment = Copilot::SeatAssignment.find_by(assignable_id: seat.assigned_user_id, assignable_type: "User")
              assert_equal seat.copilot_seat_assignment_id, T.must(assignment).id
              assert_equal @organization.id, T.must(assignment).owner_id
              assert_equal "Organization", T.must(assignment).owner_type
            end
          end
        end

        context "just the assignment for the org, no seats" do
          test "no seats created" do
            @configuration.seat_management_enabled_for_all!
            @organization.add_member(@user)

            create(:copilot_seat_assignment, organization: @organization, assignable: @organization, assigning_user: @organization.admins.first)

            # no seats created from org assignment
            assert_equal 0, Copilot::Seat.where(organization: @organization).count
            assert_equal 1, Copilot::SeatAssignment.where(organization: @organization).count

            assert @copilot_organization.organization_seat_assignment.present?

            # even though we haven't run yet, we still are in allow all mode
            assert @copilot_organization.seat_management_enabled_for_all?

            @copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: true)

            # it should delete the organization seat assignment
            refute @copilot_organization.organization_seat_assignment

            assert_equal 2, Copilot::SeatAssignment.where(organization: @organization).count
            assert_equal 2, Copilot::Seat.where(organization: @organization).count
          end
        end
      end

      context "start from scratch" do
        context "organization job has run to create seats" do
          test "it keeps the existing seats" do
            @organization.add_member(@user)

            organization_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @organization, assigning_user: @organization.admins.first)
            organization_seat_assignment.convert_to_seats # this is all the job does

            assert_equal 2, Copilot::Seat.where(organization: @organization).count
            assert_equal 1, Copilot::SeatAssignment.where(organization: @organization).count
            assert @copilot_organization.organization_seat_assignment.present?

            @copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: false)

            # organization seat assignment should be pending cancellation
            org_assignment = @copilot_organization.organization_seat_assignment
            assert org_assignment.pending_cancellation_date

            assert_equal 1, Copilot::SeatAssignment.where(organization: @organization).count
            assert_equal 2, Copilot::Seat.where(organization: @organization).count

            # all of the seats should still be pointing to the org seat assignment
            refute Copilot::Seat.where(organization: @organization).where.not(copilot_seat_assignment_id: org_assignment.id).exists?

            # let's create a new user seat assignment
            user_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @user, assigning_user: @organization.admins.first)
            user_seat_assignment.convert_to_seats

            # org assignment should not be deleted because other seat exists
            org_assignment.reload
            assert org_assignment.pending_cancellation_date
            assert Copilot::Seat.where(organization: @organization, copilot_seat_assignment_id: user_seat_assignment.id).exists?

            # create a user seat assignment for the org admin
            org_admin_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @organization.admins.first, assigning_user: @organization.admins.first)
            org_admin_assignment.convert_to_seats

            # org assignment should be deleted because no other seats exist
            refute Copilot::SeatAssignment.where(id: org_assignment.id).exists?

            assert_equal 2, Copilot::SeatAssignment.where(organization: @organization).count
            assert_equal 2, Copilot::Seat.where(organization: @organization).count
          end
        end

        context "just the assignment for the org, no seats" do
          test "no seats created" do
            @configuration.seat_management_enabled_for_all!
            @organization.add_member(@user)

            create(:copilot_seat_assignment, organization: @organization, assignable: @organization, assigning_user: @organization.admins.first)

            # no seats created from org assignment
            assert_equal 0, Copilot::Seat.where(organization: @organization).count
            assert_equal 1, Copilot::SeatAssignment.where(organization: @organization).count

            assert @copilot_organization.organization_seat_assignment.present?

            # even though we haven't run yet, we still are in allow all mode
            assert @copilot_organization.seat_management_enabled_for_all?

            @copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: false)

            # organization seat assignment should be pending cancellation
            org_assignment = @copilot_organization.organization_seat_assignment
            assert org_assignment.pending_cancellation_date

            assert_equal 1, Copilot::SeatAssignment.where(organization: @organization).count
            assert_equal 0, Copilot::Seat.where(organization: @organization).count

            # let's create a new team seat assignment
            team = create(:team, organization: @organization)
            team_user = create(:user)
            team.add_member(team_user)
            team_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: team, assigning_user: @organization.admins.first)
            team_seat_assignment.convert_to_seats

            assert_equal 2, Copilot::SeatAssignment.where(organization: @organization).count
            assert_equal 1, Copilot::Seat.where(organization: @organization).count
          end
        end
      end

      test "starting from scratch when enabled for selected > enabled for all > enabled for selected" do
        original_constant = Copilot::COPILOT_FOR_BUSINESS_SEAT_DELAYS
        Copilot.send(:remove_const, :COPILOT_FOR_BUSINESS_SEAT_DELAYS)
        Copilot.const_set(:COPILOT_FOR_BUSINESS_SEAT_DELAYS, { ORGANIZATION: 30.minutes })

        first_user = create(:user)
        second_user = create(:user)

        @organization.add_member(first_user)
        @organization.add_member(second_user)

        Timecop.freeze do
          @configuration.seat_management_enabled_for_selected!
          @copilot_organization.seat_management_allow_all!
          @copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: false)

          perform_enqueued_jobs(only: [Copilot::SeatManagement::SeatAssignmentConverterJob]) do
            Timecop.travel(30.minutes.from_now)
          end

          seat_assignments = Copilot::SeatAssignment.for_organization(@organization)

          refute_equal(seat_assignments.count, @organization.members.count)
          assert_equal(seat_assignments.count, 1)
          assert_equal(seat_assignments.first!.assignable_type, "Organization")
        ensure
          Copilot.send(:remove_const, :COPILOT_FOR_BUSINESS_SEAT_DELAYS)
          Copilot.const_set(:COPILOT_FOR_BUSINESS_SEAT_DELAYS, original_constant)
        end
      end
    end

    # We might hit this case if there's a race condition between two admins updating settings, or if we run a db
    # transition that creates seats and an admin is updating their settings at the exact wrong time
    test "we somehow manage to do selected -> selected, which should never happen" do
      @organization.add_member(@user)

      user_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @user, assigning_user: @organization.admins.first)
      user_seat_assignment.convert_to_seats
      user_seat_assignment.unassign!(@organization.admins.first)
      seat = Copilot::Seat.where(organization: @organization, copilot_seat_assignment_id: user_seat_assignment.id).first!

      refute @copilot_organization.organization_seat_assignment.present?
      # so we shouldn't ever call this, but let's see what happens

      logs = capture_logs do
        @copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: false)
      end
      assert_match "Found unmanaged seats for organization", logs
      assert_match "Creating new Organization SeatAssignment", logs

      seat.reload
      assert @copilot_organization.organization_seat_assignment.present?
      assert @copilot_organization.organization_seat_assignment.pending_cancellation_date
      assert_equal seat.seat_assignment&.id, @copilot_organization.organization_seat_assignment.id
      refute Copilot::SeatAssignment.where(id: user_seat_assignment.id).exists?
    end
  end

  context "various combinations" do
    context "Original State (disabled) -> Allow All -> Disabled" do
      test "changes between things reliably" do
        # original state
        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

        # allow all
        @copilot_organization.seat_management_allow_all!

        assert @copilot_organization.seat_management_enabled_for_all?

        seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))
        seat_assignment.convert_to_seats

        assert_nil seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count

        # disable
        @copilot_organization.seat_management_disable!

        assert @copilot_organization.seat_management_disabled?

        seat_assignment.reload

        refute_nil seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count
      end
    end

    context "Original State (disabled) -> Allow All -> Selected (Keep All)" do
      test "changes between things reliably" do
        # original state
        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

        # allow all
        @copilot_organization.seat_management_allow_all!

        assert @copilot_organization.seat_management_enabled_for_all?

        seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))
        seat_assignment.convert_to_seats

        assert_nil seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count

        # selected (keep them all)
        @copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: true)

        assert @copilot_organization.seat_management_enabled_for_selected?

        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

        Copilot::Seat.where(organization: @organization).each do |seat|
          user_seat_assignment = Copilot::SeatAssignment.where(organization: @organization, assignable: seat.assigned_user).first
          assert_equal user_seat_assignment&.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count
      end
    end

    context "Original State (disabled) -> Allow All -> Selected (Start From Scratch)" do
      test "changes between things reliably" do
        # original state
        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

        # allow all
        @copilot_organization.seat_management_allow_all!

        assert @copilot_organization.seat_management_enabled_for_all?

        seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))
        seat_assignment.convert_to_seats

        assert_nil seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count

        # Selected (Start From Scratch)
        @copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: false)

        assert @copilot_organization.seat_management_enabled_for_selected?

        seat_assignment.reload

        refute_nil seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count
      end
    end

    context "Original State (disabled) -> Selected -> Allow All" do
      test "changes between things reliably" do
        # original state
        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

        # selected
        @copilot_organization.seat_management_selected_teams_and_users!

        user_seat_assignment = create(:copilot_seat_assignment, :user, organization: @organization, assignable: @organization.members.first, assigning_user: @organization.admins.first)
        user_seat_assignment.convert_to_seats

        assert_nil user_seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal user_seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count

        # allow all
        @copilot_organization.seat_management_allow_all!

        refute Copilot::SeatAssignment.find_by(id: user_seat_assignment.id)

        seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))
        seat_assignment.convert_to_seats
        seat_assignment.reload

        assert_nil seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count
      end
    end

    context "Original State (disabled) -> Selected -> Disabled" do
      test "changes between things reliably" do
        # original state
        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

        # selected
        @copilot_organization.seat_management_selected_teams_and_users!

        user_seat_assignment = create(:copilot_seat_assignment, :user, organization: @organization, assignable: @organization.members.first, assigning_user: @organization.admins.first)
        user_seat_assignment.convert_to_seats

        assert_nil user_seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal user_seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count

        # disabled
        @copilot_organization.seat_management_disable!

        refute Copilot::SeatAssignment.find_by(id: user_seat_assignment.id)

        seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))
        refute_nil seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count
      end
    end

    context "Original State (disabled) -> Selected -> Disabled -> Allow All" do
      test "changes between things reliably" do
        # original state
        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

        # selected
        @copilot_organization.seat_management_selected_teams_and_users!

        user_seat_assignment = create(:copilot_seat_assignment, :user, organization: @organization, assignable: @organization.members.first, assigning_user: @organization.admins.first)
        user_seat_assignment.convert_to_seats

        assert_nil user_seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal user_seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count

        # disabled
        @copilot_organization.seat_management_disable!

        refute Copilot::SeatAssignment.find_by(id: user_seat_assignment.id)

        seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))
        refute_nil seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count

        # allow all
        @copilot_organization.seat_management_allow_all!

        refute Copilot::SeatAssignment.find_by(id: user_seat_assignment.id)

        seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))
        assert_nil seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end
        assert_equal @organization.members.count, Copilot::Seat.where(organization: @organization).count
      end
    end

    context "Original State (disabled) -> Selected w/Seat -> Disabled -> Selected (Keep All)" do
      test "changes between things reliably" do
        # original state
        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

        # selected
        @copilot_organization.seat_management_selected_teams_and_users!

        user_seat_assignment = create(:copilot_seat_assignment, :user, organization: @organization, assignable: @organization.members.first, assigning_user: @organization.admins.first)
        user_seat_assignment.convert_to_seats

        assert_nil user_seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal user_seat_assignment.id, seat.copilot_seat_assignment_id
        end

        # disabled
        @copilot_organization.seat_management_disable!

        refute Copilot::SeatAssignment.find_by(id: user_seat_assignment.id)

        seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))
        refute_nil seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end

        # selected (keep all)
        @copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: true)

        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

        Copilot::Seat.where(organization: @organization).each do |seat|
          user_seat_assignment = Copilot::SeatAssignment.where(organization: @organization, assignable: seat.assigned_user).first
          assert_equal user_seat_assignment&.id, seat.copilot_seat_assignment_id
        end
      end
    end

    context "Original State (disabled) -> Selected w/Seat -> Disabled -> Selected (Start From Scratch)" do
      test "changes between things reliably" do
        # original state
        refute Copilot::SeatAssignment.organization_seat_assignment(@organization)

        # selected
        @copilot_organization.seat_management_selected_teams_and_users!

        user_seat_assignment = create(:copilot_seat_assignment, :user, organization: @organization, assignable: @organization.members.first, assigning_user: @organization.admins.first)
        user_seat_assignment.convert_to_seats

        assert_nil user_seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal user_seat_assignment.id, seat.copilot_seat_assignment_id
        end

        # disabled
        @copilot_organization.seat_management_disable!

        refute Copilot::SeatAssignment.find_by(id: user_seat_assignment.id)
        seat_assignment = T.must(Copilot::SeatAssignment.organization_seat_assignment(@organization))
        refute_nil seat_assignment.pending_cancellation_date

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end

        # selected (start from scratch)
        @copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: false)

        assert Copilot::SeatAssignment.organization_seat_assignment(@organization)
        seat_assignment.reload

        Copilot::Seat.where(organization: @organization).each do |seat|
          assert_equal seat_assignment.id, seat.copilot_seat_assignment_id
        end
      end
    end
  end

  context "seat_management_disabled?" do
    test "is true when the configuration is disabled" do
      @configuration.seat_management_disabled!

      assert @copilot_organization.seat_management_disabled?
    end

    test "is true when the configuration is unconfigured" do
      @configuration.seat_management_unconfigured!

      assert @copilot_organization.seat_management_disabled?
    end

    test "is false when the configuration is enabled for all" do
      @configuration.seat_management_enabled_for_all!

      refute @copilot_organization.seat_management_disabled?
    end

    test "is false when the configuration is enabled for selected" do
      @configuration.seat_management_enabled_for_selected!

      refute @copilot_organization.seat_management_disabled?
    end
  end

  context "seat_management_enabled_for_all?" do
    test "is true when the configuration is enabled for all" do
      @configuration.seat_management_enabled_for_all!

      assert @copilot_organization.seat_management_enabled_for_all?
    end

    test "is false when the configuration is unconfigured" do
      @configuration.seat_management_unconfigured!

      refute @copilot_organization.seat_management_enabled_for_all?
    end

    test "is false when the configuration is disabled" do
      @configuration.seat_management_disabled!

      refute @copilot_organization.seat_management_enabled_for_all?
    end

    test "is false when the configuration is enabled for selected" do
      @configuration.seat_management_enabled_for_selected!

      refute @copilot_organization.seat_management_enabled_for_all?
    end
  end

  context "seat_management_enabled_for_selected?" do
    test "is true when the configuration is enabled for selected" do
      @configuration.seat_management_enabled_for_selected!

      assert @copilot_organization.seat_management_enabled_for_selected?
    end

    test "is false when the configuration is unconfigured" do
      @configuration.seat_management_unconfigured!

      refute @copilot_organization.seat_management_enabled_for_selected?
    end

    test "is false when the configuration is disabled" do
      @configuration.seat_management_disabled!

      refute @copilot_organization.seat_management_enabled_for_selected?
    end

    test "is false when the configuration is enabled for all" do
      @configuration.seat_management_enabled_for_all!

      refute @copilot_organization.seat_management_enabled_for_selected?
    end
  end

  context "seat_management_setting" do
    test "is disabled when the configuration is unconfigured" do
      @configuration.seat_management_unconfigured!

      assert_equal @copilot_organization.seat_management_setting, "disabled"
    end

    test "is disabled when the configuration is disabled" do
      @configuration.seat_management_disabled!

      assert_equal @copilot_organization.seat_management_setting, "disabled"
    end

    test "is enabled_for_all when the configuration is enabled for all" do
      @configuration.seat_management_enabled_for_all!

      assert_equal @copilot_organization.seat_management_setting, "enabled_for_all"
    end

    test "is enabled_for_selected when the configuration is enabled for selected" do
      @configuration.seat_management_enabled_for_selected!

      assert_equal @copilot_organization.seat_management_setting, "enabled_for_selected"
    end
  end

  context "friendly_seat_management_setting" do
    test "is disabled when the configuration is unconfigured" do
      @configuration.seat_management_unconfigured!

      assert_equal "Unconfigured", @copilot_organization.friendly_seat_management_setting
    end

    test "is disabled when the configuration is disabled" do
      @configuration.seat_management_disabled!

      assert_equal "Disabled", @copilot_organization.friendly_seat_management_setting
    end

    test "is enabled_for_all when the configuration is enabled for all" do
      @configuration.seat_management_enabled_for_all!

      assert_equal "Enabled for All", @copilot_organization.friendly_seat_management_setting
    end

    test "is enabled_for_selected when the configuration is enabled for selected" do
      @configuration.seat_management_enabled_for_selected!

      assert_equal "Enabled for Selected Users/Teams", @copilot_organization.friendly_seat_management_setting
    end
  end

  context "#migrate_to_enterprise_teams" do
    test "works when seat_management_enabled_for_all" do
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(@organization.business)
      @configuration.seat_management_enabled_for_all!
      @organization.add_member(@user)

      seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @organization, assigning_user: @organization.admins.first)
      seat_assignment.convert_to_seats

      events = subscribe("enterprise_team.copilot.update")

      assert_difference -> { EnterpriseTeam.count }, 1 do
        @copilot_organization.migrate_to_enterprise_teams
      end

      enterprise_team = EnterpriseTeam.last!
      assert_equal @organization.members.length, enterprise_team.member_user_ids.length
      assert (@organization.members.pluck(:id) - enterprise_team.member_user_ids).empty?

      new_seat_assignments = Copilot::SeatAssignment.where(assignable: enterprise_team)
      assert_equal 1, new_seat_assignments.length
      assert_equal 2, new_seat_assignments.first!.seats.length
      assert_equal 0, new_seat_assignments.first!.seats.where.not(organization_id: nil).length
      refute Copilot::SeatAssignment.find_by(organization: @organization)

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal({ id: enterprise_team.id }, event.payload)
      assert Copilot::Business.new(@organization.business).copilot_enabled?
    end

    test "works when seat_management_enabled_for_selected user" do
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(@organization.business)
      @configuration.seat_management_enabled_for_selected!
      @organization.add_member(@user)

      user_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @user, assigning_user: @organization.admins.first)
      user_seat_assignment.convert_to_seats

      events = subscribe("enterprise_team.copilot.update")
      assert_difference -> { EnterpriseTeam.count }, 1 do
        @copilot_organization.migrate_to_enterprise_teams
      end

      enterprise_team = EnterpriseTeam.last!
      assert_equal 1, enterprise_team.member_user_ids.length  # Expect just @user, excludes the org admin
      assert_equal @user.id, enterprise_team.member_user_ids.first

      new_seat_assignments = Copilot::SeatAssignment.where(assignable: enterprise_team)
      assert_equal 1, new_seat_assignments.length
      assert_equal 1, new_seat_assignments.first!.seats.length
      refute Copilot::SeatAssignment.find_by(organization: @organization)

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal({ id: enterprise_team.id }, event.payload)
      assert Copilot::Business.new(@organization.business).copilot_enabled?
    end

    test "works when seat_management_enabled_for_selected team" do
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(@organization.business)
      @configuration.seat_management_enabled_for_selected!
      @organization.add_member(@user)

      team = create(:team, organization: @organization)
      team.add_member(@user)
      team_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: team, assigning_user: @organization.admins.first)
      team_seat_assignment.convert_to_seats

      events = subscribe("enterprise_team.copilot.update")
      assert_difference -> { EnterpriseTeam.count }, 1 do
        @copilot_organization.migrate_to_enterprise_teams
      end

      enterprise_team = EnterpriseTeam.last!
      assert_equal 1, enterprise_team.member_user_ids.length  # Expect just @user, excludes the org admin
      assert_equal @user.id, enterprise_team.member_user_ids.first

      new_seat_assignments = Copilot::SeatAssignment.where(assignable: enterprise_team)
      assert_equal 1, new_seat_assignments.length
      assert_equal 1, new_seat_assignments.first!.seats.length
      refute Copilot::SeatAssignment.find_by(organization: @organization)

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal({ id: enterprise_team.id }, event.payload)
      assert Copilot::Business.new(@organization.business).copilot_enabled?
    end

    test "works when seat_management_enabled_for_selected team with external_group_mapping" do
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(@organization.business)
      @configuration.seat_management_enabled_for_selected!
      @organization.add_member(@user)

      team = create(:team, organization: @organization)
      external_group_with_members = create(:external_group, :with_members, business: @organization.business, number_of_members: 1)
      external_group_team = ExternalGroupTeam.create(external_group: external_group_with_members, team: team)
      external_group_team.add_member(@user)

      team_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: team, assigning_user: @organization.admins.first)
      team_seat_assignment.convert_to_seats

      events = subscribe("enterprise_team.copilot.update")
      assert_difference -> { EnterpriseTeam.count }, 1 do
        @copilot_organization.migrate_to_enterprise_teams
      end

      enterprise_team = EnterpriseTeam.last!
      enterprise_team_group_mapping = EnterpriseTeamGroupMapping.where(enterprise_team_id: enterprise_team.id).first!
      assert_equal enterprise_team_group_mapping.external_group_id, external_group_with_members.id
      assert_equal 1, enterprise_team.member_user_ids.length  # Expect just @user, excludes the org admin

      new_seat_assignments = Copilot::SeatAssignment.where(assignable: enterprise_team)
      assert_equal 1, new_seat_assignments.length
      assert_equal 1, new_seat_assignments.first!.seats.length
      refute Copilot::SeatAssignment.find_by(organization: @organization)

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal({ id: enterprise_team.id }, event.payload)
      assert Copilot::Business.new(@organization.business).copilot_enabled?
    end if TestEnv.test_with_all_emus?

    test "works when seat_management_enabled_for_selected team and user mix" do
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(@organization.business)
      @configuration.seat_management_enabled_for_selected!
      @organization.add_member(@user)
      user = create(:user)
      @organization.add_member(user)

      user_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @user, assigning_user: @organization.admins.first)
      user_seat_assignment.convert_to_seats

      team = create(:team, organization: @organization)
      team.add_member(user)
      team_seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: team, assigning_user: @organization.admins.first)
      team_seat_assignment.convert_to_seats

      events = subscribe("enterprise_team.copilot.update")
      assert_difference -> { EnterpriseTeam.count }, 2 do
        @copilot_organization.migrate_to_enterprise_teams
      end

      team_specific_enterprise_team = EnterpriseTeam.find_by!(name: "#{@organization.login}-#{team.slug}-#{EnterpriseTeam::COPILOT_TEAM_SUFFIX}")
      catchall_user_enterprise_team = EnterpriseTeam.find_by!(name: "#{@organization.login}-#{EnterpriseTeam::COPILOT_TEAM_SUFFIX}")

      assert_equal 1, team_specific_enterprise_team.member_user_ids.length # only user was added to the team
      assert_includes team_specific_enterprise_team.member_user_ids, user.id

      assert_equal 1, catchall_user_enterprise_team.member_user_ids.length # only @user has an individual assignment
      assert_includes catchall_user_enterprise_team.member_user_ids, @user.id

      team_specific_seat_assignment = Copilot::SeatAssignment.where(assignable: team_specific_enterprise_team)
      catchall_seat_assignment = Copilot::SeatAssignment.where(assignable: catchall_user_enterprise_team)
      assert_equal 1, team_specific_seat_assignment.length
      assert_equal 1, catchall_seat_assignment.length
      assert_equal 1, team_specific_seat_assignment.first!.seats.length
      assert_equal 1, catchall_seat_assignment.first!.seats.length
      refute Copilot::SeatAssignment.find_by(organization: @organization)

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal({ id: catchall_user_enterprise_team.id }, event.payload)

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal({ id: team_specific_enterprise_team.id }, event.payload)

      assert Copilot::Business.new(@organization.business).copilot_enabled?
    end

    test "does nothing when the enterprise is not a beta participant" do
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].disable(@organization.business)
      @configuration.seat_management_enabled_for_all!

      seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @organization, assigning_user: @organization.admins.first)
      seat_assignment.convert_to_seats

      events = subscribe("enterprise_team.copilot.update")
      assert_no_difference -> { EnterpriseTeam.count } do
        @copilot_organization.migrate_to_enterprise_teams
      end

      assert_equal 1, T.must(Copilot::SeatAssignment.find_by(organization: @organization)).seats.length
      assert_nil events.pop
    end

    test "does nothing when the organization seat management is not configured" do
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(@organization.business)

      seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @organization, assigning_user: @organization.admins.first)
      seat_assignment.convert_to_seats

      events = subscribe("enterprise_team.copilot.update")
      assert_no_difference -> { EnterpriseTeam.count } do
        @copilot_organization.migrate_to_enterprise_teams
      end

      assert_equal 1, T.must(Copilot::SeatAssignment.find_by(organization: @organization)).seats.length
      assert_nil events.pop
    end

    test "does nothing when the organization seat management is disabled" do
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(@organization.business)
      @configuration.seat_management_disabled!

      seat_assignment = create(:copilot_seat_assignment, organization: @organization, assignable: @organization, assigning_user: @organization.admins.first)
      seat_assignment.convert_to_seats

      events = subscribe("enterprise_team.copilot.update")
      assert_no_difference -> { EnterpriseTeam.count } do
        @copilot_organization.migrate_to_enterprise_teams
      end

      assert_equal 1, T.must(Copilot::SeatAssignment.find_by(organization: @organization)).seats.length
      assert_nil events.pop
    end

    test "ignores OrganizationInvites for since basic emus don't use invitations" do
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(@organization.business)
      @configuration.seat_management_enabled_for_selected!

      user = create :user
      invitation = @organization.invite(user, inviter: @organization.admin)
      create(:copilot_seat_assignment, organization: @organization, assignable: invitation, assigning_user: @organization.admins.first)

      events = subscribe("enterprise_team.copilot.update")
      assert_no_difference -> { EnterpriseTeam.count } do
        @copilot_organization.migrate_to_enterprise_teams
      end

      refute Copilot::SeatAssignment.find_by(organization: @organization)
      assert_nil events.pop
    end
  end
end if GitHub.copilot_enabled?
