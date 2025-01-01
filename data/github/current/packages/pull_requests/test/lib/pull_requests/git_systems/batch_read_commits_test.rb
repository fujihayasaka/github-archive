# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module GitSystems
    class BatchReadCommitsTest < GitHub::TestCase
      fixtures do
        Spokesd.enable_spokesd

        @owner = create(:user, login: "ari")
        @repo = create(:repository, owner: @owner, from_example: :pull_request_source)

        example_repo_snapshot
      end

      setup do
        example_repo_restore
      end

      test "it can load commits that may or may not exist" do
        service = BatchReadCommits.new

        valid_commit = @repo.ref_to_sha("refs/heads/master")
        invalid_commit = SecureRandom.hex(20)

        service.request(@repo, valid_commit)
        service.request(@repo, invalid_commit)

        assert service.read(@repo, valid_commit)
        refute service.read(@repo, invalid_commit)
      end
    end
  end
end
