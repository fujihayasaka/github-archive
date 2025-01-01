# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::SeatAssignments::EnterpriseTeamConverterCommandTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    disable_feature_flag(:copilot_revokable_access)
  end

  context "emu" do
    test "gets outta dodge if the seat assignment is pending cancellation" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team, pending_cancellation_date: Time.now)
      assert_raises(Copilot::Errors::SeatAssignmentPendingCancellationError) do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::EnterpriseTeamConverterCommand.new(seat_assignment)
        end
      end
    end

    test "throws an error if the assignable isn't an enterprise team" do
      seat_assignment = create(:copilot_seat_assignment, :organization)

      assert_raises Copilot::Errors::SeatAssignmentError do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::EnterpriseTeamConverterCommand.call(seat_assignment)
        end
      end
    end

    test "can't create a seat if it can't lock" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never

      lock_key = "enter-team-converter-command-#{seat_assignment.owner.id}-#{seat_assignment.assignable.id}"
      restraint = GitHub::Restraint.new

      restraint.lock!(lock_key, 1, 5.minutes) do
        assert_raises GitHub::Restraint::UnableToLock do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatAssignments::EnterpriseTeamConverterCommand.call(seat_assignment)
          end
        end
      end
    end

    test "creates new seats if none exist" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once.with(seat_assignment, 0, 2, 2)
      assert_difference "Copilot::Seat.count", 2 do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Processing enterprise team members") do
            Copilot::SeatAssignments::EnterpriseTeamConverterCommand.call(seat_assignment)
            refute_dogstats_increment("copilot.seat_assignment_conversion.skipped")
            assert_dogstats_histogram_value(2, "copilot.seat_assignment_conversion.difference")
            assert_dogstats_histogram_value(2, "copilot.seat_assignment_conversion.inserting")
            assert_dogstats_histogram_value(0, "copilot.seat_assignment_conversion.to_be_deleted")
          end
        end
      end
    end

    test "creates only seats that need to be created" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      enterprise_team = seat_assignment.assignable
      member = User.find_by(id: enterprise_team.member_user_ids.last)

      create(:copilot_seat, :enterprise_team_member, assigned_user: member, seat_assignment: seat_assignment)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once.with(seat_assignment, 1, 1, 1)
      assert_difference "Copilot::Seat.count", 1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Processing enterprise team members") do
            Copilot::SeatAssignments::EnterpriseTeamConverterCommand.call(seat_assignment)
            refute_dogstats_increment("copilot.seat_assignment_conversion.skipped")
            assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.difference")
            assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.inserting")
            assert_dogstats_histogram_value(0, "copilot.seat_assignment_conversion.to_be_deleted")
          end
        end
      end
    end

    test "doesnt create seats for suspended members" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      enterprise_team = seat_assignment.assignable
      member = User.find_by(id: enterprise_team.member_user_ids.last)
      T.must(member).update_column(:suspended_at, Time.now)

      seat = create(:copilot_seat, :enterprise_team_member, assigned_user: member, seat_assignment: seat_assignment)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once.with(seat_assignment, 0, 1, 1)
      assert_difference "Copilot::Seat.count", 0 do # delete suspended add new
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Processing enterprise team members") do
            Copilot::SeatAssignments::EnterpriseTeamConverterCommand.call(seat_assignment)
            refute_dogstats_increment("copilot.seat_assignment_conversion.skipped")
            assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.difference")
            assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.inserting")
            assert_dogstats_histogram_value(0, "copilot.seat_assignment_conversion.to_be_deleted")
          end
        end
      end

      refute Copilot::Seat.exists?(seat.id)
    end

    test "deletes seats without associated members" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      enterprise_team = seat_assignment.assignable

      assert_equal 2, enterprise_team.member_user_ids.count

      member_to_delete = User.find_by(id: enterprise_team.member_user_ids.last)
      seat = create(:copilot_seat, assigned_user: member_to_delete, organization: nil, seat_assignment: seat_assignment)

      member_to_delete&.destroy

      assert_equal 1, enterprise_team.member_user_ids.count

      GlobalInstrumenter.expects(:instrument).at_least_once
      GlobalInstrumenter.expects(:instrument).with(
        Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_CANCELLED, {
          user: nil,
          organization: nil,
          seat: seat,
          actor: seat_assignment.assigning_user,
          details: {}
        },
      ).never
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once.with(seat_assignment, 0, 1, 1)

      assert_difference "Copilot::Seat.count", 0 do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Deleted seats not associated with EnterpriseTeam members") do
            Copilot::SeatAssignments::EnterpriseTeamConverterCommand.call(seat_assignment)
            refute_dogstats_increment("copilot.seat_assignment_conversion.skipped")
            assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.difference")
            assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.inserting")
            assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.to_be_deleted")
          end
        end
      end
    end

    test "deletes seats without associated members who still exist in the DB, but not on the team" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      enterprise_team = seat_assignment.assignable
      first_user_id = enterprise_team.member_user_ids.first

      assert_equal 2, enterprise_team.member_user_ids.count

      member_to_delete = User.find_by(id: enterprise_team.member_user_ids.last)
      seat = create(:copilot_seat, assigned_user: member_to_delete, organization: nil, seat_assignment: seat_assignment)
      # Stub the team members to not include the removed user, to simulate their mapping being removed
      enterprise_team.stubs(:member_user_ids).returns([first_user_id])

      GlobalInstrumenter.expects(:instrument).at_least_once
      GlobalInstrumenter.expects(:instrument).with(
        Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_CANCELLED, {
          user: member_to_delete,
          organization: nil,
          seat: seat,
          actor: seat_assignment.assigning_user,
          details: {}
        },
      ).once
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).once.with(seat_assignment, 0, 1, 1)

      assert_difference "Copilot::Seat.count", 0 do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "Deleted seats not associated with EnterpriseTeam members") do
            Copilot::SeatAssignments::EnterpriseTeamConverterCommand.call(seat_assignment)
            refute_dogstats_increment("copilot.seat_assignment_conversion.skipped")
            assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.difference")
            assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.inserting")
            assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.to_be_deleted")
          end
        end
      end
    end

    test "Skips conversion if all members already have seats, destroys seats for deprovisioned users" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      enterprise_team = seat_assignment.assignable

      assert_equal 2, enterprise_team.member_user_ids.count

      enterprise_team.member_user_ids.each do |member_user_id|
        member = User.find_by(id: member_user_id)
        create(:copilot_seat, assigned_user: member, organization: nil, seat_assignment: seat_assignment)
      end

      suspended_user = User.find_by(id: enterprise_team.member_user_ids.last)
      suspended_user&.update_column(:suspended_at, Time.now)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never
      assert_difference "Copilot::Seat.count", -1 do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "No new seats need to be created") do
            assert_logged("Body" => "Destroyed seats for suspended team members") do
              Copilot::SeatAssignments::EnterpriseTeamConverterCommand.call(seat_assignment)
              assert_dogstats_increment(1, "copilot.seat_assignment_conversion.skipped")
              assert_dogstats_histogram_value(0, "copilot.seat_assignment_conversion.to_be_deleted")
            end
          end
        end
      end
    end

    test "does not destroy seats for deprovisioned users when the copilot_revokable_access feature flag is active" do
      enable_feature_flag(:copilot_revokable_access)
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      enterprise_team = seat_assignment.assignable

      enterprise_team.member_user_ids.each do |member_user_id|
        member = User.find_by(id: member_user_id)
        create(:copilot_seat, assigned_user: member, organization: nil, seat_assignment: seat_assignment)
      end

      suspended_user = User.find_by(id: enterprise_team.member_user_ids.last)
      suspended_user&.update_column(:suspended_at, Time.now)

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_assignment_conversion).never
      Copilot::Instrumenter.expects(:send_to_hydro).with do |args|
        assert_equal Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_CANCELLED, args
      end.never

      assert_no_difference "Copilot::Seat.count" do
        ActiveRecord::Base.connected_to(role: :reading) do
          assert_logged("Body" => "No new seats need to be created") do
            Copilot::SeatAssignments::EnterpriseTeamConverterCommand.call(seat_assignment)
            assert_dogstats_increment(1, "copilot.seat_assignment_conversion.skipped")
            assert_dogstats_histogram_value(0, "copilot.seat_assignment_conversion.to_be_deleted")
          end
        end
      end
    end
  end if TestEnv.test_with_all_emus?

  context "conversion when member is in multiple enterprise teams" do
    test "repoints existing seats that are pending cancellation to seat assignment being converted" do
      basic_enterprise = create(:business, :default_managed, seats_plan_type: :basic)

      ent_team1 = create(:enterprise_team, name: "ent-team-1", business: basic_enterprise)
      ent_team2 = create(:enterprise_team, name: "ent-team-2", business: basic_enterprise)

      duped_user = create(:user)
      user_without_seat = create(:user)
      basic_enterprise.add_user_accounts([duped_user.id, user_without_seat.id], business_roles_bitfield: 0)

      [ent_team1, ent_team2].each do |ent_team|
        ent_team.enterprise_team_memberships.create!(user_id: duped_user.id)
      end
      ent_team2.enterprise_team_memberships.create!(user_id: user_without_seat.id)

      seat_assignment = create(:copilot_seat_assignment,
        :enterprise_team,
        supplied_business: basic_enterprise,
        assignable: ent_team1,
      )

      # Intentionally _NOT_ using .convert_to_seats as that de-dupes users across enterprise teams
      create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: duped_user)

      seat_assignment.update_column(:pending_cancellation_date, Time.now)

      seat_assignment_to_convert = create(:copilot_seat_assignment,
        :enterprise_team,
        supplied_business: basic_enterprise,
        assignable: ent_team2,
      )

      assert_difference "Copilot::SeatAssignment.count", 0 do
        assert_difference "Copilot::Seat.count", 1 do
          ActiveRecord::Base.connected_to(role: :reading) do
            assert_logged("Body" => "Updated existing seats to point at this EnterpriseTeam SeatAssignment") do
              Copilot::SeatAssignments::EnterpriseTeamConverterCommand.call(seat_assignment_to_convert)
              assert_dogstats_increment(0, "copilot.seat_assignment_conversion.skipped")
              assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.existing_seats_updated")
              assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.difference")
              assert_dogstats_histogram_value(1, "copilot.seat_assignment_conversion.inserting")
              assert_dogstats_histogram_value(0, "copilot.seat_assignment_conversion.to_be_deleted")
            end
          end
        end
      end

      assert_equal seat_assignment_to_convert, Copilot::Seat.for_user(duped_user).first&.seat_assignment
      assert_equal seat_assignment_to_convert, Copilot::Seat.for_user(user_without_seat).first&.seat_assignment
    end

    test "does not delete suspended seats when the copilot_revokable_access feature flag is active" do
      enable_feature_flag(:copilot_revokable_access)

      basic_enterprise = create(:business, :default_managed, seats_plan_type: :basic)
      ent_team = create(:enterprise_team, name: "ent-team-1", business: basic_enterprise)

      team_user = create(:user)
      basic_enterprise.add_user_accounts([team_user.id], business_roles_bitfield: 0)
      ent_team.enterprise_team_memberships.create!(user_id: team_user.id)

      seat_assignment = create(:copilot_seat_assignment,
        :enterprise_team,
        supplied_business: basic_enterprise,
        assignable: ent_team,
      )
      ent_team.member_user_ids.each do |id|
        user = User.find_by(id: id)
        create(:copilot_seat, seat_assignment: seat_assignment, organization_id: nil, assigned_user: user)
      end

      team_user.update_column(:suspended_at, Time.now)

      assert_no_difference "Copilot::Seat.count" do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatAssignments::EnterpriseTeamConverterCommand.call(seat_assignment)
          assert_dogstats_increment(1, "copilot.seat_assignment_conversion.skipped")
          assert_dogstats_histogram_value(0, "copilot.seat_assignment_conversion.existing_seats_updated")
          assert_dogstats_histogram_value(0, "copilot.seat_assignment_conversion.to_be_deleted")

          refute_dogstats_histogram("copilot.seat_assignment_conversion.difference")
          refute_dogstats_histogram("copilot.seat_assignment_conversion.inserting")
        end
      end
    end
  end unless TestEnv.test_with_all_emus?
end if GitHub.copilot_enabled?
