# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroEnterpriseAdvancedSecurityLicenseToggledJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  fixtures do
    # referencing the job class forces it to load, so it can be looked up by queue name
    @queue = HydroEnterpriseAdvancedSecurityLicenseToggledJob.queue_name
    @schema = "github.security_center.v0.EnterpriseAdvancedSecurityLicenseToggled"

    @admin = create :user
    @org = create :organization, plan: GitHub::Plan.business_plus
    @member = create(:user)
    @org.add_member(@member)
    @business = create :business, organizations: [@org], owners: [@admin]
  end

  test "kicks off organization license changed job" do
    message = {
      business_id: @business.id,
      enabled: true
    }

    assert_enqueued_jobs 1, only: EnterpriseAdvancedSecurityLicenseToggledJob do
      perform_hydro_message_job(message, schema: @schema, queue: @queue)
    end
  end
end
