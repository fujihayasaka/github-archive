# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Organizations::SeatManagement::MemberSearchPayloadTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include Elastomer::TestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags
  include AvatarHelper

  fixtures do
    @user = T.let(create(:user, login: "no-seat-admin"), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @organization = T.let(create(:organization, admin: @user), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped

    @team = T.let(create(:team, organization: @organization, name: "no-seat-team", privacy: :closed), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @child_team = create(:team, organization: @organization, name: "no-seat-child-team", parent_team_id: @team.id, privacy: :closed)
    @child_user = create(:user, login: "no-seat-child-user")
    @child_team.add_member(@child_user)

    @user_with_seat = T.let(create(:user, login: "seat-user"), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @organization.add_member(@user_with_seat)

    @team_with_seat = T.let(create(:team, organization: @organization, name: "seat-team", privacy: :closed), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @team_member_with_seat = T.let(create(:user, login: "seat-team-member"), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @team_with_seat.add_member(@team_member_with_seat)

    @invitation = T.let(create(:organization_invitation, organization: @organization), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
  end

  setup do
    Copilot::Organization.new(@organization).seat_management_selected_teams_and_users!
    create(:copilot_seat_assignment, :user, assignable: @user_with_seat, organization: @organization, assigning_user: @user)
    create(:copilot_seat_assignment, :team, assignable: @team_with_seat, organization: @organization, assigning_user: @user)
    create(:copilot_seat_assignment, :organization_invitation, assignable: @invitation, organization: @organization, assigning_user: @user) unless TestEnv.test_with_all_emus?
    Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
  end

  def default_expected_payload
    {
      total: 5,
      assignables: [
        {
          id: @team.id,
          avatar_url: avatar_url_for(@team, 24),
          name: @team.name,
          slug: T.must(@team.slug),
          org_member: true,
          member_ids: T.let(@team.member_ids, T::Array[Integer]),
          type: Copilot::Types::Search::Team,
        },
        {
          id: @child_team.id,
          avatar_url: avatar_url_for(@child_team, 24),
          name: @child_team.name,
          slug: T.must(@child_team.slug),
          org_member: true,
          member_ids: T.let(@child_team.member_ids, T::Array[Integer]),
          type: Copilot::Types::Search::Team,
        },
        {
          id: @user.id,
          avatar_url: avatar_url_for(@user, 24),
          display_login: @user.display_login,
          profile_name: @user.profile_name,
          org_member: true,
          type: Copilot::Types::Search::User,
          feature_request: nil
        },
        {
          id: @child_user.id,
          avatar_url: avatar_url_for(@child_user, 24),
          display_login: @child_user.display_login,
          profile_name: @child_user.profile_name,
          org_member: true,
          type: Copilot::Types::Search::User,
          feature_request: nil
        },
        {
          org_member: false,
          type: Copilot::Types::Search::OrganizationInvite,
          id: @invitation.id,
          avatar_url: avatar_url_for(@invitation.invitee, 24),
          display_login: @invitation.email_or_invitee_name,
          profile_name: @invitation.invitee&.display_login
        }
      ]
    }
  end

  def payload(params: {}, org: @organization, user: @user)
    Copilot::Organizations::SeatManagement::MemberSearchPayload.new(organization: org,
                                                                    params: ActionController::Parameters.new(params),
                                                                    current_user: user).call
  end

  context "#call" do
    test "payloads come in different shapes sometimes" do
      expected = default_expected_payload
      actual = payload

      assert_equal expected[:total], actual[:total]
    end

    context "when there are more results than the per page limit" do
      test "paginates and still returns correct total" do
        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
        Copilot::Organizations::SeatManagement::MemberSearchPayload.stub_const(:PER_PAGE, 1) do
          actual = payload

          assert_equal 5, actual[:total]
          assert_equal 1, actual[:assignables].size
        end
      end
    end

    context "when querying" do
      test "handles queries when searching for users in the org" do
        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
        actual = payload(params: { q: "no-seat-admin" })

        assert_equal [{
          id: @user.id,
          avatar_url: avatar_url_for(@user, 24),
          display_login: @user.display_login,
          profile_name: @user.profile_name,
          org_member: true,
          type: Copilot::Types::Search::User,
          feature_request: nil
        }], actual[:assignables]
      end

      test "handles queries when searching for teams in the org" do
        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
        actual = payload(params: { q: "no-seat-team" })

        assert_equal [{
          id: @team.id,
          avatar_url: avatar_url_for(@team, 24),
          name: @team.name,
          slug: T.must(@team.slug),
          org_member: true,
          member_ids: T.let(@team.member_ids, T::Array[Integer]),
          type: Copilot::Types::Search::Team,
        }], actual[:assignables]
      end

      test "correctly identifies whether searched users have access already and doesnt include them in the results" do
        second_page_user = create(:user, login: "second-page-user")
        @organization.add_member(second_page_user)
        create(:copilot_seat_assignment, :user, assignable: second_page_user, organization: @organization, assigning_user: @user)

        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)

        Copilot::Organizations::SeatManagement::MemberSearchPayload.stub_const(:PER_PAGE, 1) do
          actual = payload(params: { q: "second-page-user" })

          assert_equal [], actual[:assignables]
        end
      end

      test "handles queries when searching for users outside the org" do
        outside_user = create(:user, login: "outside-user")
        Copilot::SeatManagement::UserSuggestionsView.any_instance.stubs(:suggestions).returns([outside_user])
        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
        actual = payload(params: { q: "outside" })

        assert_equal [{
          id: outside_user.id,
          avatar_url: avatar_url_for(outside_user, 24),
          display_login: outside_user.display_login,
          profile_name: outside_user.profile_name,
          org_member: false,
          type: Copilot::Types::Search::User,
          feature_request: nil
        }], actual[:assignables]
      end

      test "handles queries when searching for new users via email" do
        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
        actual = payload(params: { q: "newperson@email.com" })

        assert_equal [{
          id: nil,
          avatar_url: nil,
          org_member: false,
          type: Copilot::Types::Search::OrganizationInvite,
          display_login: "newperson@email.com",
          profile_name: nil
        }], actual[:assignables]
      end

      test "does not suggest seated members when searching by login" do
        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
        actual = payload(params: { q: @user_with_seat.display_login })

        assert_equal [], actual[:assignables]
      end

      test "does not suggest seated members when searching by email" do
        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
        actual = payload(params: { q: @user_with_seat.email })

        assert_equal [], actual[:assignables]
      end

      test "does not suggest seated members when searching by email of invited users" do
        invited_user = create(:user, email: "jamie@gmail.com")
        @email_invitation = T.let(create(:organization_invitation, organization: @organization, invitee: invited_user), T.untyped)  # rubocop:todo Sorbet/ForbidTUntyped
        create(:copilot_seat_assignment, assignable: @email_invitation, organization: @organization, assigning_user: @user)
        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)

        actual = payload(params: { q: invited_user.email })

        assert_equal [], actual[:assignables]
      end

      test "does not suggest new users via email if the org is on a free trial" do
        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
        Copilot::BusinessTrial.create_trial!(@organization, @user).start_trial!
        actual = payload(params: { q: "newperson@email.com" })

        assert_equal [], actual[:assignables]
      end

      test "does not suggest org members who are suspended" do
        login = "badbuddy"
        bad_buddy = create(:user, display_login: login)
        @organization.add_member(bad_buddy)
        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
        bad_buddy.update(suspended_at: Time.current)

        search_payload = Copilot::Organizations::SeatManagement::MemberSearchPayload.new(
          organization: @organization,
          params: ActionController::Parameters.new({ q: login }),
          current_user: @user
        )
        actual = search_payload.call

        assert_empty actual[:assignables]
      end

      test "does not suggest other users who may be suspended" do
        setup_search
        org = create(:copilot_enterprise_enabled_organization)

        good_user = create(:user, display_login: "goodbuddy", login: "goodbuddy")
        bad_user = create(:user, display_login: "badbuddy", login: "badbuddy")

        org.add_member(good_user)
        org.add_member(bad_user)
        bad_user.update(suspended_at: Time.current)

        make_searchable(good_user, bad_user)

        search_payload = Copilot::Organizations::SeatManagement::MemberSearchPayload.new(
          organization: org,
          params: ActionController::Parameters.new({ q: "buddy" }),
          current_user: @user
        )

        actual = search_payload.call
        assert_equal actual[:assignables].count, 1
        assert_equal actual[:assignables].first[:display_login], good_user.display_login

        # Search should return a suspended user
        ::User.expects(:search).returns([bad_user])

        search_payload = Copilot::Organizations::SeatManagement::MemberSearchPayload.new(
          organization: org,
          params: ActionController::Parameters.new({ q: "badbuddy" }),
          current_user: @user
        )
        actual = search_payload.call

        # Suspended users should be cleared here
        assert_empty actual[:assignables]

        teardown_search
      end

      test "does not suggest members outside the org when the org is enterprise managed" do
        setup_search
        org = create(:copilot_enterprise_enabled_organization)

        member_user = create(:user, display_login: "member", login: "member")
        other_rando = create(:user, display_login: "rando", login: "rando")

        org.add_member(member_user)

        make_searchable(member_user, other_rando)

        search_payload = Copilot::Organizations::SeatManagement::MemberSearchPayload.new(
          organization: org,
          params: ActionController::Parameters.new({ q: "member" }),
          current_user: @user
        )

        actual = search_payload.call
        assert_equal actual[:assignables].count, 1
        assert_equal actual[:assignables].first[:display_login], member_user.display_login

        search_payload = Copilot::Organizations::SeatManagement::MemberSearchPayload.new(
          organization: org,
          params: ActionController::Parameters.new({ q: "rando" }),
          current_user: @user
        )
        actual = search_payload.call
        assert_empty actual[:assignables]

        teardown_search
      end if TestEnv.test_with_all_emus?
    end

    test "includes feature request for users that have requested access" do
      member = create(:user)
      @organization.add_member(member)
      feature_request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @organization, requester: member)
      Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
      actual = payload

      # Force db timestamp for comparison
      feature_request.reload

      assert_includes actual[:assignables], {
        id: member.id,
        avatar_url: avatar_url_for(member, 24),
        display_login: member.display_login,
        profile_name: member.profile_name,
        org_member: true,
        type: Copilot::Types::Search::User,
        feature_request: {
          id: feature_request.id,
          requested_at: feature_request.updated_at,
        },
      }
    end

    test "does not include feature_request for users that have not requested access" do
      member = create(:user)
      @organization.add_member(member)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @organization, requester: member)
      Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
      actual = payload

      assert_includes actual[:assignables], {
        id: @user.id,
        avatar_url: avatar_url_for(@user, 24),
        display_login: @user.display_login,
        profile_name: @user.profile_name,
        org_member: true,
        type: Copilot::Types::Search::User,
        feature_request: nil
      }
    end

    test "only include feature requests for users with unfulfilled requests" do
      member = create(:user)
      @organization.add_member(member)
      feature_request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @organization, requester: member)

      another_member = create(:user)
      @organization.add_member(another_member)
      create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @organization, requester: another_member, status: :fulfilled)
      Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)

      actual = payload

      assert_includes actual[:assignables], {
        id: member.id,
        avatar_url: avatar_url_for(member, 24),
        display_login: member.display_login,
        profile_name: member.profile_name,
        org_member: true,
        type: Copilot::Types::Search::User,
        feature_request: {
          id: feature_request.id,
          requested_at: feature_request.updated_at,
        },
      }

      assert_includes actual[:assignables], {
        id: another_member.id,
        avatar_url: avatar_url_for(another_member, 24),
        display_login: another_member.display_login,
        profile_name: another_member.profile_name,
        org_member: true,
        type: Copilot::Types::Search::User,
        feature_request: nil
      }

    end

    context "sort assignables by requested_at" do
      test "ascending" do
        # Create several user instances with different requested_at values
        member1 = create(:user)
        member2 = create(:user)
        member3 = create(:user)
        @organization.add_member(member1)
        @organization.add_member(member2)
        @organization.add_member(member3)
        request1 = create(:member_feature_request, requester: member1, request_entity: @organization,
          feature: MemberFeatureRequest::Feature::CopilotForBusiness, updated_at: 3.days.ago)
        request2 = create(:member_feature_request, requester: member2, request_entity: @organization,
          feature: MemberFeatureRequest::Feature::CopilotForBusiness, updated_at: 1.day.ago)
        request3 = create(:member_feature_request, requester: member3, request_entity: @organization,
          feature: MemberFeatureRequest::Feature::CopilotForBusiness, updated_at: 2.days.ago)
        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
        sorted_requested_at = [
          {
            id: member1.id,
            avatar_url: avatar_url_for(member1, 24),
            display_login: member1.display_login,
            profile_name: member1.profile_name,
            org_member: true,
            type: Copilot::Types::Search::User,
            feature_request: {
              id: request1.id,
              requested_at: request1.updated_at,
            },
          },
          {
            id: member3.id,
            avatar_url: avatar_url_for(member3, 24),
            display_login: member3.display_login,
            profile_name: member3.profile_name,
            org_member: true,
            type: Copilot::Types::Search::User,
            feature_request: {
              id: request3.id,
              requested_at: request3.updated_at,
            },
          },
          {
            id: member2.id,
            avatar_url: avatar_url_for(member2, 24),
            display_login: member2.display_login,
            profile_name: member2.profile_name,
            org_member: true,
            type: Copilot::Types::Search::User,
            feature_request: {
              id: request2.id,
              requested_at: request2.updated_at,
            },
          }
        ]

        expected_payload_with_sorted_requested_at = {
          total: 8,
          assignables: sorted_requested_at + default_expected_payload[:assignables]
        }

        expected = expected_payload_with_sorted_requested_at
        actual = payload(params: { sort: "requested_at_asc" })

        assert_equal expected[:total], actual[:total]
        assert_equal expected[:assignables].first(3), actual[:assignables].first(3)
      end

      test "descending" do
        # Create several user instances with different requested_at values
        member1 = create(:user)
        member2 = create(:user)
        member3 = create(:user)
        @organization.add_member(member1)
        @organization.add_member(member2)
        @organization.add_member(member3)
        request1 = create(:member_feature_request, requester: member1, request_entity: @organization,
          feature: MemberFeatureRequest::Feature::CopilotForBusiness, updated_at: 3.days.ago)
        request2 = create(:member_feature_request, requester: member2, request_entity: @organization,
          feature: MemberFeatureRequest::Feature::CopilotForBusiness, updated_at: 1.day.ago)
        request3 = create(:member_feature_request, requester: member3, request_entity: @organization,
          feature: MemberFeatureRequest::Feature::CopilotForBusiness, updated_at: 2.days.ago)
        Copilot::SeatAssignment.for_organization(@organization).map(&:convert_to_seats)
        sorted_requested_at = [
          {
            id: member2.id,
            avatar_url: avatar_url_for(member2, 24),
            display_login: member2.display_login,
            profile_name: member2.profile_name,
            org_member: true,
            type: Copilot::Types::Search::User,
            feature_request: {
              id: request2.id,
              requested_at: request2.updated_at,
            },
          },
          {
            id: member3.id,
            avatar_url: avatar_url_for(member3, 24),
            display_login: member3.display_login,
            profile_name: member3.profile_name,
            org_member: true,
            type: Copilot::Types::Search::User,
            feature_request: {
              id: request3.id,
              requested_at: request3.updated_at,
            },
          },
          {
            id: member1.id,
            avatar_url: avatar_url_for(member1, 24),
            display_login: member1.display_login,
            profile_name: member1.profile_name,
            org_member: true,
            type: Copilot::Types::Search::User,
            feature_request: {
              id: request1.id,
              requested_at: request1.updated_at,
            },
          }
        ]

        expected_payload_with_sorted_requested_at = {
          total: 8,
          assignables: sorted_requested_at + default_expected_payload[:assignables]
        }

        expected = expected_payload_with_sorted_requested_at
        actual = payload(params: { sort: "requested_at_desc" })

        assert_equal expected[:total], actual[:total]
        assert_equal expected[:assignables].first(3), actual[:assignables].first(3)
      end
    end
  end
end if GitHub.copilot_enabled?
