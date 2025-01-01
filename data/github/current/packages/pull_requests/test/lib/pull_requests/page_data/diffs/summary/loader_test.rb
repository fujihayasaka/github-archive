# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::Diffs::Summary
    class LoaderTest < GitHub::TestCase
      include GitHub::QueryAssertionTestHelpers
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

        example_repo_snapshot
      end

      # for diff summary retrieval, logged in and out users have the same payload
      inputs = { 'logged in': @user, 'logged out': nil }
      inputs.each do |label, value|
        test "returns expected payload for #{label} user" do
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: value,
          )

          git_diff = pull_comparison.diff

          expected_payload = {
            "summaries" => git_diff.summary.deltas.map do |diff_delta|
              tree_entry_hash = {
                "oid" => diff_delta.old_file.oid,
                "path" => diff_delta.old_file.path,
                "mode" => diff_delta.old_file.mode,
                "type" => "blob",
              } if diff_delta.deleted?

              tree_entry_hash = {
                "oid" => diff_delta.new_file.oid,
                "path" => diff_delta.new_file.path,
                "mode" => diff_delta.new_file.mode,
                "type" => "blob",
              } unless diff_delta.deleted?

              {
                "diff_delta" => diff_delta,
                "tree_entry" => TreeEntry.new(@repository, tree_entry_hash),
              }
            end,
          }

          rpc_counts = {
            authzd: {
              single: 0,
              batch: 0,
            },
            gitrpc: 2,
          }

          query_counts = {
            repository_networks: 1,
          }

          assert_query_count_per_table(query_counts) do
            assert_rpc_calls(rpc_counts) do
              actual_payload = PullRequests::PageData::Diffs::Summary::Loader.load(
                diff: git_diff,
                repository: @repository,
              )

              assert_equal expected_payload["summaries"].length, actual_payload.summaries.length
              assert_equal 3, actual_payload.summaries.length # make sure we have all three changes
              assert_equal expected_payload, actual_payload.serialize
            end
          end
        end
      end
    end
  end
end
