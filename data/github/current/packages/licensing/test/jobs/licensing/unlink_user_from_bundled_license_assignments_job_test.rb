# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::UnlinkUserFromBundledLicenseAssignmentsJobTest < GitHub::TestCase
  setup do
    @user = create(:user)
    @business1 = create(:business)
    @business2 = create(:business)
    @assignment1 = create(:licensing_bundled_license_assignment, user: @user, business: @business1)
    @assignment2 = create(:licensing_bundled_license_assignment, user: @user, business: @business2)
    @assignment3 = create(:licensing_bundled_license_assignment, user: @user, business: @business2)
  end

  test "unlinks user from bundled license assignments" do
    Licensing::UnlinkUserFromBundledLicenseAssignmentsJob.perform_now(@user.id)

    assert_nil @assignment1.reload.user_id
    assert_nil @assignment2.reload.user_id
    assert_nil @assignment3.reload.user_id
  end unless GitHub.single_business_environment?
end

class Licensing::UnlinkUserFromBundledLicenseAssignmentsJobGHESTest < GitHub::TestCase
  setup do
    @user = create(:user)
    @business = create(:business)
    @assignment = create(:licensing_bundled_license_assignment, user: @user, business: @business)
  end

  test "does not enqueue job in single business environment" do
    assert_no_enqueued_jobs do
      Licensing::UnlinkUserFromBundledLicenseAssignmentsJob.perform_later(@user.id)
    end
  end if GitHub.single_business_environment?
end
