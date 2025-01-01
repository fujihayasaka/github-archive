# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroCopilotContentExclusionRepositoryDeletedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include GitHub::LoggerHelper

  test "it works" do
    config = create(:copilot_content_exclusion_configuration, :repository)
    create(:copilot_content_exclusion_configuration, :repository)

    assert_equal Copilot::ContentExclusionConfiguration.count, 2
    assert config.resource.is_a?(::Repository)

    repository_id = config.resource.id

    message = {
      repository_id:
    }

    assert_logged(
      Body: "Purged content exclusion repo level configuration",
      "gh.copilot.ignore.deleted.count": 1
    ) do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Deleted", queue: "hydro_copilot_content_exclusion_repository_deleted")
    end

    assert_equal Copilot::ContentExclusionConfiguration.count, 1
    refute Copilot::ContentExclusionConfiguration.for_repository_ids([repository_id]).exists?
  end
end
