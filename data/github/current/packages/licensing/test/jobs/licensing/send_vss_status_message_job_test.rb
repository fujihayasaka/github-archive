# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::SendVssStatusMessageJobTest < GitHub::TestCase
  fixtures do
    @assignment = create(:licensing_bundled_license_assignment, business: nil, user: nil, updated_at: 45.seconds.ago)
    @business = create(:business)
    @user = create(:user)
  end

  test "sends desired status message for assignment based on the state of the object" do
    expected_message = {
      subscriptionGuid: @assignment.subscription_id,
      state: "pendingAccountSetup",
      updatedDate: @assignment.updated_at,
      enterpriseAgreementNumber: @assignment.enterprise_agreement_number,
      email: @assignment.email
    }.to_json

    GitHub::AzureServiceBus::QueueClient.any_instance.expects(:send_message).with(expected_message)

    Licensing::SendVssStatusMessageJob.perform_now(assignment: @assignment)
  end

  test "overrides passed in status message if the derived status has a higher priority" do
    travel_to(1.minute.ago) do
      @assignment.update!(business: @business, user: @user)
    end

    expected_message = {
      subscriptionGuid: @assignment.subscription_id,
      state: "linkedToUser",
      updatedDate: @assignment.updated_at,
      enterpriseAgreementNumber: @assignment.enterprise_agreement_number,
      email: @assignment.email
    }.to_json

    GitHub::AzureServiceBus::QueueClient.any_instance.expects(:send_message).with(expected_message)

    Licensing::SendVssStatusMessageJob.perform_now(assignment: @assignment, event_type: :invited_to_repo)
  end

  test "logs a message to the audit log when the status has been sent" do
    events = subscribe "bundled_license_assignment.status_message_sent"
    expected_payload = {
      bundled_license_assignment_id: @assignment.id,
      email: @assignment.email,
      enterprise_agreement_number: @assignment.enterprise_agreement_number,
      subscription_id: @assignment.subscription_id,
      status_sent: :pending_account_setup
    }

    GitHub::AzureServiceBus::QueueClient.any_instance.expects(:send_message)

    Licensing::SendVssStatusMessageJob.perform_now(assignment: @assignment)

    assert_equal 1, events.count
    assert_equal expected_payload, events.first.payload
  end

  test "does not allow multiple jobs to be enqueued for the same assignment at the same time" do
    Licensing::SendVssStatusMessageJob.perform_later(assignment: @assignment)
    Licensing::SendVssStatusMessageJob.perform_later(assignment: @assignment)

    assert_enqueued_jobs 1, only: Licensing::SendVssStatusMessageJob
  end if GitHub.billing_enabled?

  test "delays sending the status message at least 30 seconds to let any other updates complete to avoid sending multiple different statuses to VSS" do
    freeze_time do
      @assignment.update_columns(updated_at: 10.seconds.ago)

      GitHub::AzureServiceBus::QueueClient.any_instance.expects(:send_message).never
      Licensing::SendVssStatusMessageJob.perform_later(assignment: @assignment)

      perform_enqueued_jobs # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      assert_enqueued_with(
        job: Licensing::SendVssStatusMessageJob,
        args: [{ assignment: @assignment, event_type: nil }],
        at: @assignment.updated_at + 30.seconds
      )
    end
  end if GitHub.billing_enabled?
end
