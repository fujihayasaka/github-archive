# typed: true
# frozen_string_literal: true

require "test_helper"

module CodeScanning
  class HydroRepositoryEnablementProxyJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    fixtures do
      @queue = HydroRepositoryEnablementProxyJob.queue_name
      @schema = "hydro.schemas.code_scanning.v0.EnablementEvent"

      @repo = create(:repository)
    end

    test "feature toggle hydro messages are published" do
      Repository.any_instance.expects(:turboscan_considers_code_scanning_enabled?).never

      message = {
        repository_id: @repo.id,
        enabled: true
      }

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      assert_hydro_messages(count: 1, schema: "code_scanning.v0.CodeScanningFeatureToggled")
    end
  end
end
