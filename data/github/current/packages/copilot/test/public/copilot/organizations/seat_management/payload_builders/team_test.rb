# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Organizations::SeatManagement::PayloadBuilders::TeamTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include AvatarHelper

  fixtures do
    @organization = T.let(create(:copilot_for_business_enabled_organization), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
  end

  setup do
    Copilot::Organization.new(@organization).seat_management_selected_teams_and_users!
  end

  def seat_detail(assignable)
    Copilot::Organizations::SeatManagement::Detail.new(organization: @organization,
                                                       seat_assignment_id: 0,
                                                       assignable: assignable,
                                                       pending_cancellation_date: nil,
                                                       last_activity_at: Time.at(0))
  end

  context "#call" do
    context "when the seat_detail does not have an assignable" do
      test "returns nil" do
        builder = Copilot::Organizations::SeatManagement::PayloadBuilders::Team.new(seat_detail: seat_detail(nil))

        assert_nil builder.call
      end
    end

    context "when the seat_detail has an assignable" do
      test "returns the correct payload" do
        team = create(:team)
        expected = {
          assignable_type: "Team",
          pending_cancellation_date: nil,
          last_activity_at: Time.at(0),
          invitation_date: nil,
          invitation_expired: nil,
          assignable: {
            id: team.id,
            login: team.name,
            slug: team.slug,
            avatar_url: avatar_url_for(team, 48),
            combined_slug: team.combined_slug,
            member_count: team.members_count,
            member_ids: team.member_ids,
            display_name: nil,
            email: nil,
            invitee: nil
          }
        }
        builder = Copilot::Organizations::SeatManagement::PayloadBuilders::Team.new(seat_detail: seat_detail(team))

        assert_equal expected, builder.call
      end
    end
  end
end if GitHub.copilot_enabled?
