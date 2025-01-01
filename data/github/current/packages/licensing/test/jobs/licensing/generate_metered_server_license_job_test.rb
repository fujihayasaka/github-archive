# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::GenerateMeteredServerLicenseJobTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @business = create(:business)
    @ghes_license = create(:licensing_ghes_license, business: @business, seats: 0)
  end

  test "self.job_id" do
    license_id = 123
    assert_equal "metered-server-license-#{license_id}", Licensing::GenerateMeteredServerLicenseJob.job_id(license_id)
  end

  test "self.status" do
    Licensing::GhesLicense.any_instance.stubs(:generate_server_license_key)
    Licensing::GenerateMeteredServerLicenseJob.perform_now(@ghes_license.id)

    status = Licensing::GenerateMeteredServerLicenseJob.status(@ghes_license.id)
    assert_equal Licensing::GenerateMeteredServerLicenseJob.job_id(@ghes_license.id), status&.id
    assert_equal "success", status&.state
  end

  test "generates a server license key" do
    Licensing::GhesLicense.any_instance.expects(:generate_server_license_key).once

    Licensing::GenerateMeteredServerLicenseJob.perform_now(@ghes_license.id)
  end
end
