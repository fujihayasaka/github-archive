# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    class BatchRefUpdatesJobTest < GitHub::TestCase
      fixtures do
        @user = create :user, login: "whimsycat"
        @repo = create :private_repository, owner: @user, name: "Whimsy", from_example: :pull_request_fork
      end

      test "it gracefully retries on repo repairing state" do
        Repository.any_instance.stubs(:repairing?).returns(true)

        assert_performed_jobs(9, only: BatchRefUpdatesJob) do
          BatchRefUpdatesJob.perform_now(@repo)
        end
      end
    end
  end
end
