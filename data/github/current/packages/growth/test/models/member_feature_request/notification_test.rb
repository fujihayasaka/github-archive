# typed: strict
# frozen_string_literal: true

require "test_helper"

class MemberFeatureRequest::NotificationTest < GitHub::TestCase
  context "validation" do
    test "it is valid when all criteria is satisfied" do
      admin = create(:user)
      org = create(:organization, admin: admin)

      assert_instance_of MemberFeatureRequest::Notification,
        MemberFeatureRequest::Notification.create!(
          feature: "copilot_for_business",
          feature_request_count: 1,
          entity: org,
          user: admin
        )
    end

    test "invalidates if admin is missing" do
      notification = build(:member_feature_request_notification, user: nil, entity: create(:organization))

      refute notification.valid?
    end

    test "invalidates if feature request count is invalid" do
      notification = build(:member_feature_request_notification, user: create(:user), feature_request_count: 0)

      refute notification.valid?
    end
  end

  context "dual write entity" do
    test "it sets entity id and type" do
      notification = create(:member_feature_request_notification)

      assert_equal notification.entity_id, notification.entity_id
      assert_equal "User", notification.entity_type
    end
  end

  context "#notification_id" do
    test "it returns a unique id" do
      notification = create(:member_feature_request_notification)

      assert_equal "member_feature_request_notification_#{notification.feature}_#{notification.id}", notification.notification_id
    end
  end

  context "newsies adapter" do
    test "it sends permalink to the request from members page" do
      notification = create(:member_feature_request_notification)

      assert_equal "https://github.com/organizations/#{notification.entity.display_login}/settings/member_feature_requests", notification.permalink
    end

    test "returns itself for notifications thread" do
      notification = create(:member_feature_request_notification)

      assert_equal notification, notification.notifications_thread
    end

    test "returns organization (entity) for notifications list" do
      notification = create(:member_feature_request_notification)

      assert_equal notification.entity, notification.notifications_list
    end

    test "returns body with feature request count and feature name" do
      org = create(:organization, name: "Growth")
      notification = create(:member_feature_request_notification,
        entity: org,
        feature_request_count: 1,
        feature: "protected_branches"
      )

      assert_equal "[Growth] You have 1 new request from members for protected branches", notification.body
    end

    test "pluralizes body" do
      org = create(:organization, name: "Growth")
      notification = create(:member_feature_request_notification,
        entity: org,
        feature_request_count: 5,
        feature: "copilot_for_business"
      )

      assert_equal "[Growth] You have 5 new requests from members for #{Copilot.business_product_name}", notification.body
    end

    test "is not readable by another user" do
      notification = create(:member_feature_request_notification)
      another_user = create(:user)

      refute notification.async_readable_by?(another_user)
    end

    test "is readable by the user" do
      notification = create(:member_feature_request_notification)

      assert notification.async_readable_by?(notification.user)
    end
  end

  test "returns text displayed in notifications group" do
    notification = create(:member_feature_request_notification)

    assert_equal "MemberFeatureRequestNotification", notification.platform_type_name
  end

  test "unsubscribes user from specific features if notifications are enabled" do
    organization = create(:organization)
    user = create(:user)
    organization.add_admin(user)

    unsubscribe_features = { organization.id => MemberFeatureRequest::Feature.values.map(&:to_s) }
    setting_response = Notifyd::Proto::RoutingSettings::GetResponse.new(routing_setting: [])
    Notifyd::MemberFeatureRequestSettings.any_instance.expects(:get).returns(setting_response)

    Notifyd::RoutingSettingsService.any_instance.expects(:save).once.returns(true)
    MemberFeatureRequest::Notification.unsubscribe(user: user, unsubscription: unsubscribe_features)
  end

  test "does nothing if user is already ignoring notifications" do
    organization = create(:organization)
    user = create(:user)
    organization.add_admin(user)

    unsubscribe_features = { organization.id => MemberFeatureRequest::Feature.values.map(&:to_s) }
    expected_settings = Notifyd::Proto::RoutingSettings::RoutingSetting.new(
      name: "MemberFeatureRequest",
      topics: [Notifyd::Proto::RoutingSettings::Topic.new(type: "organization", value: organization.id.to_s)],
      channels: [Notifyd::Proto::RoutingSettings::Channel.new(name: "ALL", enabled: false)],
      custom_fields: [],
      filters: [],
    )
    setting_response = Notifyd::Proto::RoutingSettings::GetResponse.new(routing_setting: [expected_settings])
    Notifyd::MemberFeatureRequestSettings.any_instance.expects(:get).returns(setting_response)

    Notifyd::RoutingSettingsService.any_instance.expects(:save).never
    MemberFeatureRequest::Notification.unsubscribe(user: user, unsubscription: unsubscribe_features)
  end

  context "permalink" do
    if GitHub.copilot_enabled?
      test "returns the permalink to allow seat assignment if it is a copilot feature and user can manage org and business" do
        owner = create(:user)
        business = create(:business, owners: [owner])
        org = create(:organization, admin: owner, business: business)
        notification = create(:member_feature_request_notification, feature: MemberFeatureRequest::Feature::CopilotForBusiness.to_s, entity: org, user: owner)

        assert_includes notification.permalink, "/organizations/#{org.name}/settings/copilot/seat_management"
      end
    else
      test "returns the permalink to the member feature request page if Copilot is not enabled" do
        owner = create(:user)
        business = create(:business, owners: [owner])
        org = create(:organization, admin: owner, business: business)
        notification = create(:member_feature_request_notification, feature: MemberFeatureRequest::Feature::CopilotForBusiness.to_s, entity: org, user: owner)

        assert_includes notification.permalink, "/organizations/#{org.name}/settings/member_feature_requests"
      end
    end

    test "returns the permalink to the member feature request page if it is not a copilot feature" do
      owner = create(:user)
      business = create(:business, owners: [owner])
      org = create(:organization, admin: owner, business: business)
      notification = create(:member_feature_request_notification, feature: MemberFeatureRequest::Feature::DraftPullRequests.to_s, entity: org, user: owner)

      assert_includes notification.permalink, "/organizations/#{org.name}/settings/member_feature_requests"
    end

    test "returns the permalink to the member feature request page if it is a copilot feature but user not enabled to assign seats" do
      owner = create(:user)
      another_user = create(:user)
      business = create(:business, owners: [another_user])
      org = create(:organization, admin: owner, business: business)
      notification = create(:member_feature_request_notification, feature: MemberFeatureRequest::Feature::CopilotForBusiness.to_s, entity: org, user: owner)

      assert_includes notification.permalink, "/organizations/#{org.name}/settings/member_feature_requests"
    end
  end

  context "#message_id" do
    test "returns unique message id for enterprise" do
      business = create(:business, name: "growth-business")
      notification = create(:member_feature_request_notification, entity: business, feature: "copilot_for_business")

      assert_equal "<growth-business/feature_requests/copilot_for_business@#{GitHub.urls.host_name}>", notification.message_id
    end

    test "returns unique message id for organization" do
      organization = create(:organization, :with_profile, name: "growth-org", profile_name: "Growth Org")
      notification = create(:member_feature_request_notification, entity: organization, feature: "copilot_for_business")

      assert_equal "<growth-org/feature_requests/copilot_for_business@#{GitHub.urls.host_name}>", notification.message_id
    end
  end

  test "when entity is a business" do
    business = create(:business)
    notification = create(:member_feature_request_notification, entity: business, feature: "copilot_for_business")

    assert_equal business, notification.entity
    assert_equal "#{GitHub.url}/enterprises/#{business.display_login}/settings/copilot", notification.permalink
    assert_equal "New requests from admins", notification.title
    assert_equal "[#{business.safe_profile_name}] You have 1 new request from admins for Copilot Business", notification.body
  end
end
