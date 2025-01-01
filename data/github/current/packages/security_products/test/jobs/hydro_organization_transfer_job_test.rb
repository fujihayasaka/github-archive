# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroOrganizationTransferJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  fixtures do
    # referencing the job class forces it to load, so it can be looked up by queue name
    @queue = HydroOrganizationTransferJob.queue_name
    @schema = "github.enterprise_account.v0.OrganizationTransfer"

    @admin = create :user
    @org = create :organization, plan: GitHub::Plan.business_plus
    @member = create(:user)
    @org.add_member(@member)
    @business = create :business, organizations: [@org], owners: [@admin]
  end

  test "kicks off organization transfer job", skip_enterprise: true do
    message = {
      organization: Hydro::EntitySerializer.organization(@org),
      source_enterprise: Hydro::EntitySerializer.business(@business),
      destination_enterprise: Hydro::EntitySerializer.business(@business),
      actor: Hydro::EntitySerializer.user(@admin),
      completed_at: Time.now,
      site_admin_transfer: false,
  }

    assert_enqueued_jobs 1, only: OrganizationTransferJob do
      perform_hydro_message_job(message, schema: @schema, queue: @queue)
    end
  end
end
