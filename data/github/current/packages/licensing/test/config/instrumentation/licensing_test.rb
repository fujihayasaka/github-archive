# typed: true
# frozen_string_literal: true

require "test_helper"

class LicensingSubscriptionsTest < GitHub::TestCase
  include HydroTestHelpers

  test "user.destroy" do
    user = create(:user)
    assert_enqueued_with(job: Licensing::UnlinkUserFromBundledLicenseAssignmentsJob) do
      GlobalInstrumenter.instrument("user.destroy", user: user)
    end
  end unless GitHub.single_business_environment?
end
