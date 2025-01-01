# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotTest < GitHub::TestCase
  context ".copilot_object" do
    test "returns a Copilot::User for a User" do
      user = create(:user)
      assert_instance_of Copilot::User, Copilot.copilot_object(user)
    end

    test "returns a Copilot::Organization for an Organization" do
      org = create(:organization)
      assert_instance_of Copilot::Organization, Copilot.copilot_object(org)
    end

    test "returns a Copilot::Business for a Business" do
      business = create(:business)
      assert_instance_of Copilot::Business, Copilot.copilot_object(business)
    end
  end

  context "copilot_feature_enabled_seat factory has all the features enabled" do
    test "it has them all" do
      seat = create(:copilot_feature_enabled_seat)
      organization = seat.seat_assignment.owner
      copilot_org = Copilot::Organization.new(organization)

      assert copilot_org.dotcom_chat_enabled?
      assert copilot_org.custom_models_enabled?
      assert copilot_org.copilot_for_dotcom_enabled?
      assert copilot_org.cli_enabled?

      business = organization.business
      copilot_business = Copilot::Business.new(business)

      assert copilot_business.dotcom_chat_enabled?
      assert copilot_business.custom_models_enabled?
      assert copilot_business.copilot_for_dotcom_enabled?
      assert copilot_business.cli_enabled?
    end
  end
end if GitHub.copilot_enabled?
