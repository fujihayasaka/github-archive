# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroCopilotContentExclusionRepositoryTransferredJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include GitHub::LoggerHelper

  test "it works" do
    config = create(:copilot_content_exclusion_configuration, :repository)
    create(:copilot_content_exclusion_configuration, :repository)

    message = {
      previous_owner: { id: config.organization.id },
      new_owner: { id: 123 }
    }

    assert_logged(
      Body: "Organization relationships updated for transferred repositories",
      "gh.copilot.ignore.updated.count": 1
    ) do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Transferred", queue: "hydro_copilot_content_exclusion_repository_transferred")
    end

    assert_equal 123, config.reload.organization_id
  end

  test "it works but does not touch organzation level configurations" do
    config = create(:copilot_content_exclusion_configuration, :repository)
    create(:copilot_content_exclusion_configuration, :repository)

    org_level_config = create(:copilot_content_exclusion_configuration, :organization, organization: config.organization)

    message = {
      previous_owner: { id: config.organization.id },
      new_owner: { id: 123 }
    }

    assert_logged(
      Body: "Organization relationships updated for transferred repositories",
      "gh.copilot.ignore.updated.count": 1
    ) do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Transferred", queue: "hydro_copilot_content_exclusion_repository_transferred")
    end

    assert_equal 123, config.reload.organization_id

    previous_id = org_level_config.organization.id

    # org level configs with the same previous owner should not change
    assert_equal previous_id, org_level_config.reload.organization_id
  end
end
