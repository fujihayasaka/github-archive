# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module BatchRefUpdate
    class LoaderTest < GitHub::TestCase
      fixtures do
        Spokesd.enable_spokesd

        @owner = create(:user, login: "ari")
        @repo = create(:repository, owner: @owner, from_example: :pull_request_source)

        example_repo_snapshot
      end

      setup do
        example_repo_restore
      end

      test "an empty database yields no requests" do
        loader = Loader.new(repository: @repo, ref_update_requests: [])
        assert_equal [], loader.requests
      end

      context "#requests" do
        test "returns a collection of eligible PullRequests::BatchRefUpdate::Request objects from valid data" do
          # Prepare git state.
          before_ref = @repo.refs.find("refs/heads/master")
          before_sha = before_ref.sha
          ref_name = "refs/pull/1/head"
          after_sha = @repo.commits.create({ message: "New commit", committer: @owner }, before_sha) do |files|
            files.add "hello.txt", "Hello World!"
          end.sha

          @repo.refs.create(ref_name, before_sha, @owner)

          ref_update_request = FakeDatabaseRecord.new(
            repository_id: @repo.id,
            pull_request_id: 1,
            ref_name:,
            before_sha:,
            after_sha:,
          )
          loader = Loader.new(repository: @repo, ref_update_requests: [ref_update_request])
          requests = loader.requests

          assert_equal 1, requests.length
          fail unless request = requests.first
          fail unless request.is_a?(Request::Eligible)

          assert_equal 1, request.pull_request_id
          assert_equal ref_name, request.ref_name
          assert_equal before_sha, request.before_sha
          assert_equal after_sha, request.after_sha
        end

        test "returns eligible request when before_sha is not present" do
          # need a valid sha from git repo
          after_sha = @repo.ref_to_sha("refs/heads/master")

          ref_update_request = FakeDatabaseRecord.new(
            repository_id: @repo.id,
            pull_request_id: 1,
            ref_name: "refs/pull/1/head",
            after_sha:,
          )
          loader = Loader.new(repository: @repo, ref_update_requests: [ref_update_request])
          requests = loader.requests

          assert_equal 1, requests.length
          fail unless request = requests.first
          fail unless request.is_a?(Request::Eligible)

          assert_equal 1, request.pull_request_id
          assert_equal "refs/pull/1/head", request.ref_name
          assert_nil request.before_sha
          assert_equal after_sha, request.after_sha
        end

        test "returns eligible request for create requests" do
          # sha for create requests
          before_sha = GitHub::NULL_OID
          # need a valid sha from git repo
          after_sha = @repo.ref_to_sha("refs/heads/master")

          ref_update_request = FakeDatabaseRecord.new(
            repository_id: @repo.id,
            pull_request_id: 1,
            ref_name: "refs/pull/1/head",
            before_sha:,
            after_sha:,
          )
          loader = Loader.new(repository: @repo, ref_update_requests: [ref_update_request])
          requests = loader.requests

          assert_equal 1, requests.length
          fail unless request = requests.first
          fail unless request.is_a?(Request::Eligible)

          assert_equal 1, request.pull_request_id
          assert_equal "refs/pull/1/head", request.ref_name
          assert_equal before_sha, request.before_sha
          assert_equal after_sha, request.after_sha
        end

        test "returns eligible request for delete requests" do
          # sha for delete requests
          after_sha = GitHub::NULL_OID

          ref_update_request = FakeDatabaseRecord.new(
            repository_id: @repo.id,
            pull_request_id: 1,
            ref_name: "refs/pull/1/head",
            after_sha:,
          )
          loader = Loader.new(repository: @repo, ref_update_requests: [ref_update_request])
          requests = loader.requests

          assert_equal 1, requests.length
          fail unless request = requests.first
          fail unless request.is_a?(Request::Eligible)

          assert_equal 1, request.pull_request_id
          assert_equal "refs/pull/1/head", request.ref_name
          assert_nil request.before_sha
          assert_equal after_sha, request.after_sha
        end

        test "handles multiple eligible requests" do
          # need a valid sha from git repo
          after_sha = @repo.ref_to_sha("refs/heads/master")

          ref_update_request_1 = FakeDatabaseRecord.new(
            repository_id: @repo.id,
            pull_request_id: 1,
            ref_name: "refs/pull/1/head",
            after_sha:,
          )

          ref_update_request_2 = FakeDatabaseRecord.new(
            repository_id: @repo.id,
            pull_request_id: 1,
            ref_name: "refs/pull/1/head",
            after_sha:,
          )
          loader = Loader.new(repository: @repo, ref_update_requests: [ref_update_request_1, ref_update_request_2])
          requests = loader.requests

          assert_equal 2, requests.length
          fail unless request = requests.first
          fail unless request.is_a?(Request::Eligible)

          assert_equal 1, request.pull_request_id
          assert_equal "refs/pull/1/head", request.ref_name
          assert_nil request.before_sha
          assert_equal after_sha, request.after_sha

          fail unless request_2 = requests.second
          fail unless request_2.is_a?(Request::Eligible)

          assert_equal 1, request_2.pull_request_id
          assert_equal "refs/pull/1/head", request_2.ref_name
          assert_nil request_2.before_sha
          assert_equal after_sha, request_2.after_sha
        end

        test "handles both eligible and ineligible requests in a batch" do
          # need a valid sha from git repo
          after_sha = @repo.ref_to_sha("refs/heads/master")

          ref_update_request_1 = FakeDatabaseRecord.new(
            repository_id: @repo.id,
            pull_request_id: 1,
            ref_name: "refs/pull/1/head",
            after_sha:,
          )

          invalid_after_sha = SecureRandom.hex(20)
          ref_update_request_2 = FakeDatabaseRecord.new(
            repository_id: @repo.id,
            pull_request_id: 1,
            ref_name: "refs/pull/1/head",
            after_sha: invalid_after_sha,
          )
          loader = Loader.new(repository: @repo, ref_update_requests: [ref_update_request_1, ref_update_request_2])
          requests = loader.requests

          assert_equal 2, requests.length
          fail unless request = requests.first
          fail unless request.is_a?(Request::Eligible)

          assert_equal 1, request.pull_request_id
          assert_equal "refs/pull/1/head", request.ref_name
          assert_nil request.before_sha
          assert_equal after_sha, request.after_sha

          fail unless request_2 = requests.second
          fail unless request_2.is_a?(Request::Ineligible)

          assert_equal 1, request_2.pull_request_id
          assert_equal "refs/pull/1/head", request_2.ref_name
          assert_nil request_2.before_sha
          assert_equal invalid_after_sha, request_2.after_sha
          assert_equal Enums::Failures::HeadCommitNotFound, request_2.reason
        end

        test "returns ineligible request for invalid before_sha" do
          # invalid sha
          before_sha = SecureRandom.hex(20)
          # need a valid sha from git repo
          after_sha = @repo.ref_to_sha("refs/heads/master")

          ref_update_request = FakeDatabaseRecord.new(
            repository_id: @repo.id,
            pull_request_id: 1,
            ref_name: "refs/pull/1/head",
            before_sha:,
            after_sha:,
          )
          loader = Loader.new(repository: @repo, ref_update_requests: [ref_update_request])
          requests = loader.requests

          assert_equal 1, requests.length
          fail unless request = requests.first
          fail unless request.is_a?(Request::Ineligible)

          assert_equal 1, request.pull_request_id
          assert_equal "refs/pull/1/head", request.ref_name
          assert_equal before_sha, request.before_sha
          assert_nil request.after_sha
          assert_equal Enums::Failures::BaseCommitNotFound, request.reason
        end

        test "returns ineligible request for invalid after_sha" do
          after_sha = SecureRandom.hex(20)

          ref_update_request = FakeDatabaseRecord.new(
            repository_id: @repo.id,
            pull_request_id: 1,
            ref_name: "refs/pull/1/head",
            after_sha:,
          )
          loader = Loader.new(repository: @repo, ref_update_requests: [ref_update_request])
          requests = loader.requests

          assert_equal 1, requests.length
          fail unless request = requests.first
          fail unless request.is_a?(Request::Ineligible)

          assert_equal 1, request.pull_request_id
          assert_equal "refs/pull/1/head", request.ref_name
          assert_nil request.before_sha
          assert_equal after_sha, request.after_sha
          assert_equal Enums::Failures::HeadCommitNotFound, request.reason
        end

        test "returns ineligible request when ref_sha does not match before_sha" do
          # Prepare git state.
          before_ref = @repo.refs.find("refs/heads/master")
          before_sha = before_ref.sha
          ref_name = "refs/pull/1/head"
          after_sha = @repo.commits.create({ message: "New commit", committer: @owner }, before_sha) do |files|
            files.add "hello.txt", "Hello World!"
          end.sha

          @repo.refs.create(ref_name, before_sha, @owner)

          ref_update_request = FakeDatabaseRecord.new(
            repository_id: @repo.id,
            pull_request_id: 1,
            ref_name: "invalid ref name",
            before_sha:,
            after_sha:,
          )
          loader = Loader.new(repository: @repo, ref_update_requests: [ref_update_request])
          requests = loader.requests

          assert_equal 1, requests.length
          fail unless request = requests.first
          fail unless request.is_a?(Request::Ineligible)

          assert_equal 1, request.pull_request_id
          assert_equal "invalid ref name", request.ref_name
          assert_equal before_sha, request.before_sha
          assert_nil request.after_sha
          assert_equal Enums::Failures::GitError, request.reason
        end
      end
    end
  end
end
