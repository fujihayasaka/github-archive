# typed: true
# frozen_string_literal: true

require "test_helper"

class Orgs::Settings::MemberFeatureRequests::SubscriptionsControllerTest < GitHub::IntegrationTestCase
  include MemberFeatureRequestsHelper
  include DogstatsTestHelpers

  fixtures do
    @admin = create(:user)
    @org = create(:organization, admin: @admin, plan: :free)
  end

  context "POST", skip_with_all_emus: true do
    test "subscribes to all notifications" do
      Notifyd::MemberFeatureRequestSettings.any_instance.stubs(:save).returns(true)
      MemberFeatureRequest::Notification::Setting.any_instance.expects(:all!)

      as @admin
      post "/organizations/#{@org}/settings/member_feature_requests/subscription",
        params: { organization_id: @org.id, features: [] }

      assert_response :ok
      assert_dogstats_increment(1, "member_feature_request_notification_subscription", tags: ["subscribed"])
    end

    test "returns error in case of failure to create" do
      Notifyd::MemberFeatureRequestSettings.any_instance.stubs(:save).returns(false)

      as @admin
      post "/organizations/#{@org}/settings/member_feature_requests/subscription",
      params: { organization_id: @org.id, do: "watching", features: [] }

      assert_response :unprocessable_entity
    end
  end

  context "PATCH", skip_with_all_emus: true do
    test "updates subscription to ignore if all features are not selected" do
      Notifyd::MemberFeatureRequestSettings.any_instance.stubs(:save).returns(true)
      MemberFeatureRequest::Notification::Setting.any_instance.expects(:ignore!)

      as @admin
      patch "/organizations/#{@org}/settings/member_feature_requests/subscription",
        params: { organization_id: @org.id, features: nil }

      assert_response :ok
      assert_dogstats_increment(1, "member_feature_request_notification_subscription", tags: ["custom"])
    end

    test "updates subscription to custom features" do
      Notifyd::MemberFeatureRequestSettings.any_instance.stubs(:save).returns(true)
      MemberFeatureRequest::Notification::Setting.any_instance.expects(:custom!).with(features: ["draft_pull_requests"])

      as @admin
      patch "/organizations/#{@org}/settings/member_feature_requests/subscription",
        params: { organization_id: @org.id, features: ["draft_pull_requests"] }

      assert_response :ok
      assert_dogstats_increment(1, "member_feature_request_notification_subscription", tags: ["custom"])
    end

    test "returns error in case of failure to update" do
      Notifyd::MemberFeatureRequestSettings.any_instance.stubs(:save).returns(false)

      as @admin
      patch "/organizations/#{@org}/settings/member_feature_requests/subscription",
      params: { organization_id: @org.id, do: "watching", features: [] }

      assert_response :unprocessable_entity
    end
  end

  context "DELETE", skip_with_all_emus: true do
    test "unsubscribe to all notifications" do
      Notifyd::MemberFeatureRequestSettings.any_instance.stubs(:save).returns(true)
      MemberFeatureRequest::Notification::Setting.any_instance.expects(:ignore!)

      as @admin
      delete "/organizations/#{@org}/settings/member_feature_requests/subscription",
        params: { organization_id: @org.id, features: [] }

      assert_response :ok
      assert_dogstats_increment(1, "member_feature_request_notification_subscription", tags: ["ignore"])
    end

    test "returns error in case of failure to delete" do
      Notifyd::MemberFeatureRequestSettings.any_instance.stubs(:save).returns(false)

      as @admin
      delete "/organizations/#{@org}/settings/member_feature_requests/subscription",
      params: { organization_id: @org.id, do: "watching", features: [] }

      assert_response :unprocessable_entity
    end
  end
end unless GitHub.enterprise?
