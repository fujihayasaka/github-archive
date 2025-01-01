# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroSecretScanningRepositoryTransferredJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  setup do
    @queue = "hydro_secret_scanning_repository_transferred"
    @schema = "github.repositories.v1.Transferred"
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
end
