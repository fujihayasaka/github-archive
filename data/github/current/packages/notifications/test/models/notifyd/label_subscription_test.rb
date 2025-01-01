# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class NotifydLabelSubscriptionTest < GitHub::TestCase
    include NotifydTestHelper
    Subs = Notifyd::Proto::Subscriptions

    setup do
      @repo = create(:repository)
      @user = create(:user)
      @repo.add_member(@user)
      @issue = create(:issue, repository: @repo)
      @label = create(:label, repository: @repo, name: "bug")
    end

    context "#valid?" do
      test "returns true for the correctly formed label subscription" do
        notifyd_subscriptions = label_subscriptions(@user, @repo, @issue, @label)
        assert Notifyd::LabelSubscription.new(@user, notifyd_subscriptions).valid?
      end

      test "returns false if reason is not 'subscribed'" do
        notifyd_subscriptions = label_subscriptions(@user, @repo, @issue, @label)
        notifyd_subscriptions[0].reason = "invalid"
        refute Notifyd::LabelSubscription.new(@user, notifyd_subscriptions).valid?

        notifyd_subscriptions = label_subscriptions(@user, @repo, @issue, @label)
        notifyd_subscriptions[1].reason = "invalid"
        refute Notifyd::LabelSubscription.new(@user, notifyd_subscriptions).valid?
      end

      test "returns false if custom fields do not contain mandatory fields" do
        assert_no_mandatory_custom_field("repository_id")
        assert_no_mandatory_custom_field("label_id")
        assert_no_mandatory_custom_field("label_name")
        assert_no_mandatory_custom_field("owner_id")
        assert_no_mandatory_custom_field("subject_type")
      end
    end

    context "#ignored?" do
      test "returns false" do
        refute Notifyd::LabelSubscription.new(@user, label_subscriptions(@user, @repo, @issue, @label)).ignored?
      end
    end

    def assert_no_mandatory_custom_field(name)
      (0..1).each do |i|
        notifyd_subscriptions = label_subscriptions(@user, @repo, @issue, @label)
        idx = notifyd_subscriptions[i].custom_fields.find_index { |field| field.name == name }
        notifyd_subscriptions[i].custom_fields.delete_at(idx)
        refute Notifyd::LabelSubscription.new(@user, notifyd_subscriptions).valid?
      end
    end
  end
end
