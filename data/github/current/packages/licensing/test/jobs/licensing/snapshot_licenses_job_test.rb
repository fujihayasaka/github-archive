# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::SnapshotLicensesJobTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @business = create(:business)
  end

  test "publishes a license snapshot event for the business" do
    Licensing::SnapshotLicensesJob.perform_now(@business)

    assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")
  end

  if TestEnv.test_in_multitenancy_mode?
    test "resolves tenant context" do
      GitHub::CurrentTenant.remove
      assert_nil GitHub::CurrentTenant.get

      Licensing::SnapshotLicensesJob.perform_now(@business)

      assert_equal @business, GitHub::CurrentTenant.get
    end

    test "does not raise an error if tenant resolved as nil" do
      GitHub::CurrentTenant.remove
      assert_nil GitHub::CurrentTenant.get

      Licensing::SnapshotLicensesJob.perform_now(nil)

      assert_nil GitHub::CurrentTenant.get
    end
  end
end if GitHub.billing_enabled?
