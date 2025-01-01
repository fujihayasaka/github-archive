# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module GitSystems
    class BatchReadRefsTest < GitHub::TestCase
      fixtures do
        Spokesd.enable_spokesd

        @owner = create(:user, login: "ari")
        @repo = create(:repository, owner: @owner, from_example: :pull_request_source)

        example_repo_snapshot
      end

      setup do
        example_repo_restore
      end

      test "it can load refs that may or may not exist" do
        service = BatchReadRefs.new

        valid_ref_name = "refs/heads/master"
        missing_ref_name = "refs/heads/#{SecureRandom.hex(128)}"

        service.request(@repo, valid_ref_name)
        service.request(@repo, missing_ref_name)
        assert service.read(@repo, valid_ref_name)
        refute service.read(@repo, missing_ref_name)
      end
    end
  end
end
