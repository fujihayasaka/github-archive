# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroSecretScanningRepositoryCreatedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  setup do
    @queue = "hydro_secret_scanning_repository_created"
    @schema = "github.repositories.v1.Created"

    @admin = create(:user)
    @org = create(:business_plus_organization, admin: @admin)
    @repo = create(:repository, :minimal, owner: @org)
  end

  test "feature toggle hydro messages are published" do
    message = {
      repository_id: @repo.id,
      repository: Hydro::EntitySerializer.repository(@repo)
    }

    perform_hydro_message_job(message, schema: @schema, queue: @queue)

    assert_hydro_messages(count: 1, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled")
    assert_hydro_messages(count: 1, schema: "github.secret_scanning.v1.SecretScanningPushProtectionFeatureToggled")
  end
end
