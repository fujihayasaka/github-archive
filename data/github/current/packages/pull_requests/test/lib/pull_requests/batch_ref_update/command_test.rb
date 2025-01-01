# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "./helpers"

module PullRequests
  module BatchRefUpdate
    class CommandTest < GitHub::TestCase
      include Helpers

      fixtures do
        Spokesd.enable_spokesd

        @owner = create(:user, login: "ari")
        @repo = create(:repository, owner: @owner, from_example: :pull_request_source)

        example_repo_snapshot
      end

      setup do
        example_repo_restore
      end

      context "#update_refs!" do
        test "it can perform valid ref updates" do
          command = Command.new(repository: @repo)

          # Prepare git state.
          base_ref = @repo.refs.find("refs/heads/master")
          before_sha = base_ref.sha
          head_ref = "refs/pull/1/head"
          after_sha = @repo.commits.create({ message: "New commit", committer: @owner }, before_sha) do |files|
            files.add "hello.txt", "Hello World!"
          end.sha

          @repo.refs.create(head_ref, before_sha, @owner)

          request = build_eligible_request(ref_name: head_ref, before_sha: nil, after_sha:)

          # Perform the ref update that should result in a created branch.
          result = command.update_refs!(requests: [request])

          # It should not have errored.
          assert_nil result.exception

          # New branch should exist.
          refute_nil @repo.all_refs.find(head_ref)&.sha

          # It should have been tracked as a success.
          assert_instance_of GitSystems::BatchWriteRefs::Outcome::Success, result.requests[request]
        end
      end
    end
  end
end
