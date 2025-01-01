# typed: true
# frozen_string_literal: true

require "test_helper"

module AdvancedSecurity
  class HydroRepositoryArchivedStatusChangedJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    fixtures do
      @queue = HydroRepositoryArchivedStatusChangedJob.queue_name
      @schema = "github.v1.RepositoryArchivedStatusChanged"

      @repo = create(:repository, :minimal)
    end

    test "feature toggle hydro messages are published" do
      message = {
        repository_id: @repo.id
      }

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end

      assert_hydro_messages(count: 1, schema: "github.security_center.v0.AdvancedSecurityToggled")
    end
  end
end
