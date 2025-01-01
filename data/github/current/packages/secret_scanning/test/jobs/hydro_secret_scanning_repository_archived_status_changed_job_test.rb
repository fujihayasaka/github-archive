# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroSecretScanningRepositoryArchivedStatusChangedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  setup do
    @queue = "hydro_secret_scanning_repository_archived_status_changed"
    @schema = "github.v1.RepositoryArchivedStatusChanged"
    @repo = create(:repository)
  end

  test "feature toggle hydro messages are published" do
    message = {
      repository_id: @repo.id
    }

    perform_hydro_message_job(message, schema: @schema, queue: @queue)

    assert_hydro_messages(count: 1, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled")
    assert_hydro_messages(count: 1, schema: "github.secret_scanning.v1.SecretScanningPushProtectionFeatureToggled")
  end

  test "feature toggle hydro messages are not published if repo can't be found" do
    message = {
      repository_id: 0
    }

    perform_hydro_message_job(message, schema: @schema, queue: @queue)

    refute_hydro_messages(schema: "github.secret_scanning.v1.SecretScanningFeatureToggled")
    refute_hydro_messages(schema: "github.secret_scanning.v1.SecretScanningPushProtectionFeatureToggled")
  end
end
