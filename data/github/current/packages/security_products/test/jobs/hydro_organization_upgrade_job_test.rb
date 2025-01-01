# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroOrganizationUpgradeJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  fixtures do
    # referencing the job class forces it to load, so it can be looked up by queue name
    @queue = HydroOrganizationUpgradeJob.queue_name
    @schema = "github.enterprise_account.v0.OrganizationUpgrade"

    @admin = create :user
    @org = create :organization, plan: GitHub::Plan.business_plus
    @member = create(:user)
    @org.add_member(@member)
    @business = create :business, organizations: [@org], owners: [@admin]
  end

  test "kicks off organization upgrade job", skip_enterprise: true do
    message = {
      organization: Hydro::EntitySerializer.organization(@org),
      enterprise: Hydro::EntitySerializer.business(@business),
      actor: Hydro::EntitySerializer.user(@admin),
      billing_type: @business.billing_type,
      status: :DIRECT_UPGRADED
    }

    assert_enqueued_jobs 1, only: OrganizationUpgradeJob do
      perform_hydro_message_job(message, schema: @schema, queue: @queue)
    end
  end
end
