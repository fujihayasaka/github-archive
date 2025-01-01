# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Payloads::Businesses::SeatManagementTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @business = T.let(create(:business, :enterprise_managed_business, seats_plan_type: :basic), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @enterprise_team = T.let(create(:copilot_enterprise_team, business: @business, name: "Awesome-Team"), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @enterprise_team_assignment = T.let(EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: "copilot"), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @seat_assignment = T.let(create(:copilot_seat_assignment, :enterprise_team, assignable: @enterprise_team, owner: @business), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
  end

  def expected_payload(merge: {})
    {
      business: {
        slug: @business.slug,
        login: T.cast(@business.display_login, String),
      },
      count: 1,
      filtered_count: 1,
      total_seats: @enterprise_team.member_user_ids.size,
      seatAssignments: [
        {
          id: @seat_assignment.id,
          assignable_type: @seat_assignment.assignable_type,
          pending_cancellation_date: @seat_assignment.pending_cancellation_date,
          last_activity_at: nil,
          status: Copilot::Types::SeatAssignment::Status::Stable.serialize,
          assignable: {
            id: @enterprise_team.id,
            mapping_id: @enterprise_team.enterprise_team_group_mappings.first&.external_group&.id,
            slug: @enterprise_team.slug,
            login: @enterprise_team.name,
            member_count: @enterprise_team.member_count,
            member_ids: @enterprise_team.member_user_ids
          }
        }
      ]
    }.merge(merge)
  end

  def payload(params: {})
    Copilot::Payloads::Businesses::SeatManagement.new(business: @business, params: ActionController::Parameters.new(**params)).call
  end

  context "#call" do
    test "returns the correct payload" do
      expected = expected_payload

      assert_equal expected, payload
    end

    test "return the correct payload when searching" do
      other_seat_assignment = create(
        :copilot_seat_assignment,
        :enterprise_team,
        supplied_business: @business,
        team_name: "bumz-mcgoo"
      )
      other_seat_assignment.convert_to_seats
      actual_payload = payload(params: { q: "bumz" })

      assert_equal actual_payload[:count], 2
      assert_equal actual_payload[:filtered_count], 1
      assert_equal actual_payload[:seatAssignments].size, 1
      assert_equal actual_payload[:seatAssignments].first[:id], other_seat_assignment.id
      assert_equal actual_payload[:total_seats], 4
    end

    context "when there are enterprise team assignments that haven't been converted to copilot seat assignments" do
      test "adds the pending assignment to the payload" do
        unsynced_enterprise_team = create :enterprise_team, business: @business
        EnterpriseTeamAssignment.create!(enterprise_team: unsynced_enterprise_team, assignment_type: "copilot")
        expected = expected_payload(merge: {
          count: 2,
          filtered_count: 2,
          total_seats: 2,
          seatAssignments: [
            {
              id: @seat_assignment.id,
              assignable_type: @seat_assignment.assignable_type,
              pending_cancellation_date: @seat_assignment.pending_cancellation_date,
              last_activity_at: nil,
              status: Copilot::Types::SeatAssignment::Status::Stable.serialize,
              assignable: {
                id: @enterprise_team.id,
                mapping_id: @enterprise_team.enterprise_team_group_mappings.first&.external_group&.id,
                slug: @enterprise_team.slug,
                login: @enterprise_team.name,
                member_count: @enterprise_team.member_count,
                member_ids: @enterprise_team.member_user_ids
              }
            },
            {
              id: nil,
              assignable_type: "EnterpriseTeam",
              pending_cancellation_date: nil,
              last_activity_at: nil,
              status: Copilot::Types::SeatAssignment::Status::Creating.serialize,
              assignable: {
                id: unsynced_enterprise_team.id,
                mapping_id: unsynced_enterprise_team.enterprise_team_group_mappings.first&.external_group&.id,
                slug: unsynced_enterprise_team.slug,
                login: unsynced_enterprise_team.name,
                member_count: unsynced_enterprise_team.member_count,
                member_ids: unsynced_enterprise_team.member_user_ids
              }
            },
          ]
        })

        assert_equal expected, payload
      end
    end

    context "when there is more than one page of assignments" do
      test "defaults to showing the first page" do
        Copilot::Payloads::Businesses::StandaloneBase.stub_const(:PER_PAGE, 1) do
          create(:copilot_seat_assignment, :enterprise_team, supplied_business: @business, member_count: 5)
          actual_payload = payload

          assert_equal actual_payload[:count], 2
          assert_equal actual_payload[:filtered_count], 2
          assert_equal actual_payload[:total_seats], 7
          assert_equal actual_payload[:seatAssignments].size, 1
          assert_equal actual_payload[:seatAssignments].first[:id], @seat_assignment.id
        end
      end

      test "uses the page param if present" do
        Copilot::Payloads::Businesses::StandaloneBase.stub_const(:PER_PAGE, 1) do
          other_seat_assignment = create(:copilot_seat_assignment, :enterprise_team, supplied_business: @business, member_count: 5)
          actual_payload = payload(params: { page: 2 })

          assert_equal actual_payload[:count], 2
          assert_equal actual_payload[:filtered_count], 2
          assert_equal actual_payload[:seatAssignments].size, 1
          assert_equal actual_payload[:total_seats], 7
          assert_equal actual_payload[:seatAssignments].first[:id], other_seat_assignment.id
        end
      end
    end

    context "mismatch between enterprise team assignments and copilot seat assignments" do
      context "seat assignment and team assignment" do
        test "seat assignment is pending_reassignment when there is a pending_cancellation_date" do
          @seat_assignment.update!(pending_cancellation_date: 1.day.from_now)

          expected_status = Copilot::Types::SeatAssignment::Status::Reassigning.serialize

          assert_equal expected_status, payload[:seatAssignments].first[:status]
        end

        test "seat assignment is stable when there is no pending_cancellation_date" do
          expected_status = Copilot::Types::SeatAssignment::Status::Stable.serialize

          assert_equal expected_status, payload[:seatAssignments].first[:status]
        end
      end

      context "seat assignment and no team assignment" do
        test "seat assignment is stable when there is no pending_cancellation_date" do
          @enterprise_team_assignment.destroy

          expected_status = Copilot::Types::SeatAssignment::Status::Unassigning.serialize

          assert_equal expected_status, payload[:seatAssignments].first[:status]
        end

        test "seat assignment is pending_unassignment when there is already a pending cancellation date" do
          @enterprise_team_assignment.destroy
          @seat_assignment.update!(pending_cancellation_date: 1.day.from_now)

          expected_status = Copilot::Types::SeatAssignment::Status::Cancelling.serialize

          assert_equal expected_status, payload[:seatAssignments].first[:status]
        end
      end
    end

    context "when sorting" do
      test "sorts by name ascending" do
        late_alphabetical_team = create :enterprise_team, business: @business, name: "Zany-Team"
        EnterpriseTeamAssignment.create!(enterprise_team: late_alphabetical_team, assignment_type: "copilot")

        actual = payload(params: { sort: "name_asc" })

        assert_equal @enterprise_team.name, actual[:seatAssignments][0][:assignable][:login]
        assert_equal late_alphabetical_team.name, actual[:seatAssignments][1][:assignable][:login]
      end

      test "sorts by name descending" do
        late_alphabetical_team = create :enterprise_team, business: @business, name: "Zany-Team"
        EnterpriseTeamAssignment.create!(enterprise_team: late_alphabetical_team, assignment_type: "copilot")

        actual = payload(params: { sort: "name_desc" })

        assert_equal late_alphabetical_team.name, actual[:seatAssignments][0][:assignable][:login]
        assert_equal @enterprise_team.name, actual[:seatAssignments][1][:assignable][:login]
      end

      test "sorts by member count ascending" do
        team_with_more_members = create :enterprise_team, business: @business
        EnterpriseTeamAssignment.create!(enterprise_team: team_with_more_members, assignment_type: "copilot")
        2.times do
          user = create :emu, business: @business
          team_with_more_members.enterprise_team_memberships.create!(user: user)
        end

        actual = payload(params: { sort: "member_count_asc" })

        assert_equal @enterprise_team.member_count, actual[:seatAssignments][0][:assignable][:member_count]
        assert_equal team_with_more_members.member_count, actual[:seatAssignments][1][:assignable][:member_count]
      end

      test "sorts by member count descending" do
        team_with_more_members = create :enterprise_team, business: @business
        EnterpriseTeamAssignment.create!(enterprise_team: team_with_more_members, assignment_type: "copilot")
        2.times do
          user = create :emu, business: @business
          team_with_more_members.enterprise_team_memberships.create!(user: user)
        end

        actual = payload(params: { sort: "member_count_desc" })

        assert_equal team_with_more_members.member_count, actual[:seatAssignments][0][:assignable][:member_count]
        assert_equal @enterprise_team.member_count, actual[:seatAssignments][1][:assignable][:member_count]
      end
    end

    context "when a team has usage data" do
      test "includes the aggregate usage" do
        create(:copilot_aggregate_usage_detail, user_id: @enterprise_team.member_user_ids.first, usage_date: Date.today)

        actual = payload

        assert_equal Date.today, actual[:seatAssignments][0][:last_activity_at].to_date
      end
    end
  end
end if GitHub.copilot_enabled?
