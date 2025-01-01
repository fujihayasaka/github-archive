# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::Vss::StatusMessageTest < GitHub::TestCase
  fixtures do
    @bundled_licence_assignement = create(:licensing_bundled_license_assignment, updated_at: 2.hours.ago)
  end

  context ".initialize" do
    test "creates valid Message object from BundledLicenceAssignment" do
      message = Licensing::Vss::StatusMessage.new(event_type: :assignment_linked_to_user,
                                              assignment: @bundled_licence_assignement)

      expected_body = {
        subscriptionGuid: @bundled_licence_assignement.subscription_id,
        state: "linkedToUser",
        updatedDate: @bundled_licence_assignement.updated_at,
        enterpriseAgreementNumber: @bundled_licence_assignement.enterprise_agreement_number,
        email: @bundled_licence_assignement.email
      }

      assert_equal expected_body, message.body
    end

    test "raises error if bad state is passed in" do
      assert_raises ArgumentError do
        Licensing::Vss::StatusMessage.new(event_type: "bad_state",
                                      assignment: @bundled_licence_assignement)
      end
    end
  end
end
