# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::VssSubscriptionEventProcessingJobTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @enterprise_agreement_number = "12345"
    @email = "email@example.com"
    @subscription_id = SecureRandom.uuid

    @enterprise_agreement = create(:enterprise_agreement, :visual_studio_bundle, agreement_id: @enterprise_agreement_number)
    @business = @enterprise_agreement.business
    @organization = create(:organization, business: @business)
    @user = create(:user)
  end

  context "handles invalid event payloads" do
    test "marks the event as failed when the payload is not valid JSON and notifies failbot" do
      Failbot.expects(:report).once

      event = create(:licensing_vss_subscription_event, payload: "invalid JSON")

      Licensing::VssSubscriptionEventProcessingJob.perform_now(event)

      assert event.failed?
      assert Licensing::BundledLicenseAssignment.none?
    end

    test "marks the event as failed when the payload is missing required data and notifies failbot" do
      Failbot.expects(:report).once

      event = create(:licensing_vss_subscription_event, :assignment, enterprise_agreement_number: @enterprise_agreement_number, email: nil, subscription_id: @subscription_id)

      Licensing::VssSubscriptionEventProcessingJob.perform_now(event)

      assert event.failed?
      assert Licensing::BundledLicenseAssignment.none?
    end

    test "marks the event as processed and does nothing else when the payload is missing the enterprise agreement number" do
      Failbot.expects(:report).never

      event = create(:licensing_vss_subscription_event, :assignment, enterprise_agreement_number: nil, email: @email, subscription_id: @subscription_id)

      Licensing::VssSubscriptionEventProcessingJob.perform_now(event)

      assert event.processed?
      assert Licensing::BundledLicenseAssignment.none?
    end

    test "marks the event as processed and does nothing else if the operation is valid, but isn't 'Assign' or 'Remove'" do
      Failbot.expects(:report).never

      event = create(:licensing_vss_subscription_event, operation: "None", enterprise_agreement_number: @enterprise_agreement_number, email: @email, subscription_id: @subscription_id)

      Licensing::VssSubscriptionEventProcessingJob.perform_now(event)

      assert event.processed?
      assert Licensing::BundledLicenseAssignment.none?
    end
  end

  context "handles a 'Assign' event" do
    test "parses the JSON and assigns the business, if there's a matching enterprise agreement with the given agreement number" do
      Failbot.expects(:report).never

      event = create(:licensing_vss_subscription_event, :assignment, enterprise_agreement_number: @enterprise_agreement_number, email: @email, subscription_id: @subscription_id)

      Licensing::VssSubscriptionEventProcessingJob.perform_now(event)

      assert event.processed?

      assignment = Licensing::BundledLicenseAssignment.find_by!(subscription_id: @subscription_id)
      assert_equal @enterprise_agreement_number, assignment.enterprise_agreement_number
      assert_equal @email, assignment.email
      refute assignment.revoked?
      assert_equal @business, assignment.business
    end

    test "it queues a job to sends a status message to VSS when there's not a matching business" do
      event = create(:licensing_vss_subscription_event, operation: "Assign", subscription_id: @subscription_id)

      assert_changes -> { Licensing::BundledLicenseAssignment.count }, 1 do
        Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
      end

      assert event.processed?
      assert_enqueued_with job: Licensing::SendVssStatusMessageJob, args: [{ assignment: Licensing::BundledLicenseAssignment.last }]
    end

    test "it queues a job to sends a status message to VSS when there is a matching business" do
      event = create(:licensing_vss_subscription_event, operation: "Assign", subscription_id: @subscription_id, enterprise_agreement_number: @enterprise_agreement_number)

      Licensing::VssSubscriptionEventProcessingJob.perform_now(event)

      assert event.processed?
      assert_enqueued_with job: Licensing::SendVssStatusMessageJob, args: [{ assignment: Licensing::BundledLicenseAssignment.last }]
    end

    test "event is processed if there's existing assignments with the same subscription ID but they're all revoked" do
      _existing_revoked_assignment = create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, revoked: true)
      event = create(:licensing_vss_subscription_event, :assignment, enterprise_agreement_number: @enterprise_agreement_number, email: @email, subscription_id: @subscription_id)

      assert_changes -> { Licensing::BundledLicenseAssignment.count }, 1 do
        Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
      end

      assert event.processed?

      new_assignment = Licensing::BundledLicenseAssignment.last
      assert_equal @enterprise_agreement_number, T.must(new_assignment).enterprise_agreement_number
      assert_equal @email, T.must(new_assignment).email
      refute T.must(new_assignment).revoked?
      assert_equal @business, T.must(new_assignment).business
    end

    test "event is processed but no new assignment is created if there's an existing nonrevoked assignment with the same subscription ID and email address" do
      _existing_revoked_assignment = create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, email: @email, revoked: false)
      event = create(:licensing_vss_subscription_event, :assignment, enterprise_agreement_number: @enterprise_agreement_number, email: @email, subscription_id: @subscription_id)

      assert_no_changes -> { Licensing::BundledLicenseAssignment.count }, 0 do
        Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
      end

      assert event.processed?
    end

    test "event fails (and failbot is notified) if there's an existing nonrevoked assignment with the same subscription ID but a different email address" do
      Failbot.expects(:report).once

      _existing_revoked_assignment = create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, email: "different@example.com", revoked: false)
      event = create(:licensing_vss_subscription_event, :assignment, enterprise_agreement_number: @enterprise_agreement_number, email: @email, subscription_id: @subscription_id)

      assert_no_changes -> { Licensing::BundledLicenseAssignment.count }, 0 do
        Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
      end

      assert event.failed?
    end
  end

  context "handles a 'Remove' event" do
    test "event is processed and revokes assignment and does not remove the user from the enterprise account" do
      @organization.add_member(@user)

      event = create(:licensing_vss_subscription_event, :revoke, subscription_id: @subscription_id, email: @email)
      assignment = create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, business: @business, user: @user, email: @email)

      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs(except: Licensing::SendVssStatusMessageJob) do
        # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
        assert_enqueued_with(job: Licensing::SendVssStatusMessageJob, args: [{ assignment: assignment }]) do
          Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
        end
      end

      assert event.reload.processed?
      assert assignment.reload.revoked?
      assert_equal assignment.email, @email
      assert_equal assignment.user_id, @user.id
      assert_includes @organization.member_ids, @user.id
    end

    test "event is processed and revokes assignment if there's an existing unrevoked assignment with the same subscription ID and email even if there's also a revoked assignment for that combination" do
      event = create(:licensing_vss_subscription_event, :revoke, subscription_id: @subscription_id, email: @email)
      _older_revoked_assignment = create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, business: @business, revoked: true, user: @user, email: @email)
      assignment = create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, business: @business, user: @user, email: @email)

      Licensing::VssSubscriptionEventProcessingJob.perform_now(event)

      assert event.reload.processed?
      assert assignment.reload.revoked?
      assert_equal assignment.email, @email
      assert_equal assignment.user_id, @user.id
    end

    test "event is processed and revokes assignment and does not remove the user from the enterprise account if there's an existing unrevoked assignment with the same subscription ID and the event is for an anonymized removal" do
      @organization.add_member(@user)
      anonymized_email = SecureRandom.hex(32)

      event = create(:licensing_vss_subscription_event, :revoke, email: anonymized_email, subscription_id: @subscription_id)
      assignment = create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, business: @business, user: @user, email: @email)

      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs(except: Licensing::SendVssStatusMessageJob) do
        # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
        assert_enqueued_with(job: Licensing::SendVssStatusMessageJob, args: [{ assignment: assignment }]) do
          Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
        end
      end

      assert event.reload.processed?
      assert assignment.reload.revoked?
      assert_equal assignment.email, anonymized_email
      assert_nil assignment.user_id
      assert_includes @organization.member_ids, @user.id
    end

    test "event is processed and revokes assignment if there's an existing unrevoked assignment with the same subscription ID and the event is for an anonymized removal, even if there's a revoked assignment for the subscription ID" do
      anonymized_email = SecureRandom.hex(32)

      event = create(:licensing_vss_subscription_event, :revoke, email: anonymized_email, subscription_id: @subscription_id)
      _older_revoked_assignment = create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, business: @business, revoked: true, user: @user, email: @email)
      assignment = create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, business: @business, user: @user, email: @email)

      assert_enqueued_with(job: Licensing::SendVssStatusMessageJob, args: [{ assignment: assignment }]) do
        Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
      end

      assert event.reload.processed?
      assert assignment.reload.revoked?
      assert_equal assignment.email, anonymized_email
      assert_nil assignment.user_id
    end

    test "event is processed, revoking the assignment, when we get an anonymized removal message without an agreement number" do
      user = create(:user)
      @organization.add_member(user)
      anonymized_email = SecureRandom.hex(32)

      event = create(:licensing_vss_subscription_event, :revoke, email: anonymized_email, subscription_id: @subscription_id, enterprise_agreement_number: nil)
      assignment = create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, business: @business, user: user, email: @email)

      # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      perform_enqueued_jobs(except: Licensing::SendVssStatusMessageJob) do
        # rubocop:enable GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
        assert_enqueued_with(job: Licensing::SendVssStatusMessageJob, args: [{ assignment: assignment }]) do
          Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
        end
      end

      assert event.reload.processed?
      assert assignment.reload.revoked?
      assert_equal assignment.email, anonymized_email
      assert_nil assignment.user_id
      assert_includes @organization.member_ids, user.id
    end

    test "event is processed as a no-op if there're no unrevoked assignments for the subscription ID and email but there is an existing revoked assignment for that combination" do
      assignment = create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, business: @business, user: @user, email: @email, revoked: true)
      event = create(:licensing_vss_subscription_event, :revoke, subscription_id: @subscription_id, email: @email)

      Licensing::VssSubscriptionEventProcessingJob.perform_now(event)

      assert event.reload.processed?
      assert assignment.reload.revoked?
      assert_equal assignment.email, @email
      assert_equal assignment.user_id, @user.id
    end

    test "event is processed as a no-op if there're no assignments (either revoked or unrevoked) for the subscription ID and email combination" do
      create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, business: @business, email: "some.other.email@example.com")
      event = create(:licensing_vss_subscription_event, :revoke, subscription_id: @subscription_id, email: @email)

      Licensing::VssSubscriptionEventProcessingJob.perform_now(event)

      assert event.reload.processed?
    end

    test "event is processed successfully if a business_id is present but the business no longer exists" do
      deleted_business_id = 999_999
      assignment = create(:licensing_bundled_license_assignment, subscription_id: @subscription_id, business_id: deleted_business_id, user: @user, email: @email, assigned_business_at: Time.now)
      event = create(:licensing_vss_subscription_event, :revoke, subscription_id: @subscription_id, email: @email)

      assert_nothing_raised do
        Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
      end

      assert event.reload.processed?
      assert assignment.reload.revoked?
    end
  end

  test "multiple jobs for the same subscription ID can be enqueued at the same time" do
    event1 = create(:licensing_vss_subscription_event, :assignment, email: @email, subscription_id: @subscription_id)
    event2 = create(:licensing_vss_subscription_event, :assignment, email: @email, subscription_id: @subscription_id)

    Licensing::VssSubscriptionEventProcessingJob.perform_later(event1)
    Licensing::VssSubscriptionEventProcessingJob.perform_later(event2)

    assert_enqueued_with job: Licensing::VssSubscriptionEventProcessingJob, args: [event1]
    assert_enqueued_with job: Licensing::VssSubscriptionEventProcessingJob, args: [event2]
  end

  test "multiple jobs for the same subscription ID should not be able to execute at the same time (and the failing job retries)" do
    event = create(:licensing_vss_subscription_event, :assignment, email: @email, subscription_id: @subscription_id)

    # create lock to simulate another job runnning
    GitHub::Restraint.new.lock!("Licensing::VssSubscriptionEventProcessingJob-#{@subscription_id}", 1, 10.seconds) do
      Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
    end

    assert event.reload.unprocessed?
    assert_enqueued_with job: Licensing::VssSubscriptionEventProcessingJob, args: [event]
  end

  test "multiple jobs for different subscription IDs should be able to execute at the same time" do
    other_subscription_id = SecureRandom.uuid
    refute_equal other_subscription_id, @subscription_id
    event = create(:licensing_vss_subscription_event, :assignment, email: @email, subscription_id: other_subscription_id)

    # create lock to simulate another job runnning
    GitHub::Restraint.new.lock!("Licensing::VssSubscriptionEventProcessingJob-#{@subscription_id}", 1, 10.seconds) do
      Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
    end

    assert event.reload.processed?
  end

  test "when a random error is encountered we mark the event as failed but does not retry it" do
    event = create(:licensing_vss_subscription_event, :revoke, email: @email, subscription_id: @subscription_id)

    random_error = Class.new(StandardError)
    Licensing::BundledLicenseAssignment.stubs(:where).raises(random_error)

    assert_raises(random_error) do
      Licensing::VssSubscriptionEventProcessingJob.perform_now(event)
    end

    assert event.reload.failed?
    assert_no_enqueued_jobs only: Licensing::VssSubscriptionEventProcessingJob
  end

  test "retries on a trilogy closed connection error" do
    event = create(:licensing_vss_subscription_event, :revoke, email: @email, subscription_id: @subscription_id)

    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    Licensing::BundledLicenseAssignment.stubs(:where).raises(ActiveRecord::ConnectionFailed)

    Licensing::VssSubscriptionEventProcessingJob.perform_now(event)

    assert_enqueued_with job: Licensing::VssSubscriptionEventProcessingJob, args: [event]
  end
end if GitHub.billing_enabled?
