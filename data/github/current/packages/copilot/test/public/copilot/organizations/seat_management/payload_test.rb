# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Organizations::SeatManagement::PayloadTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include AvatarHelper

  fixtures do
    @admin = create(:user)
    @ent_linked_org = T.let(create(:copilot_for_business_enabled_organization, admin: @admin), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @non_ent_linked_org = T.let(create(:copilot_for_business_enabled_non_enterprise_organization), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
  end

  setup do
    Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
    Copilot::Organization.any_instance.stubs(:is_copilot_plan_misconfigured?).returns(false)
    Copilot::Organization.new(@ent_linked_org).seat_management_selected_teams_and_users!
    Copilot::Organization.new(@non_ent_linked_org).seat_management_selected_teams_and_users!
    Copilot::Organizations::SeatManagement::PayloadBuilders::User
      .any_instance.stubs(:call).returns({ assignable: "User" })
    Copilot::Organizations::SeatManagement::PayloadBuilders::Team
      .any_instance.stubs(:call).returns({ assignable: "Team" })
    Copilot::Organizations::SeatManagement::PayloadBuilders::OrganizationInvitation
      .any_instance.stubs(:call).returns({ assignable: "OrganizationInvitation" })
    Copilot::Organizations::SeatManagement::PayloadBuilders::Organization
      .any_instance.stubs(:call).returns({ assignable: "Organization" })
    GitHub.flipper[:copilot_show_unconfigured_org_state].disable
  end

  def expected_payload(merge: {}, org: @ent_linked_org)
    {
      policy: "enabled_for_selected",
      seats: {
        seats: [],
        count: 0,
        pending_requests: { requesters: [], count: 0 },
        licenses: {
          user_ids: [],
          team_ids: [],
          invite_user_ids: [],
          invite_emails: [],
        }
      },
      seat_breakdown: { seats_assigned: 0, seats_billed: 0, seats_pending: 0, description: "0 seats assigned" },
      seat_assignments: 0,
      public_code_suggestions_configured: true,
      business_trial: nil,
      render_trial_expired_banner: false,
      can_add_teams: false,
      organization: {
        name: org.display_login,
        id: org.id,
        billable: true,
        has_seat: false,
        add_seat_link: nil,
      },
      business: {
        name: org.business&.name,
        slug: org.business&.slug,
      },
      members_count: org.members_count,
      can_allow_to_assign_seats_on_business: false,
      next_billing_date: Copilot::Organization.new(org).pending_cancellation_date,
      plan_text: "Business",
      featureRequestInfo: {
        showFeatureRequest: false,
        alreadyRequested: false,
        dismissed: false,
        featureName: "copilot_for_business",
        requestPath: "/orgs/#{org.display_login}/member_feature_request",
        isEnterpriseRequest: true,
        dismissedAt: nil,
        billingEntityId: org.business&.id.to_s,
        latestUsernameRequests: MemberFeatureRequest.latest_members_by_feature_request(org, MemberFeatureRequest::Feature::CopilotForBusiness, 1),
        amountOfUserRequests: MemberFeatureRequest.total_for_feature(org, MemberFeatureRequest::Feature::CopilotForBusiness),
      },
      render_pending_downgrade_banner: false,
      render_misconfigured_plan_for_org_banner: false,
    }.deep_merge(merge)
  end

  def payload(organization: @ent_linked_org)
    Copilot::Organizations::SeatManagement::Payload.new(organization: organization, params: ActionController::Parameters.new, current_user: @admin).call
  end

  def seat_detail(assignable)
    Copilot::Organizations::SeatManagement::Detail.new(organization: @ent_linked_org,
                                                       seat_assignment_id: 0,
                                                       assignable: assignable,
                                                       pending_cancellation_date: nil,
                                                       last_activity_at: Time.at(0))
  end

  context "#call" do
    context "when the organization has no linked enterprise" do
      test "returns the correct payload for users, teams, and organization invites" do
        user = create(:user)
        @non_ent_linked_org.add_admin(@admin)
        team = create(:team, organization: @non_ent_linked_org)
        invite = create(:organization_invitation, organization: @non_ent_linked_org)
        Copilot::Organization.any_instance.stubs(:seat_assignments).returns([seat_detail(user),
                                                                             seat_detail(team),
                                                                             seat_detail(invite),
                                                                             seat_detail(nil)])
        expected = expected_payload(merge: {
          organization: {
            name: @non_ent_linked_org.display_login,
            id: @non_ent_linked_org.id,
            add_seat_link: "/organizations/#{@non_ent_linked_org.login}/settings/billing/seats",
            billable: true,
            has_seat: false
          },
          business: nil,
          seats: {
            seats: [{ assignable: "User" }, { assignable: "Team" }, { assignable: "OrganizationInvitation" }],
            count: 4,
            pending_requests: { requesters: [], count: 0 },
            licenses: {
              user_ids: [],
              team_ids: [],
              invite_user_ids: [],
              invite_emails: [],
            }
          },
          seat_assignments: 4,
          can_add_teams: true,
          featureRequestInfo: {
            isEnterpriseRequest: false
          },
        }, org: @non_ent_linked_org)

        assert_equal expected, payload(organization: @non_ent_linked_org)
      end
    end

    context "when the organization is set to have copilot enabled for selected" do
      test "returns the correct payload for users, teams, and organization invites" do
        user = create(:user)
        team = create(:team, organization: @ent_linked_org)
        invite = create(:organization_invitation, organization: @ent_linked_org)
        Copilot::Organization.any_instance.stubs(:seat_assignments).returns([seat_detail(user),
                                                                             seat_detail(team),
                                                                             seat_detail(invite),
                                                                             seat_detail(nil)])
        expected = expected_payload(merge: {
          seats: {
            seats: [{ assignable: "User" }, { assignable: "Team" }, { assignable: "OrganizationInvitation" }],
            count: 4,
            pending_requests: { requesters: [], count: 0 },
            licenses: {
              user_ids: [],
              team_ids: [],
              invite_user_ids: [],
              invite_emails: [],
            }
          },
          seat_assignments: 4,
          can_add_teams: true
        })
        assert_equal expected, payload
      end
    end

    context "when the organization is set to have copilot disabled" do
      test "returns the correct payload with seat details based off the org" do
        Copilot::Organization.new(@ent_linked_org).seat_management_disable!
        Copilot::Organization.any_instance.stubs(:all_org_seat_assignments).returns([seat_detail(@ent_linked_org)])
        Copilot::Organization.any_instance.stubs(:seat_assignments).returns([seat_detail(@ent_linked_org)])

        expected = expected_payload(merge: {
          policy: "disabled",
          seats: {
            seats: [{ assignable: "Organization" }],
            count: 1,
            pending_requests: { requesters: [], count: 0 },
            licenses: {
              user_ids: [],
              team_ids: [],
              invite_user_ids: [],
              invite_emails: [],
            }
          },
          seat_assignments: 1,
        })

        assert_equal expected, payload
      end
    end

    context "when the organization is set to have copilot enabled for all" do
      test "returns the correct payload with seat details based off the org" do
        Copilot::Organization.new(@ent_linked_org).seat_management_allow_all!
        Copilot::Organization.any_instance.stubs(:all_org_seat_assignments).returns([seat_detail(@ent_linked_org)])
        Copilot::Organization.any_instance.stubs(:seat_assignments).returns([seat_detail(@ent_linked_org)])

        expected = expected_payload(merge: {
          policy: "enabled_for_all",
          seats: {
            seats: [{ assignable: "Organization" }],
            count: 1,
            pending_requests: { requesters: [], count: 0 },
            licenses: {
              user_ids: [],
              team_ids: [],
              invite_user_ids: [],
              invite_emails: [],
            }
          },
          seat_assignments: 1,
        })

        assert_equal expected, payload
      end
    end

    context "when the organization has a business trial" do
      test "payload includes the trial" do
        user = create(:user)
        trial = Copilot::BusinessTrial.create_trial!(@ent_linked_org, @ent_linked_org.admins.first)
        trial.start_trial!

        payload = Copilot::Organizations::SeatManagement::Payload.new(organization: @ent_linked_org,
                                                                      params: ActionController::Parameters.new,
                                                                      current_user: user).call

        assert_equal payload[:business_trial], trial.to_object
      end
    end

    context "when the organization has a seat" do
      test "payload sets has_organization_seat to true" do
        create(:copilot_seat, organization: @ent_linked_org)

        assert payload[:organization][:has_seat]
      end
    end

    context "add seat link" do
      test "when org admin and no business" do
        user = create(:user)
        org = create(:organization)
        org.add_member(user)
        org.add_admin(user)
        Copilot::Organization.new(org).seat_management_selected_teams_and_users!
        payload = Copilot::Organizations::SeatManagement::Payload.new(organization: org,
                                                                      params: ActionController::Parameters.new,
                                                                      current_user: user).call
        assert_equal payload[:organization][:add_seat_link], "/organizations/#{org.login}/settings/billing/seats"
      end

      test "when org admin and business admin" do
        user = create(:user, login: "admin-one")
        business = create(:business, owners: [user])
        org = create(:organization, business: business)
        Copilot::Organization.new(org).seat_management_selected_teams_and_users!
        payload = Copilot::Organizations::SeatManagement::Payload.new(organization: org,
                                                                      params: ActionController::Parameters.new,
                                                                      current_user: user).call
        assert_equal payload[:organization][:add_seat_link], "/enterprises/#{business.slug}/enterprise_licensing?manage_seats=true"
      end

      test "when org admin but not business admin" do
        business = create(:business, owners: [create(:user, login: "admin-one")])
        user = create(:user)
        org = create(:organization, business: business)
        org.add_member(user)
        org.add_admin(user)
        Copilot::Organization.new(org).seat_management_selected_teams_and_users!
        payload = Copilot::Organizations::SeatManagement::Payload.new(organization: org,
                                                                      params: ActionController::Parameters.new,
                                                                      current_user: user).call
        assert_nil payload[:organization][:add_seat_link]
      end
    end

    context "when there are pending seat requests" do
      test "returns the payload with pending seat requests" do
        user = create(:user)
        @ent_linked_org.add_member(user)
        feature_request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @ent_linked_org, requester: user)
        expected = expected_payload(merge: {
          seats: {
            seats: [],
            count: 0,
            pending_requests: {
              requesters: [{
                id: user.id,
                display_login: user.display_login,
                profile_name: user.profile_name,
                # Force db timestamp for comparison
                requested_at: feature_request.reload.updated_at,
              }],
              count: 1,
            },
            licenses: {
              user_ids: [],
              team_ids: [],
              invite_user_ids: [],
              invite_emails: [],
            }
          },
          seat_assignments: 0
        })

        assert_equal expected, payload
      end

      test "returns the payload without fulfilled requests" do
        user = create(:user)
        @ent_linked_org.add_member(user)
        feature_request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @ent_linked_org, requester: user)

        another_user = create(:user)
        @ent_linked_org.add_member(another_user)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @ent_linked_org, requester: another_user, status: :fulfilled)

        expected = expected_payload(merge: {
          seats: {
            seats: [],
            count: 0,
            pending_requests: {
              requesters: [{
                id: user.id,
                display_login: user.display_login,
                profile_name: user.profile_name,
                requested_at: feature_request.updated_at,
              }],
              count: 1,
            },
            licenses: {
              user_ids: [],
              team_ids: [],
              invite_user_ids: [],
              invite_emails: [],
            }
          },
          seat_assignments: 0,
        })

        assert_equal expected, payload
      end

      context "when there are no pending seat requests" do
        test "returns the payload with empty pending seat requests" do
          expected = expected_payload(merge: {
            seats: {
              seats: [],
              count: 0,
              pending_requests: { requesters: [], count: 0 },
              licenses: {
                user_ids: [],
                team_ids: [],
                invite_user_ids: [],
                invite_emails: [],
              }
            },
            seat_assignments: 0
          })

          assert_equal expected, payload
        end
      end

      test "returns the payload with pending seat requests even when there are some seats assigned" do
        user = create(:user)
        @ent_linked_org.add_member(user)
        feature_request = create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @ent_linked_org, requester: user)
        Copilot::Organization.any_instance.stubs(:seat_assignments).returns([seat_detail(user)])

        expected = expected_payload(merge: {
          seats: {
            seats: [{ assignable: "User" }],
            count: 1,
            pending_requests: {
              requesters: [{
                id: user.id,
                display_login: user.display_login,
                profile_name: user.profile_name,
                requested_at: feature_request.updated_at,
              }],
              count: 1,
            },
            licenses: {
              user_ids: [],
              team_ids: [],
              invite_user_ids: [],
              invite_emails: [],
            }
          },
          seat_assignments: 1,
        })

        assert_equal expected, payload
      end
    end

    context "when organization does not have a business" do
      test "returns the payload without the business object" do
        user = create(:user)
        non_enterprise_org = create(:copilot_for_business_enabled_non_enterprise_organization, admin: user)
        Copilot::Organization.new(non_enterprise_org).seat_management_selected_teams_and_users!

        payload = Copilot::Organizations::SeatManagement::Payload.new(
          organization: non_enterprise_org,
          params: ActionController::Parameters.new,
          current_user: user
        ).call

        expected = expected_payload(merge: {
          organization: {
            name: non_enterprise_org.display_login,
            id: non_enterprise_org.id,
            billable: true,
            has_seat: false,
            add_seat_link: "/organizations/#{non_enterprise_org.display_login}/settings/billing/seats",
          },
          business: nil,
          business_trial: nil,
          next_billing_date: Copilot::Organization.new(non_enterprise_org).pending_cancellation_date,
          featureRequestInfo: {
            isEnterpriseRequest: false,
          }
        }, org: non_enterprise_org)
        assert_equal expected, payload
      end
    end
  end

  context "#render_misconfigured_plan_for_org_banner?" do
    test "returns true when the org has a misconfigured plan" do
      GitHub.flipper[:copilot_mixed_licenses].enable
      GitHub.flipper[:copilot_show_unconfigured_org_state].enable
      @ent_linked_org.business.add_owner(@admin, actor: @admin)
      Copilot::Organization.any_instance.unstub(:is_copilot_plan_misconfigured?)

      actual = Copilot::Organizations::SeatManagement::Payload.new(
        organization: @ent_linked_org,
        params: ActionController::Parameters.new,
        current_user: @admin
      ).call

      assert actual[:render_misconfigured_plan_for_org_banner]
    end

    test "returns false when Copilot is not enabled" do
      GitHub.flipper[:copilot_mixed_licenses].enable
      GitHub.flipper[:copilot_show_unconfigured_org_state].enable
      @ent_linked_org.business.add_owner(@admin, actor: @admin)
      Copilot::Organization.any_instance.unstub(:is_copilot_plan_misconfigured?)
      Copilot::Organization.new(@ent_linked_org).disable_copilot!

      actual = Copilot::Organizations::SeatManagement::Payload.new(
        organization: @ent_linked_org,
        params: ActionController::Parameters.new,
        current_user: @admin
      ).call

      assert actual[:render_misconfigured_plan_for_org_banner]
    end

    test "returns false when the org has an explicit plan" do
      GitHub.flipper[:copilot_mixed_licenses].enable
      GitHub.flipper[:copilot_show_unconfigured_org_state].enable
      @ent_linked_org.business.add_owner(@admin, actor: @admin)
      Copilot::Organization.any_instance.unstub(:is_copilot_plan_misconfigured?)
      Copilot::Organization.new(@ent_linked_org).copilot_plan_business!(false)

      actual = Copilot::Organizations::SeatManagement::Payload.new(
        organization: @ent_linked_org,
        params: ActionController::Parameters.new,
        current_user: @admin
      ).call

      refute actual[:render_misconfigured_plan_for_org_banner]
    end

    test "returns false when the org admin is not the same as the enterprise admin" do
      GitHub.flipper[:copilot_mixed_licenses].enable
      GitHub.flipper[:copilot_show_unconfigured_org_state].enable
      actual = Copilot::Organizations::SeatManagement::Payload.new(
        organization: @ent_linked_org,
        params: ActionController::Parameters.new,
        current_user: @admin
      ).call

      refute actual[:render_misconfigured_plan_for_org_banner]
    end

    test "returns false when the copilot_show_unconfigured_org_state feature flag is inactive" do
      GitHub.flipper[:copilot_mixed_licenses].enable
      GitHub.flipper[:copilot_show_unconfigured_org_state].disable
      @ent_linked_org.business.add_owner(@admin, actor: @admin)
      Copilot::Organization.any_instance.unstub(:is_copilot_plan_misconfigured?)

      actual = Copilot::Organizations::SeatManagement::Payload.new(
        organization: @ent_linked_org,
        params: ActionController::Parameters.new,
        current_user: @admin
      ).call

      refute actual[:render_misconfigured_plan_for_org_banner]
    end
  end
end if GitHub.copilot_enabled?
