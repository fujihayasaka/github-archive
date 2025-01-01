# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationLicensingTest < GitHub::TestCase
  include HydroTestHelpers

  if GitHub.billing_enabled?
    test "publishes license snapshot message when a member is added" do
      business = create(:business)
      organization = create(:organization, business: business)
      user = create(:user)

      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        organization.add_member(user)
      end

      assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")
    end

    test "does not publish a license snapshot message when a member is added if the organization isn't business owned" do
      organization = create(:organization)
      user = create(:user)

      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        organization.add_member(user)
      end

      assert_hydro_messages(count: 0, schema: "github.billing.v0.LicenseSnapshot")
    end
  else
    test "does not publish a license snapshot message when a member is added" do
      business = create(:business)
      organization = create(:organization, business: business)
      user = create(:user)

      reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        organization.add_member(user)
      end

      assert_hydro_messages(count: 0, schema: "github.billing.v0.LicenseSnapshot")
    end
  end
end
