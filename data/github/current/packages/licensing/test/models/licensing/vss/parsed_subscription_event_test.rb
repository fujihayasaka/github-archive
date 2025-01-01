# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::Vss::ParsedSubscriptionEventTest < GitHub::TestCase
  context ".valid?" do
    test "true if the input is valid JSON and all of the required fields are present" do
      event = build(:licensing_vss_subscription_event)

      assert Licensing::Vss::ParsedSubscriptionEvent.new(event.payload).valid?
    end

    test "false if the input is valid JSON but some of the required fields are blank" do
      event = build(:licensing_vss_subscription_event, email: "")

      refute Licensing::Vss::ParsedSubscriptionEvent.new(event.payload).valid?
    end

    test "false if the input is valid JSON but some of the required fields are missing" do
      data = JSON.parse(build(:licensing_vss_subscription_event, operation: "impossible").payload)
      data.delete("Identity")

      refute Licensing::Vss::ParsedSubscriptionEvent.new(data.to_json).valid?
    end

    test "false if the input is valid JSON and all of the required fields are present, but the operation field is invalid" do
      event = build(:licensing_vss_subscription_event, operation: "impossible")

      refute Licensing::Vss::ParsedSubscriptionEvent.new(event.payload).valid?
    end

    test "false if the input is valid JSON, but not a hash/object" do
      refute Licensing::Vss::ParsedSubscriptionEvent.new(%w[sneaky error].to_json).valid?
    end

    test "false if the input is invalid JSON" do
      refute Licensing::Vss::ParsedSubscriptionEvent.new("not JSON").valid?
    end
  end

  context "#enterprise_agreement_number" do
    test "the enterprise agreement number from the JSON" do
      event = build(:licensing_vss_subscription_event, enterprise_agreement_number: "123456")

      assert_equal "123456", Licensing::Vss::ParsedSubscriptionEvent.new(event.payload).enterprise_agreement_number
    end
  end

  context "#email" do
    test "the email from the JSON" do
      event = build(:licensing_vss_subscription_event, email: "example@example.com")

      assert_equal "example@example.com", Licensing::Vss::ParsedSubscriptionEvent.new(event.payload).email
    end
  end

  context "#subscription_id" do
    test "the subscription ID from the JSON" do
      event = build(:licensing_vss_subscription_event, subscription_id: "aaa-bbb-ccc")

      assert_equal "aaa-bbb-ccc", Licensing::Vss::ParsedSubscriptionEvent.new(event.payload).subscription_id
    end
  end

  context "#operation" do
    test "the subscription ID from the JSON" do
      event = build(:licensing_vss_subscription_event, operation: "Assign")

      assert_equal "Assign", Licensing::Vss::ParsedSubscriptionEvent.new(event.payload).operation
    end
  end

  context "#new_assignment?" do
    test "true if the operation is 'Assign'" do
      event = build(:licensing_vss_subscription_event, operation: "Assign")

      assert Licensing::Vss::ParsedSubscriptionEvent.new(event.payload).new_assignment?
    end

    test "false if the operation is anything else" do
      event = build(:licensing_vss_subscription_event, operation: "NotAssign")

      refute Licensing::Vss::ParsedSubscriptionEvent.new(event.payload).new_assignment?
    end
  end

  context "#remove_assignment?" do
    test "true if the operation is 'Remove'" do
      event = build(:licensing_vss_subscription_event, operation: "Remove")

      assert Licensing::Vss::ParsedSubscriptionEvent.new(event.payload).remove_assignment?
    end

    test "true if the operation is 'Unassign'" do
      event = build(:licensing_vss_subscription_event, operation: "Unassign")

      assert Licensing::Vss::ParsedSubscriptionEvent.new(event.payload).remove_assignment?
    end

    test "false if the operation is anything else" do
      event = build(:licensing_vss_subscription_event, operation: "NotRemove")

      refute Licensing::Vss::ParsedSubscriptionEvent.new(event.payload).remove_assignment?
    end
  end
end if GitHub.billing_enabled?
