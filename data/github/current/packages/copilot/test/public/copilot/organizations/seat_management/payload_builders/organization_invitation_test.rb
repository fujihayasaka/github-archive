# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Organizations::SeatManagement::PayloadBuilders::OrganizationInvitationTest < GitHub::TestCase
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
        builder = Copilot::Organizations::SeatManagement::PayloadBuilders::OrganizationInvitation.new(seat_detail: seat_detail(nil))

        assert_nil builder.call
      end
    end

    context "when the seat_detail has an assignable" do
      context "when the invitation has an invitee" do
        test "returns the correct payload with the invitee included" do
          invite = create(:organization_invitation, organization: @organization)
          expected = {
            assignable_type: "OrganizationInvitation",
            pending_cancellation_date: nil,
            last_activity_at: Time.at(0),
            invitation_date: invite.created_at,
            invitation_expired: false,
            assignable: {
              id: invite.id,
              display_name: invite.invitee.profile_name,
              login: invite.invitee.display_login,
              avatar_url: T.cast(avatar_url_for(invite.invitee, 96), String),
              email: invite.email,
              invitee: {
                id: invite.invitee.id,
                display_name: invite.invitee.profile_name,
                login: invite.invitee.display_login,
                avatar_url: T.cast(avatar_url_for(invite.invitee, 96), String)
              },
              slug: nil,
              combined_slug: nil,
              member_count: nil,
              member_ids: nil,
            }
          }
          builder = Copilot::Organizations::SeatManagement::PayloadBuilders::OrganizationInvitation.new(seat_detail: seat_detail(invite))

          assert_equal expected, builder.call
        end
      end

      context "when the invitation is expired" do
        test "returns the correct payload with invitation_expired true" do
          invite = create(:organization_invitation, organization: @organization)
          invite.expire
          invite.reload
          expected = {
            assignable_type: "OrganizationInvitation",
            pending_cancellation_date: nil,
            last_activity_at: Time.at(0),
            invitation_date: invite.created_at,
            invitation_expired: true,
            assignable: {
              id: invite.id,
              display_name: invite.invitee.profile_name,
              login: invite.invitee.display_login,
              avatar_url: T.cast(avatar_url_for(invite.invitee, 96), String),
              email: invite.email,
              invitee: {
                id: invite.invitee.id,
                display_name: invite.invitee.profile_name,
                login: invite.invitee.display_login,
                avatar_url: T.cast(avatar_url_for(invite.invitee, 96), String)
              },
              slug: nil,
              combined_slug: nil,
              member_count: nil,
              member_ids: nil,
            }
          }
          builder = Copilot::Organizations::SeatManagement::PayloadBuilders::OrganizationInvitation.new(seat_detail: seat_detail(invite))

          assert_equal expected, builder.call
        end
      end

      context "when the invitation does not have an invitee" do
        test "returns the correct payload with just the invitation info" do
          invite = create(:organization_invitation, organization: @organization)
          invite.update(invitee: nil)
          expected = {
            assignable_type: "OrganizationInvitation",
            pending_cancellation_date: nil,
            last_activity_at: Time.at(0),
            invitation_date:  invite.created_at,
            invitation_expired: false,
            assignable: {
              id: invite.id,
              display_name: nil,
              login: nil,
              avatar_url: nil,
              email: invite.email,
              invitee: nil,
              slug: nil,
              combined_slug: nil,
              member_count: nil,
              member_ids: nil,
            }
          }
          builder = Copilot::Organizations::SeatManagement::PayloadBuilders::OrganizationInvitation.new(seat_detail: seat_detail(invite))

          assert_equal expected, builder.call
        end
      end
    end
  end
end if GitHub.copilot_enabled?
