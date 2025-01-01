# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroOrganizationAdvancedSecurityLicenseToggledJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  fixtures do
    # referencing the job class forces it to load, so it can be looked up by queue name
    @queue = HydroOrganizationAdvancedSecurityLicenseToggledJob.queue_name
    @schema = "github.security_center.v0.OrganizationAdvancedSecurityLicenseToggled"

    @admin = create :user
    @org = create :organization, plan: GitHub::Plan.business_plus
    @member = create(:user)
    @org.add_member(@member)
    @business = create :business, organizations: [@org], owners: [@admin]
  end

  test "kicks off organization license changed job" do
    message = {
      organization_id: @org.id,
      enabled: true
    }

    assert_enqueued_jobs 1, only: OrganizationAdvancedSecurityLicenseToggledJob do
      perform_hydro_message_job(message, schema: @schema, queue: @queue)
    end
  end
end
