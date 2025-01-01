# typed: true
# frozen_string_literal: true

require "test_helper"

class Orgs::Settings::MemberFeatureRequestsControllerTest < GitHub::IntegrationTestCase
  include MemberFeatureRequestsHelper
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @admin = create(:user)
    @org = create(:organization, admin: @admin, plan: :free)
  end

  setup do
    GitHub.flipper[:raf_email_notifications_notifyd].disable
  end

  def mock_notifyd
    expected_settings = Notifyd::Proto::RoutingSettings::RoutingSetting.new(
        name: "MemberFeatureRequest",
        topics: [Notifyd::Proto::RoutingSettings::Topic.new(type: "organization", value: @org.id.to_s)],
        channels: [Notifyd::Proto::RoutingSettings::Channel.new(name: "ALL", enabled: true)],
        custom_fields: [Notifyd::Proto::RoutingSettings::CustomField.new(
            name: "delivery_group", value: "member_feature_request"
          )
        ],
        filters: [
          Notifyd::Proto::RoutingSettings::Filter.new(
            subject_type: "MemberFeatureRequest::Notification", trigger: "any", reason: "any"
          ),
        ],
      )
    expected_response = Notifyd::Proto::RoutingSettings::GetResponse.new(routing_setting: [expected_settings])
    Notifyd::MemberFeatureRequestSettings.any_instance.stubs(:get).returns(expected_response)
  end

  if GitHub.enterprise? || TestEnv.test_with_all_emus?
    context "404s for emu or enterprise server" do
      test "GET /organizations/:org/settings/member_feature_requests" do
        billing_manager = create(:user)
        Organization::BillingManagement.new(@org).add_manager(billing_manager, actor: @admin)
        as billing_manager

        get "/organizations/#{@org.display_login}/settings/member_feature_requests"

        assert_response_not_found
      end
    end
  else
    context "GET #show" do
      test "redirects to login for anon" do
        @session.clear
        as nil

        url = "/organizations/#{@org.display_login}/settings/member_feature_requests"
        get url

        assert_redirected_to login_path(return_to: "http://github.com#{url}")
      end

      test "renders 404 when you don't have access to the org" do
        another_org = create(:organization)
        as @admin

        get "/organizations/#{another_org.display_login}/settings/member_feature_requests"

        assert_response :not_found
      end

      test "renders 404 when you are not an org admin or billing manager" do
        member = create(:user)
        @org.add_member(member)
        as member

        get "/organizations/#{@org.display_login}/settings/member_feature_requests"

        assert_response :not_found
      end

      test "renders the page when you are an org billing manager" do
        billing_manager = create(:user)
        Organization::BillingManagement.new(@org).add_manager(billing_manager, actor: @admin)
        as billing_manager

        get "/organizations/#{@org.display_login}/settings/member_feature_requests"

        assert_response :ok
      end

      test "renders the page with the total count of feature requests" do
        mock_notifyd
        requesters = create_list(:user, 2)
        requesters.each do |requester|
          @org.add_member(requester)
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: @org, requester: requester)
        end
        as @admin

        get "/organizations/#{@org.display_login}/settings/member_feature_requests"

        assert_response :ok
        assert_test_selector "total-feature-protected_branches-total", text: /2/
      end

      test "renders the page with the heading of individual member feature requests" do
        mock_notifyd
        requesters = create_list(:user, 2)
        requesters.each do |requester|
          @org.add_member(requester)
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: @org, requester: requester)
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, request_entity: @org, requester: requester)
        end
        as @admin

        get "/organizations/#{@org.display_login}/settings/member_feature_requests"

        assert_response :ok
        assert_test_selector "team-features-member-requests", text: /Member requests for GitHub*/
      end

      test "marks the user as having visited the page" do
        as @admin
        mock_notifyd
        assert_nil user_visited_feature_request_page_at(@org, @admin)

        get "/organizations/#{@org.display_login}/settings/member_feature_requests"

        refute_nil user_visited_feature_request_page_at(@org, @admin)
      end

      test "only consider features that are not on my plan" do
        Organizations::MemberRequests::WatchButtonComponent.any_instance.stubs(:render?).returns(false)
        business_org = create(:organization, admin: @admin, plan: :business)

        requester_on_my_plan = create(:user)
        requester_not_on_my_plan = create(:user)
        business_org.add_member(requester_on_my_plan)
        business_org.add_member(requester_not_on_my_plan)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: business_org, requester: requester_on_my_plan)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, request_entity: business_org, requester: requester_not_on_my_plan)
        as @admin

        get "/organizations/#{business_org.display_login}/settings/member_feature_requests"

        assert_response :ok
        assert_test_selector "total-feature-custom_repository_roles-total", text: /1/
        assert_includes response.body, "Custom repository roles"
        refute_includes response.body, "Protected branches"
      end

      test "renders the team banner when current plan is free and no enterprise only features are requested" do\
        mock_notifyd
        requester = create(:user)
        @org.add_member(requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: @org, requester: requester)
        as @admin

        get "/organizations/#{@org.display_login}/settings/member_feature_requests"

        assert_response :ok
        assert_includes response.body, "Team Features"
        assert_test_selector "requests-from-members-upgrade-cta", text: "Upgrade to Team" do |link|
          assert_equal "/account/upgrade?org=#{@org.display_login}&plan=business&target=organization", link.attr("href").value
          expected = {
            category: "requests_from_members_page",
            action: "click_to_upgrade_free_to_team",
            label: "ref_cta:upgrade_to_team; ref_loc:requests_from_members_unlock_banner"
          }.stringify_keys
          assert_equal expected, JSON.parse(link.attr("data-analytics-event"))
        end
      end

      test "renders the enterprise banner when current plan is free and enterprise only features are requested" do
        mock_notifyd
        requester = create(:user)
        @org.add_member(requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, request_entity: @org, requester: requester)
        as @admin

        get "/organizations/#{@org.display_login}/settings/member_feature_requests"

        assert_response :ok
        assert_includes response.body, "Enterprise Features"
      end

      test "renders the try enterprise for free when the org is eligible for trial" do
        mock_notifyd
        requester = create(:user)
        @org.add_member(requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, request_entity: @org, requester: requester)
        as @admin

        get "/organizations/#{@org.display_login}/settings/member_feature_requests"

        assert_response :ok
        assert @org.eligible_for_org_enterprise_cloud_trial?
        assert_test_selector "requests-from-members-try-enterprise-cta", text: "Try Enterprise for free" do |link|
          assert_equal "/account/enterprises/new/#{@org.display_login}", link.attr("href").value
          expected = {
            category: "requests_from_members_page",
            action: "click_to_select_trial_enterprise_plan",
            label: "ref_cta:try_enterprise_for_free; ref_loc:requests_from_members_unlock_banner"
          }.stringify_keys
          assert_equal expected, JSON.parse(link.attr("data-analytics-event"))
        end
      end

      test "renders the upgrade to enterprise when the org is not eligible for trial" do
        mock_notifyd
        requester = create(:user)
        @org.add_member(requester)
        create(:billing_plan_trial, user: @org, plan: "business_plus")
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, request_entity: @org, requester: requester)
        as @admin

        get "/organizations/#{@org.display_login}/settings/member_feature_requests"

        assert_response :ok
        refute @org.eligible_for_org_enterprise_cloud_trial?
        assert_test_selector "requests-from-members-upgrade-cta", text: "Upgrade to Enterprise" do |link|
          assert_equal "/account/upgrade?org=#{@org.display_login}&plan=business_plus&target=organization", link.attr("href").value
          expected = {
            category: "requests_from_members_page",
            action: "click_to_upgrade_free_to_enterprise",
            label: "ref_cta:upgrade_to_enterprise; ref_loc:requests_from_members_unlock_banner"
          }.stringify_keys
          assert_equal expected, JSON.parse(link.attr("data-analytics-event"))
        end
      end

      test "renders the enterprise banner when current plan is team" do
        mock_notifyd
        business_org = create(:organization, admin: @admin, plan: :business)
        requester = create(:user)
        business_org.add_member(requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, request_entity: business_org, requester: requester)
        as @admin

        get "/organizations/#{business_org.display_login}/settings/member_feature_requests"

        assert_response :ok
        assert_includes response.body, "Enterprise Features"
      end

      test "renders the upgrade to enterprise when the current plan is team and the org is not eligible for trial" do
        mock_notifyd
        business_org = create(:organization, admin: @admin, plan: :business)
        requester = create(:user)
        business_org.add_member(requester)
        create(:billing_plan_trial, user: business_org, plan: "business_plus")
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, request_entity: business_org, requester: requester)
        as @admin

        get "/organizations/#{business_org.display_login}/settings/member_feature_requests"

        assert_response :ok
        assert_test_selector "requests-from-members-upgrade-cta", text: "Upgrade to Enterprise" do |link|
          assert_equal "/account/upgrade?org=#{business_org.display_login}&plan=business_plus&target=organization", link.attr("href").value
          expected = {
            category: "requests_from_members_page",
            action: "click_to_upgrade_team_to_enterprise",
            label: "ref_cta:upgrade_to_enterprise; ref_loc:requests_from_members_unlock_banner"
          }.stringify_keys
          assert_equal expected, JSON.parse(link.attr("data-analytics-event"))
        end
      end

      test "renders the watch customer story" do
        mock_notifyd
        requester = create(:user)
        @org.add_member(requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: @org, requester: requester)
        as @admin

        get "/organizations/#{@org.display_login}/settings/member_feature_requests"

        assert_response :ok
        assert_test_selector "requests-from-members-watch-customer-story-cta", text: "Watch customer story" do |link|
          assert_equal "https://www.youtube.com/watch?v=z8Tqq6AltMo", link.attr("href").value
          expected = {
            category: "requests_from_members_page",
            action: "click_to_watch_customer_story_video",
            label: "ref_cta:watch_customer_story; ref_loc:requests_from_members_unlock_banner"
          }.stringify_keys
          assert_equal expected, JSON.parse(link.attr("data-analytics-event"))
        end
      end

      context "with feature section" do
        test "renders at least one enterprise feature request" do
          mock_notifyd
          requester = create(:user)
          @org.add_member(requester)
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: @org, requester: requester)
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles, request_entity: @org, requester: requester)
          as @admin

          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          assert_response :ok
          assert_test_selector "enterprise-team-feature-title", text: /Enterprise Features/
        end

        test "renders only team feature requests" do
          mock_notifyd
          requester = create(:user)
          @org.add_member(requester)
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: @org, requester: requester)
          as @admin

          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          assert_response :ok
          assert_test_selector "enterprise-team-feature-title", text: /Team Features/
        end

        test "renders view docs link" do
          mock_notifyd
          requester = create(:user)
          @org.add_member(requester)
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: @org, requester: requester)
          as @admin

          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          assert_response :ok
          assert_test_selector "requests-from-members-view-docs-protected-branches-cta", text: "View docs" do |link|
            assert_match "/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches", link.attr("href").value
            expected = {
              category: "requests_from_members_page",
              action: "click_to_view_docs_protected_branches",
              label: "ref_cta:view_docs; ref_loc:requests_from_members_page_team_features"
            }
          end
        end

        test "renders anchor tag" do
          mock_notifyd
          requester = create(:user)
          @org.add_member(requester)
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: @org, requester: requester)
          as @admin

          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          assert_response :ok
          assert_select "[id=protected_branches]"
        end
      end

      context "with add-on section" do
        test "does not render add-on section when the org has no addon" do
          mock_notifyd
          requesters = create_list(:user, 2)
          requesters.each do |requester|
            @org.add_member(requester)
            create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: @org, requester: requester)
          end
          as @admin

          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          assert_response :ok
          refute_test_selector "business-addons-heading", text: /2/
        end

        test "renders the page with the total count of copilot for business requests" do
          mock_notifyd
          requesters = create_list(:user, 2)
          requesters.each do |requester|
            @org.add_member(requester)
            create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @org, requester: requester)
          end
          as @admin

          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          assert_response :ok
          assert_test_selector "total-addon-copilot_for_business", text: /2/
        end

        test "renders the page without the first header when there is at least one team feature request" do
          mock_notifyd
          requester = create(:user)
          @org.add_member(requester)
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @org, requester: requester)
          as @admin

          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          assert_response :ok
          refute_test_selector "team-features-member-requests", text: /2/
        end

        test "renders cta to buy add-on" do
          mock_notifyd
          requester = create(:user)
          @org.add_member(requester)
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @org, requester: requester)
          as @admin

          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          assert_response :ok
          assert_test_selector "addon-primary-cta", text: /Buy #{Copilot.business_product_name}/
        end

        test "renders cta to see how it works" do
          mock_notifyd
          requester = create(:user)
          @org.add_member(requester)
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @org, requester: requester)
          as @admin

          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          assert_response :ok
          assert_test_selector "addon-see-how-it-works-cta", text: /See how it works/
        end

        test "renders anchor tag" do
          mock_notifyd
          requester = create(:user)
          @org.add_member(requester)
          create(:member_feature_request, feature: MemberFeatureRequest::Feature::CopilotForBusiness, request_entity: @org, requester: requester)
          as @admin

          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          assert_response :ok
          assert_select "[id=copilot_for_business]"
        end
      end

      test "renders watching component" do
        mock_notifyd
        requester = create(:user)
        @org.add_member(requester)
        create(:member_feature_request, feature: MemberFeatureRequest::Feature::ProtectedBranches, request_entity: @org, requester: requester)
        as @admin

        get "/organizations/#{@org.display_login}/settings/member_feature_requests"

        assert_response :ok
        assert_test_selector "feature-request-watch-button"
        assert_test_selector "feature-request-subscription-form"
        assert_test_selector "feature-request-custom-form"
      end

      context "markings notifications as read" do
        test "mark all notifications that belongs to the same user and org as read" do
          notification = create(:member_feature_request_notification, entity: @org, user: @admin, feature: MemberFeatureRequest::Feature::ProtectedBranches.to_s)
          summary = NotificationSummary.fetch_and_update!(notification.notifications_list, notification.notifications_thread, notification)
          Newsies::NotificationEntry.insert(@admin.id, summary, reason: "mention", event_time: 1.day.ago)

          as @admin
          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          assert_hydro_published(
            { user_id: @admin.id, threads: [notification.to_global_id.to_s] },
            schema: "notifications.v0.MarkAsRead",
            topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 }
          )
        end

        test "does not mark notifications as read if they belong to other user" do
          new_admin = create(:user)
          notification = create(:member_feature_request_notification, entity: @org, user: new_admin, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles.to_s)
          summary = NotificationSummary.fetch_and_update!(notification.notifications_list, notification.notifications_thread, notification)
          Newsies::NotificationEntry.insert(new_admin.id, summary, reason: "mention", event_time: 1.day.ago)

          as @admin
          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          refute_hydro_messages(schema: "notifications.v0.MarkAsRead")
        end

        test "does not mark notifications as read if they belong to other organization" do
          new_org = create(:organization)
          new_org.add_admin(@admin)
          notification = create(:member_feature_request_notification, entity: new_org, user: @admin, feature: MemberFeatureRequest::Feature::CustomRepositoryRoles.to_s)
          summary = NotificationSummary.fetch_and_update!(notification.notifications_list, notification.notifications_thread, notification)
          Newsies::NotificationEntry.insert(@admin.id, summary, reason: "mention", event_time: 1.day.ago)

          as @admin
          get "/organizations/#{@org.display_login}/settings/member_feature_requests"

          refute_hydro_messages(schema: "notifications.v0.MarkAsRead")
        end
      end
    end
  end
end
