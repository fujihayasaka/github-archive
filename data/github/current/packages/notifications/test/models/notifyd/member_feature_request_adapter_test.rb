# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class MemberFeatureRequestAdapterTest < GitHub::TestCase
    include NotifydTestHelper

    fixtures do
      @admin = create(:user)
      @organization = create(:organization, plan: :free, admin: @admin)
    end

    context "validating subject" do
      test "validates a subject with admin, organization, feature and feature count" do
        subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

        assert adapter(subject).matches?
      end

      test "invalidates subject when user is missing" do
        subject = FactoryBot.build(:member_feature_request_notification, user: nil, entity: @organization)

        refute adapter(subject).matches?
      end
    end

    context "#authzd_attributes" do
      test "matches owning_organization when entity is an Organization" do
        subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

        assert adapter(subject).authzd_attributes.any? { |authzd| authzd.id == "subject.owning_organization.id" }
        refute adapter(subject).authzd_attributes.any? { |authzd| authzd.id == "subject.business.id" }

        authzd_attribute = adapter(subject).authzd_attributes.find { |authzd| authzd.id == "subject.owning_organization.id" }
        assert_equal authzd_attribute.value.integer_value, subject.entity_id
      end

      test "matches subject.business.id when entity is a Business" do
        subject = create(:member_feature_request_notification, user: @admin, entity: create(:business))

        assert adapter(subject).authzd_attributes.any? { |authzd| authzd.id == "subject.business.id" }
        refute adapter(subject).authzd_attributes.any? { |authzd| authzd.id == "subject.owning_organization.id" }

        authzd_attribute = adapter(subject).authzd_attributes.find { |authzd| authzd.id == "subject.business.id" }
        assert_equal authzd_attribute.value.integer_value, subject.entity_id
      end
    end

    context "#saml_enforcement" do
      test "returns skip_enforcement when entity is a Business" do
        subject = create(:member_feature_request_notification, user: @admin, entity: create(:business))

        assert_equal({ skip_enforcement: true }, adapter(subject).saml_enforcement)
      end

      test "returns organization_id when entity is an Organization" do
        subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

        expected_enforcement = { organization_id: subject.entity_id }

        assert_equal expected_enforcement, adapter(subject).saml_enforcement
      end
    end

    context "#notify_feature_flag" do
      test "returns true when flag is enabled" do
        subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

        enable_feature_flag(:raf_email_notifications_notifyd)

        assert adapter(subject).notify_feature_flag.enabled?
      end

      test "returns false when flag is disabled" do
        subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

        disable_feature_flag(:raf_email_notifications_notifyd)

        refute adapter(subject).notify_feature_flag.enabled?
      end
    end

    test "#mobile_layout" do
      subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

      assert_nil adapter(subject).mobile_layout
    end

    context "#related_topics" do
      test "returns related topics for an Organization" do
        subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

        related_topics = [{ type: "organization", value: @organization.id.to_s }]

        assert_equal related_topics, adapter(subject).related_topics
      end

      test "returns related topics for a Business" do
        business = create(:business)
        subject = create(:member_feature_request_notification, user: @admin, entity: business)

        related_topics = [{ type: "business", value: business.id.to_s }]

        assert_equal related_topics, adapter(subject).related_topics
      end
    end

    test "#repository_id" do
      subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

      assert_nil adapter(subject).repository_id
    end

    test "#attributes" do
      subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

      assert_nil adapter(subject).attributes
    end

    test "#actor" do
      subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

      assert_equal @admin, adapter(subject).actor
    end

    test "#owner_id" do
      subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

      assert_equal @admin.id, adapter(subject).owner_id
    end

    test "#owner_type" do
      subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

      assert_equal :user, adapter(subject).owner_type
    end

    test "#trigger" do
      subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

      assert_equal "member_feature_requested", adapter(subject).trigger
    end

    test "#notification_id" do
      Timecop.freeze do
        subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

        assert_equal "member_feature_request_notification_#{subject.feature}_#{subject.id}", adapter(subject).notification_id
      end
    end

    context "#email_layout" do
      test "returns correct email layout for an organization request" do
        subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

        email = adapter(subject).email_layout

        assert_instance_of Notifyd::Proto::Layouts::Email::Basic, email
        assert_equal "[#{@organization.name}] New requests from members for protected branches", email.subject
        assert_match "You have 1 new request from members for protected branches", email.body
        assert_match "organizations/#{@organization.display_login}/settings/member_feature_requests", email.body
      end

      test "returns correct email layout for an business request" do
        business = create(:business, owners: [@admin], name: "Growth Business")
        subject = create(:member_feature_request_notification, user: @admin, entity: business, feature: "copilot_for_business")

        email = adapter(subject).email_layout

        assert_instance_of Notifyd::Proto::Layouts::Email::Basic, email
        assert_equal "[Growth Business] New requests from admins for Copilot Business", email.subject
        assert_match "Organizations in your Growth Business enterprise want Copilot Business", email.body
        assert_match "enterprises/#{business.display_login}/settings/copilot", email.body
      end
    end

    test "#feature_switches returns correct data" do
      subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

      expected = { notify_actor: true, notify_subscribers: false }
      assert_equal expected, adapter(subject).feature_switches
    end

    test "#explicit_recipients" do
      subject = create(:member_feature_request_notification, user: @admin, entity: @organization)

      expected = [{ reason: "member_feature_requested", users: [subject.user] }]
      assert_equal expected, adapter(subject).explicit_recipients
    end

    private

    def adapter(subject)
      context = {
        actor_id: @admin.id,
        organization_id: @organization.id,
        operation: "member_feature_requested"
      }

      Notifyd::MemberFeatureRequestAdapter.new(subject, context)
    end
  end
end
