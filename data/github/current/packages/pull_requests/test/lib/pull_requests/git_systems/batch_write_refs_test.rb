# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module GitSystems
    class BatchWriteRefsTest < GitHub::TestCase
      fixtures do
        Spokesd.enable_spokesd

        @owner = create(:user, login: "ari")
        @repo = create(:repository, owner: @owner, from_example: :pull_request_source)

        example_repo_snapshot
      end

      setup do
        example_repo_restore

        @commit = @repo.commits.create({ message: "New commit", committer: @owner }, branch.sha) do |files|
          files.add "hello.txt", "Hello World!"
        end
      end

      test "it allows branch creation" do
        service = BatchWriteRefs::Service.new(repository: @repo, actor: @owner)
        service.add(ref_name: "refs/pull/1/head", before_oid: GitHub::NULL_OID, after_oid: @commit.oid)

        result = service.call

        assert_equal 1, result.requests.length
        fail unless request = result.requests.first

        # It should've been successful.
        assert_instance_of BatchWriteRefs::Outcome::Success, request.outcome

        ref = @repo.all_refs.find("refs/pull/1/head")

        refute_nil ref
        assert_equal @commit.oid, ref.sha
      end

      test "it allows branch updating without declaring a before" do
        service = BatchWriteRefs::Service.new(repository: @repo, actor: @owner)
        service.add(ref_name: branch.qualified_name, before_oid: nil, after_oid: @commit.oid)

        result = service.call

        assert_equal 1, result.requests.length
        fail unless request = result.requests.first

        # It should've been successful.
        assert_instance_of BatchWriteRefs::Outcome::Success, request.outcome

        ref = @repo.reload.all_refs.find(branch.qualified_name)
        refute_nil ref
        assert_equal @commit.oid, ref.sha
      end

      test "the ref update fails if there is an unreachable object in the update set" do
        service = BatchWriteRefs::Service.new(repository: @repo, actor: @owner)
        service.add(ref_name: branch.qualified_name, before_oid: nil, after_oid: SecureRandom.hex(16))

        result = service.call

        assert_equal 1, result.requests.length
        fail unless request = result.requests.first

        outcome = request.outcome
        fail unless outcome.is_a?(BatchWriteRefs::Outcome::Failed)

        # Should bundle the exception in the payload.
        assert_equal outcome.reason, BatchWriteRefs::FailureReason::RefUpdateFailed
        refute_nil outcome.exception
      end

      private

      sig { returns(Git::Ref) }
      def branch
        @repo.refs.find("refs/heads/master")
      end
    end
  end
end
