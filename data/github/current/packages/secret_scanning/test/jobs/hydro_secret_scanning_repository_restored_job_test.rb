# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroSecretScanningRepositoryRestoredJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  setup do
    @queue = "hydro_secret_scanning_repository_restored"
    @schema = "github.repositories.v2.Restored"
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
