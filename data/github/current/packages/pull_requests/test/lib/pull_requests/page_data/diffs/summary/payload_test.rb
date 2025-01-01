# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData::Diffs::Summary
    class PayloadTest < GitHub::TestCase
      include PerformanceTestHelpers

      fixtures do
        @user = create(:user)
        @repository = create(:repository, admin: @user, from_example: :simple)

        base_ref = @repository.heads.find(@repository.default_branch)

        # seed files to remove and modify
        base_ref.append_commit({ message: "Seed base branch", committer: @user }, @user) do |files|
          files.add("file-to-modify.txt", "# Test File")
          files.add("file-to-remove.txt", "name: Test\non: [status, check_run]")
        end

        head_ref = @repository.heads.create("topic", base_ref.target, @user)

        # seed more files to validate gitprc calls dont increase with file count
        head_ref.append_commit({ message: "Add files", committer: @user }, @user) do |files|
          files.add("file-to-add.txt", "# New File")
          files.remove("file-to-remove.txt")
          files.add("file-to-modify.txt", "on: [status, check_run]\nLine added")
        end

        @pull = create(:pull_request,
          repository: @repository,
          base_repository: @repository,
          base_user: @user,
          base_ref: @repository.default_branch,
          head_repository: @repository,
          head_user: @user,
          head_ref_name: "topic",
          user: @user,
        )
      end

      test "serializes the diff summary payload with Ruby conventions using to_hash" do
        pull_comparison = PullRequest::Comparison.find(
          base_commit_oid: @pull.base_sha,
          end_commit_oid: @pull.head_sha,
          pull: @pull,
          start_commit_oid: @pull.merge_base,
          viewer: @user,
        )

        git_diff = pull_comparison.diff

        @expected_payload = {
          "summaries" => [
            {
              "changeType" => "ADDED",
              "isManifestFile" => false,
              "isVendored" => false,
              "path" => "file-to-add.txt",
              "pathDigest" => "a466d7dddcd8507a1b33368ea7baa2fc32ce9e355cd348f04e49fdd13e93d06d"
            },
            {
              "changeType" => "MODIFIED",
              "isManifestFile" => false,
              "isVendored" => false,
              "path" => "file-to-modify.txt",
              "pathDigest" => "5c0e88470b653a145e9a1a8edabca4162cf5d4829e456f1cacd8982f1710d004"
            },
            {
              "changeType" => "REMOVED",
              "isManifestFile" => false,
              "isVendored" => false,
              "path" => "file-to-remove.txt",
              "pathDigest" => "8e4c689f4e7b6ed20c6e3dd505b195bc1028c2de0a6e15f3d1b24df31a396908"
            }
          ],
        }

        data = PullRequests::PageData::Diffs::Summary::Loader.load(
          diff: git_diff,
          repository: @repository,
        )

        rpc_counts = {
          authzd: {
            single: 0,
            batch: 0,
          },
          gitrpc: 0,
        }

        assert_no_queries do
          assert_rpc_calls(rpc_counts) do
            actual_payload = PullRequests::PageData::Diffs::Summary::Payload.call(data)
            assert_equal @expected_payload.as_json, actual_payload.as_json
          end
        end
      end
    end
  end
end
