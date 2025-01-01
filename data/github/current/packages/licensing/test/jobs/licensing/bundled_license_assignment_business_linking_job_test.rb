# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::BundledLicenseAssignmentBusinessLinkingJobTest < GitHub::TestCase
  fixtures do
    @agreement_number = "123454321"
    @prev_business = create(:business)
    @business = create(:business)
    @enterprise_agreement = create(:enterprise_agreement, business: @business, agreement_id: @agreement_number)
  end

  test "sets the business ID on bundled licensing assignments with matching enterprise agreement numbers, sends a VSS status message, and links users" do
    assignment = create(:licensing_bundled_license_assignment, business: nil, enterprise_agreement_number: @agreement_number)

    freeze_time do
      assert_enqueued_with(job: Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob, args: [{ assignment: assignment }]) do
        assert_enqueued_with(job: Licensing::SendVssStatusMessageJob, args: [{ assignment: assignment }]) do
          Licensing::BundledLicenseAssignmentBusinessLinkingJob.perform_now(@enterprise_agreement)
        end
      end

      assert_equal @business, assignment.reload.business
      assert_equal Time.current, assignment.assigned_business_at
    end
  end

  test "updates the business ID on bundled licensing assignments with matching enterprise agreement numbers, sends a VSS status message, and links users" do
    freeze_time do
      assignment = create(:licensing_bundled_license_assignment, business: @prev_business, assigned_business_at: Time.current - 1.day, enterprise_agreement_number: @agreement_number)

      assert_enqueued_with(job: Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob, args: [{ assignment: assignment }]) do
        assert_enqueued_with(job: Licensing::SendVssStatusMessageJob, args: [{ assignment: assignment }]) do
          Licensing::BundledLicenseAssignmentBusinessLinkingJob.perform_now(@enterprise_agreement)
        end
      end

      assert_equal @business, assignment.reload.business
      assert_equal Time.current, assignment.assigned_business_at
    end
  end

  test "does not update unrelated assignments" do
    random_assignment = create(:licensing_bundled_license_assignment, business: nil, enterprise_agreement_number: "something different")

    freeze_time do
      assert_no_enqueued_jobs do
        Licensing::BundledLicenseAssignmentBusinessLinkingJob.perform_now(@enterprise_agreement)
      end

      assert_nil random_assignment.reload.business
      assert_nil random_assignment.assigned_business_at
    end
  end

  test "does not update revoked assignments" do
    revoked_assignment = create(:licensing_bundled_license_assignment, business: nil, enterprise_agreement_number: @agreement_number, revoked: true)

    freeze_time do
      assert_no_enqueued_jobs do
        Licensing::BundledLicenseAssignmentBusinessLinkingJob.perform_now(@enterprise_agreement)
      end

      assert_nil revoked_assignment.reload.business
      assert_nil revoked_assignment.assigned_business_at
    end
  end
end if GitHub.billing_enabled?
