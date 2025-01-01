# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJobTest < GitHub::TestCase
  fixtures do
    @verified_user = create(:verified_user)
    @unverified_user = create(:user)
    @business = create(:business)
  end

  test "sets user_id on bundled_license_assignment if business exist and user is verified" do
    assignment = create(:licensing_bundled_license_assignment, business: @business, email: @verified_user.email)

    assert_nil assignment.user_id

    Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob.perform_now(business: @business, user: @verified_user)

    assert_equal assignment.reload.user_id, @verified_user.id
  end

  test "sets user_id on bundled_license_assignment if business exist with the passed (unverified) email" do
    assignment = create(:licensing_bundled_license_assignment, business: @business, email: @unverified_user.email)

    assert_nil assignment.user_id

    Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob.perform_now(
      business: @business, user: @unverified_user, emails: [@unverified_user.email]
    )

    assert_equal assignment.reload.user_id, @unverified_user.id
  end

  test "sets user_id on all bundled_license_assignment matching (unverified) emails passed to the job" do
    email1 = create(:user_email, user: @verified_user)
    email2 = create(:user_email, :verified, user: @verified_user)
    email3 = create(:user_email)
    assignment1 = create(:licensing_bundled_license_assignment, business: @business, email: email1.email)
    assignment2 = create(:licensing_bundled_license_assignment, business: @business, email: email2.email)
    assignment3 = create(:licensing_bundled_license_assignment, business: @business, email: email3.email)

    assert_nil assignment1.user_id
    assert_nil assignment2.user_id
    assert_nil assignment3.user_id

    Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob.perform_now(
      business: @business, user: @verified_user, emails: [email1.email, email2.email, email3.email]
    )

    assert_equal assignment1.reload.user_id, @verified_user.id
    assert_equal assignment2.reload.user_id, @verified_user.id
    assert_equal assignment3.reload.user_id, @verified_user.id
  end

  test "doesn't update user_id if user already exists" do
    assignment = create(
      :licensing_bundled_license_assignment,
      email: @verified_user.email, user: @verified_user, business: @business
    )

    assignment.expects(:update).never

    Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob.perform_now(business: @business, user: @verified_user)
  end

  test "doesn't update user_id if business doesn't exist" do
    assignment = create(:licensing_bundled_license_assignment, email: @verified_user.email)

    assignment.expects(:update).never

    Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob.perform_now(business: @business, user: @verified_user)
  end

  unless GitHub.single_business_environment?
    test "enqueues license attributer cache job" do
      assignment = create(:licensing_bundled_license_assignment, business: @business, email: @verified_user.email)

      assert_nil assignment.user_id

      assert_enqueued_jobs(1, only: [BusinessUpdateLicenseUsageJob]) do
        Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob.perform_now(business: @business, user: @verified_user)
      end
    end
  end
end if GitHub.billing_enabled?
