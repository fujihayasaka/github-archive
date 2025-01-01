# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroBusinessUpdateLicenseUsageOnRepoChangeJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @schema = "github.repositories.v1.VisibilityChanged"
    @queue = "hydro_business_update_license_usage_on_repo_change"

    @org = create(:organization)
    @business = create(:business, organizations: [@org])
    @repo = create(:repository, owner: @org)
  end

  test "schedules a license update job when repo belongs to business" do
    Business.any_instance.expects(:update_license_usage).once

    message = { repository_id: @repo.id }
    perform_hydro_message_job(message, schema: @schema, queue: @queue)
  end
end
