# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData::Diffs::Contents
    class PayloadTest < GitHub::TestCase
      include PerformanceTestHelpers

      fixtures do
        @user = create(:user)
        @repository = create(:repository, admin: @user, from_example: :simple)

        @base_ref = @repository.heads.find(@repository.default_branch)

        # seed files to remove and modify
        @base_ref.append_commit({ message: "Seed base branch", committer: @user }, @user) do |files|
          files.add("file-to-modify.txt", "# Test File")
          files.add("file-to-remove.txt", "name: Test\non: [status, check_run]")
        end

        @head_ref = @repository.heads.create("topic", @base_ref.target, @user)

        # seed more files to validate gitprc calls dont increase with file count
        @head_ref.append_commit({ message: "Add files", committer: @user }, @user) do |files|
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

        @base_ref.freeze
        @head_ref.freeze
        @pull.freeze
      end

      test "serializes the diff contents payload with Ruby conventions using to_hash" do
        @expected_payload = [
            {
              "isBinary": false,
              "isSubmodule": false,
              "isTooBig": false,
              "diffLines": [
                {
                  "type": "HUNK",
                  "blobLineNumber": 0,
                  "position": 0,
                  "displayNoNewLineWarning": false,
                  "text": "@@ -0,0 +1 @@",
                  "html": "@@ -0,0 +1 @@",
                  "left": nil,
                  "right": 0,
                },
                {
                  "type": "ADDITION",
                  "blobLineNumber": 1,
                  "position": 1,
                  "displayNoNewLineWarning": false,
                  "text": "+# New File",
                  "html": "+# New File",
                  "left": nil,
                  "right": 1,
                }
              ],
              "linesAdded": 1,
              "linesChanged": 1,
              "linesDeleted": 0,
              "newCommitOid": @head_ref.target.oid,
              "newTreeEntry": { "mode": 100644, "path": "file-to-add.txt", "lineCount": 1, isGenerated: false },
              "oldCommitOid": @base_ref.target.oid,
              "oldTreeEntry": nil,
              "path": "file-to-add.txt",
              "pathDigest": "a466d7dddcd8507a1b33368ea7baa2fc32ce9e355cd348f04e49fdd13e93d06d",
              "richDiff": nil,
              "status": "ADDED",
              "truncatedReason": nil,
              "reviewed": false,
              "size": "",
            },
            {
              "isBinary": false,
              "isSubmodule": false,
              "isTooBig": false,
              "diffLines": [
                {
                  "type": "HUNK",
                  "blobLineNumber": 0,
                  "position": 0,
                  "displayNoNewLineWarning": false,
                  "text": "@@ -1 +1,2 @@",
                  "html": "@@ -1 +1,2 @@",
                  "left": 0,
                  "right": 0,
                },
                {
                  "type": "DELETION",
                  "blobLineNumber": 1,
                  "position": 1,
                  "displayNoNewLineWarning": false,
                  "text": "-# Test File",
                  "html": "-# Test File",
                  "left": 1,
                  "right": 0,
                },
                {
                  "type": "ADDITION",
                  "blobLineNumber": 1,
                  "position": 3,
                  "displayNoNewLineWarning": false,
                  "text": "+on: [status, check_run]",
                  "html": "+on: [status, check_run]",
                  "left": 1,
                  "right": 1,
                },
                {
                  "type": "ADDITION",
                  "blobLineNumber": 2,
                  "position": 4,
                  "displayNoNewLineWarning": false,
                  "text": "+Line added",
                  "html": "+Line added",
                  "left": 1,
                  "right": 2,
                }
              ],
              "linesAdded": 2,
              "linesChanged": 3,
              "linesDeleted": 1,
              "newCommitOid": @head_ref.target.oid,
              "newTreeEntry": { "mode": 100644, "path": "file-to-modify.txt", "lineCount": 2, isGenerated: false },
              "oldCommitOid": @base_ref.target.oid,
              "oldTreeEntry": { "mode": 100644, "path": "file-to-modify.txt", "lineCount": 1 },
              "path": "file-to-modify.txt",
              "pathDigest": "5c0e88470b653a145e9a1a8edabca4162cf5d4829e456f1cacd8982f1710d004",
              "richDiff": nil,
              "status": "MODIFIED",
              "truncatedReason": nil,
              "reviewed": false,
              "size": "",
            },
            {
              "isBinary": false,
              "isSubmodule": false,
              "isTooBig": false,
              "diffLines": [], # we don't serve lines for removed files, users click to fetch those on demand
              "linesAdded": 0,
              "linesChanged": 2,
              "linesDeleted": 2,
              "newCommitOid": @head_ref.target.oid,
              "newTreeEntry": nil,
              "oldCommitOid": @base_ref.target.oid,
              "oldTreeEntry": { "mode": 100644, "path": "file-to-remove.txt", "lineCount": 2 },
              "path": "file-to-remove.txt",
              "pathDigest": "8e4c689f4e7b6ed20c6e3dd505b195bc1028c2de0a6e15f3d1b24df31a396908",
              "richDiff": nil,
              "status": "REMOVED",
              "truncatedReason": nil,
              "reviewed": false,
              "size": "",
            }
          ]

        pull_comparison = PullRequest::Comparison.find(
          base_commit_oid: @pull.base_sha,
          end_commit_oid: @pull.head_sha,
          pull: @pull,
          start_commit_oid: @pull.merge_base,
          viewer: @user,
        )

        data = PullRequests::PageData::Diffs::Contents::Loader.load(
          diff: pull_comparison.diff,
          repository: @repository,
          ignore_whitespace: false,
          timeout: 1,
          top_only: true,
          viewed_files: PullRequestUserReviews.new(@pull, @user),
        )

        query_counts = {
          flipper_gates: 1,
        }

        rpc_counts = {
          authzd: {
            single: 0,
            batch: 0,
          },
          gitrpc: TestEnv.test_all_features? ? 0 : 4,
        }

        assert_query_count_per_table(query_counts) do
          assert_rpc_calls(rpc_counts) do
            actual_payload = PullRequests::PageData::Diffs::Contents::Payload.call(data)
            assert_equal @expected_payload.as_json, actual_payload.as_json
          end
        end
      end
    end
  end
end
