# typed: true
# frozen_string_literal: true

require "test_helper"

module CodeScanning
  class HydroRepositoryDeletedJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    fixtures do
      @queue = HydroRepositoryDeletedJob.queue_name
      @schema = "github.repositories.v1.Deleted"

      @repo = create(:repository, :minimal)
    end

    test "feature toggle hydro messages are published" do
      # Stub this method because it makes a turboscan call to check if code scanning is enabled
      Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(true)

      message = {
        repository_id: @repo.id
      }

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      assert_hydro_messages(count: 1, schema: "code_scanning.v0.CodeScanningFeatureToggled")
    end
  end
end
