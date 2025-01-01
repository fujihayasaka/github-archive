# typed: true
# frozen_string_literal: true

require "test_helper"
require "json"

module PullRequests
  module PageData::Diffs::Contents
    class LoaderTest < GitHub::TestCase
      include GitHub::QueryAssertionTestHelpers
      include PerformanceTestHelpers

      fixtures do
        @user = create(:user)
        @repository = create(:repository, admin: @user, from_example: :simple)

        base_ref = @repository.heads.find(@repository.default_branch)

        # sorry to muck this test up with all this content
        # but we need a decent amount of text so that I have extra lines to inject
        # if it's any consolation, this content is from a great simpsons episode
        file_to_modify_with_injected_context_lines_content = <<~EOF
          You know, Simpson, you're not as objectionable
          as you seemed when we first met!
          The story of our national parks begins in 1872.
          Perhaps we should let John Muir tell the tale.
          Excuse me, sir.
          I can't find my children.
          I won't lie to you
          Our chances of finding your children
          are slim to nil.
          Hi, mom!
          There they are!
          Let me down here!
          Sorry, there's no way off till we get to the top
          and even then it's sort of tricky.
        EOF

        modified_file_with_injected_lines_content = <<~EOF
          You know, Simpson, you're not as objectionable
          as you seemed when we first met!
          The story of our national parks begins in 1872.
          Perhaps we should let John Muir tell the tale.
          Excuse me, sir.
          I can't find my children.
          Follow me.
          We'll take the chair lift.
          It'll give us an eagle eye view
          of the area right below the chair lift.
          I won't lie to you
          Our chances of finding your children
          are slim to nil.
          Hi, mom!
          There they are!
          Let me down here!
          Sorry, there's no way off till we get to the top
          and even then it's sort of tricky.
        EOF

        # seed files to remove and modify
        base_ref.append_commit({ message: "Seed base branch", committer: @user }, @user) do |files|
          files.add("file-to-modify.txt", "# Test File")
          files.add("file-to-remove.txt", "name: Test\non: [status, check_run]")
          files.add("file-to-modify-with-injected-lines.txt", file_to_modify_with_injected_context_lines_content)
        end

        head_ref = @repository.heads.create("topic", base_ref.target, @user)

        # seed more files to validate gitprc calls dont increase with file count
        head_ref.append_commit({ message: "Add files", committer: @user }, @user) do |files|
          files.add("file-to-add.txt", "# New File")
          files.remove("file-to-remove.txt")
          files.add("file-to-modify.txt", "on: [status, check_run]\nLine added")
          files.add("file-to-modify-with-injected-lines.txt", modified_file_with_injected_lines_content)
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

        @added_diff_entry = GitHub::Diff::Entry.new(nil, "file-to-add.txt").freeze
        @modified_diff_entry = GitHub::Diff::Entry.new("file-to-modify.txt", "file-to-modify.txt").freeze
        @deleted_diff_entry = GitHub::Diff::Entry.new("file-to-remove.txt", nil).freeze
        @injected_lines_diff_entry = GitHub::Diff::Entry.new("file-to-modify-with-injected-lines.txt", nil).freeze
        @viewed_files = PullRequestUserReviews.new(@pull, @user).freeze

        @added_tree_entry = TreeEntry.new(@repository, {
          "path" => "file-to-add.txt",
          "mode" => "100644",
          "oid" => "e983499a5533fe7f87291a72252a241deeabae76",
          "type" => "blob"
        }).freeze

        @modified_new_tree_entry = TreeEntry.new(@repository, {
          "path" => "file-to-modify.txt",
          "mode" => "100644",
          "oid" => "81ec58b3154f2fa0bd159156a885d8bcac838be7",
          "type" => "blob"
        }).freeze

        @modified_old_tree_entry = TreeEntry.new(@repository, {
          "path" => "file-to-modify.txt",
          "mode" => "100644",
          "oid" => "c6a9d37a3e58ff73ad80dc3bcd4e4b4b7d4f084e",
          "type" => "blob"
        }).freeze

        @deleted_tree_entry = TreeEntry.new(@repository, {
          "path" => "file-to-remove.txt",
          "mode" => "100644",
          "oid" => "2b48b6f2ac64fdba6e26ad28b797d12f9aaa434d",
          "type" => "blob"
        }).freeze

        @injected_lines_new_tree_entry = TreeEntry.new(@repository, {
          "path" => "file-to-modify-with-injected-lines.txt",
          "mode" => "100644",
          "oid" => "2aff8bbe5cc51b2035651a3da3aa861d90d5ce94",
          "type" => "blob"
        }).freeze

        @injected_lines_old_tree_entry = TreeEntry.new(@repository, {
          "path" => "file-to-modify-with-injected-lines.txt",
          "mode" => "100644",
          "oid" => "e619752da5f077c2ac8539c7d4db46ae7c6e1f7b",
          "type" => "blob"
        }).freeze

        example_repo_snapshot
      end

      # for diff contents retrieval, logged in and out users have the same loader data
      inputs = { 'logged in': @user, 'logged out': nil }
      inputs.each do |label, viewer|
        test "returns loader data for #{label} user with expected RPC calls" do
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: viewer,
          )

          expected_data = {
            "diffs" => [
              {
                "diff_entry" => @added_diff_entry,
                "new_tree_entry" => @added_tree_entry,
                "old_tree_entry" => nil,
                "diffLines" => [],
                "binary_size" => nil,
                "diff_index" => 0
              },
              {
                "diff_entry" => @injected_lines_diff_entry,
                "new_tree_entry" => @injected_lines_new_tree_entry,
                "old_tree_entry" => @injected_lines_old_tree_entry,
                "diffLines" => [],
                "binary_size" => nil,
                "diff_index" => 1
              },
              {
                "diff_entry" => @modified_diff_entry,
                "new_tree_entry" => @modified_new_tree_entry,
                "old_tree_entry" => @modified_old_tree_entry,
                "diffLines" => [],
                "binary_size" => nil,
                "diff_index" => 2
              },
              {
                "diff_entry" => @deleted_diff_entry,
                "new_tree_entry" => nil,
                "old_tree_entry" => @deleted_tree_entry,
                "diffLines" => [],
                "binary_size" => nil,
                "diff_index" => 3
              },
            ]
          }

          rpc_counts = {
            authzd: {
              single: 0,
              batch: 0,
            },
            # count_lines (2)
            # native_read_diff_toc_with_base
            # read_attributes
            # read_diff_pairs_with_base
            # read_objects (2)
            #
            # All features calls read_diff_pairs_with_base twice
            gitrpc: TestEnv.test_all_features? ? 8 : 7,
          }

          assert_rpc_calls(rpc_counts) do
            assert_query_counts(4) do
              actual_data = PullRequests::PageData::Diffs::Contents::Loader.load(
                diff: pull_comparison.diff,
                ignore_whitespace: false,
                repository: @repository,
                timeout: 1,
                top_only: true,
                viewed_files: @viewed_files,
              )

              assert_equal expected_data["diffs"].length, actual_data.diffs.length
              assert_equal 4, actual_data.diffs.length # make sure we have all four changes

              # GitHub::Diff::Entry objects cannot be compared directly, so we assert on path instead
              assert_equal expected_data["diffs"].map { |diff| diff["diff_entry"].path }, actual_data.diffs.map { |diff| diff.diff_entry.path }
              assert_equal expected_data["diffs"].map { |diff| diff["new_tree_entry"] }, actual_data.diffs.map { |diff| diff.new_tree_entry }
              assert_equal expected_data["diffs"].map { |diff| diff["old_tree_entry"] }, actual_data.diffs.map { |diff| diff.old_tree_entry }
              assert_equal expected_data["diffs"].map { |diff| diff["binary_size"] }, actual_data.diffs.map { |diff| diff.binary_size }
              assert_equal expected_data["diffs"].map { |diff| diff["diff_index"] }, actual_data.diffs.map { |diff| diff.diff_index }
              # lines validation is hard - might need to follow up and do this separately - payload validation has good checks though
            end
          end
        end

        test "injects context lines in file already in diff for #{label} user with expected RPC calls" do
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: viewer,
          )

          rpc_counts = {
            authzd: {
              single: 0,
              batch: 0,
            },
            # count_lines (2)
            # native_read_diff_toc_with_base
            # read_attributes
            # read_blob_oids
            # read_diff_pairs_with_base
            # read_objects (3)
            #
            # All features read_diff_pairs_with_base twice
            gitrpc: TestEnv.test_all_features? ? 10 : 9,
          }

          assert_rpc_calls(rpc_counts) do
            assert_query_counts(4) do
              actual_data = PullRequests::PageData::Diffs::Contents::Loader.load(
                diff: pull_comparison.diff,
                ignore_whitespace: false,
                repository: @repository,
                timeout: 1,
                top_only: true,
                context_lines: { "file-to-modify-with-injected-lines.txt" => [15..17] },
                viewed_files: @viewed_files,
              )

              assert_equal 4, actual_data.diffs.length # make sure we have all four changes + the injected file

              context_injected_diff_entry = actual_data.diffs.find { |diff| diff.diff_entry.path == "file-to-modify-with-injected-lines.txt" }
              diff_text = T.must(context_injected_diff_entry).lines.map(&:text).join("\n")
              assert_includes diff_text, "Let me down here!"
              assert_includes diff_text, "Sorry, there's no way off till we get to the top"
            end
          end
        end

        test "filters diff to given paths for #{label} user" do
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: viewer,
          )

          expected_data = {
            "diffs" => [
              {
                "diff_entry" => @modified_diff_entry,
                "new_tree_entry" => @modified_new_tree_entry,
                "old_tree_entry" => @modified_old_tree_entry,
                "diffLines" => [],
                "binary_size" => nil,
                "diff_index" => 0
              },
              {
                "diff_entry" => @deleted_diff_entry,
                "new_tree_entry" => nil,
                "old_tree_entry" => @deleted_tree_entry,
                "diffLines" => [],
                "binary_size" => nil,
                "diff_index" => 1
              }
            ]
          }

          rpc_counts = {
            authzd: {
              single: 0,
              batch: 0,
            },
            # count_lines (2)
            # native_read_diff_toc_with_base
            # read_attributes
            # read_diff_pairs_with_base
            # read_diff_summary_with_base
            # read_objects (2)
            #
            # All features calls native_read_diff_toc_with_base twice
            gitrpc: TestEnv.test_all_features? ? 9 : 8,
          }

          filtered_paths = ["file-to-modify.txt", "file-to-remove.txt"]

          assert_rpc_calls(rpc_counts) do
            assert_query_counts(4) do
              actual_data = PullRequests::PageData::Diffs::Contents::Loader.load(
                diff: pull_comparison.diff,
                paths: filtered_paths,
                ignore_whitespace: false,
                repository: @repository,
                timeout: 1,
                top_only: true,
                viewed_files: @viewed_files,
              )

              assert_equal expected_data["diffs"].length, actual_data.diffs.length
              assert_equal filtered_paths, actual_data.diffs.map { |diff| diff.diff_entry.path }

              # GitHub::Diff::Entry objects cannot be compared directly, so we assert on path instead
              assert_equal expected_data["diffs"].map { |diff| diff["diff_entry"].path }, actual_data.diffs.map { |diff| diff.diff_entry.path }
              assert_equal expected_data["diffs"].map { |diff| diff["new_tree_entry"] }, actual_data.diffs.map { |diff| diff.new_tree_entry }
              assert_equal expected_data["diffs"].map { |diff| diff["old_tree_entry"] }, actual_data.diffs.map { |diff| diff.old_tree_entry }
              assert_equal expected_data["diffs"].map { |diff| diff["binary_size"] }, actual_data.diffs.map { |diff| diff.binary_size }
              assert_equal expected_data["diffs"].map { |diff| diff["diff_index"] }, actual_data.diffs.map { |diff| diff.diff_index }
            end
          end
        end

        test "fails to add paths for #{label} user if diff has already been loaded" do
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: viewer,
          )

          diff = pull_comparison.diff
          refute_predicate diff, :loaded?

          diff.load_diff
          assert_predicate diff, :loaded?

          assert_raises GitHub::Diff::AlreadyLoaded do
            PullRequests::PageData::Diffs::Contents::Loader.load(
              diff: diff,
              paths: ["file-to-modify.txt", "file-to-remove.txt"],
              ignore_whitespace: false,
              repository: @repository,
              timeout: 1,
              top_only: true,
              viewed_files: @viewed_files,
            )
          end
        end

        test "does not apply top only limit for #{label} user if top_only option is false" do
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: viewer,
          )

          diff = pull_comparison.diff
          refute_predicate diff, :top_only?
          diff.expects(:apply_top_only_limits!).never

          rpc_counts = {
            authzd: {
              single: 0,
              batch: 0,
            },
            # count_lines (2)
            # native_read_diff_toc_with_base
            # read_attributes
            # read_diff_pairs_with_base
            # read_diff_summary_with_base
            # read_objects (2)
            #
            # All features does not call read_diff_summary_with_base
            gitrpc: TestEnv.test_all_features? ? 6 : 7,
          }

          assert_rpc_calls(rpc_counts) do
            PullRequests::PageData::Diffs::Contents::Loader.load(
              diff: diff,
              ignore_whitespace: false,
              repository: @repository,
              timeout: 1,
              top_only: false,
              viewed_files: @viewed_files,
            )
          end

          refute_predicate diff, :top_only?
        end

        test "applies top only limit for #{label} user if top_only option is true" do
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: viewer,
          )

          diff = pull_comparison.diff
          refute_predicate diff, :top_only?

          diff.expects(:apply_auto_load_single_entry_limits!).never
          diff.expects(:maximize_single_entry_limits!).never
          diff.expects(:apply_top_only_limits!).once

          rpc_counts = {
            authzd: {
              single: 0,
              batch: 0,
            },
            # count_lines (2)
            # native_read_diff_toc_with_base
            # read_attributes
            # read_diff_pairs_with_base
            # read_diff_summary_with_base
            # read_objects (2)
            #
            # All features does not call read_diff_summary_with_base
            gitrpc: TestEnv.test_all_features? ? 6 : 7,
          }

          assert_rpc_calls(rpc_counts) do
            PullRequests::PageData::Diffs::Contents::Loader.load(
              diff: diff,
              ignore_whitespace: false,
              repository: @repository,
              timeout: 1,
              top_only: true,
              viewed_files: @viewed_files,
            )
          end

          assert_predicate diff, :top_only?
        end

        test "applies auto load single entry limit for #{label} user by default" do
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: viewer,
          )

          diff = pull_comparison.diff
          diff.expects(:apply_auto_load_single_entry_limits!).once
          diff.expects(:maximize_single_entry_limits!).never
          diff.expects(:apply_top_only_limits!).never

          rpc_counts = {
            authzd: {
              single: 0,
              batch: 0,
            },
            # count_lines (2), read_attributes, read_diff_pairs_with_base, read_diff_summary_with_base, read_objects (2)
            # All features does not call read_diff_summary_with_base
            gitrpc: TestEnv.test_all_features? ? 6 : 7,
          }

          assert_rpc_calls(rpc_counts) do
            PullRequests::PageData::Diffs::Contents::Loader.load(
              diff: pull_comparison.diff,
              ignore_whitespace: false,
              repository: @repository,
              timeout: 1,
              top_only: false,
              viewed_files: @viewed_files,
            )
          end
        end

        test "applies maximum single entry limit for #{label} user when single path is requested" do
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: viewer,
          )

          diff = pull_comparison.diff
          diff.expects(:apply_auto_load_single_entry_limits!).never
          diff.expects(:maximize_single_entry_limits!).once
          diff.expects(:apply_top_only_limits!).never

          rpc_counts = {
            authzd: {
              single: 0,
              batch: 0,
            },
            # count_lines (2)
            # native_read_diff_toc_with_base
            # read_attributes
            # read_diff_pairs_with_base
            # read_diff_summary_with_base
            # read_objects (2)
            #
            # All features does not call read_diff_summary_with_base
            gitrpc: TestEnv.test_all_features? ? 7 : 8,
          }

          assert_rpc_calls(rpc_counts) do
            PullRequests::PageData::Diffs::Contents::Loader.load(
              diff: diff,
              ignore_whitespace: false,
              paths: ["file-to-modify.txt"],
              repository: @repository,
              timeout: 1,
              top_only: false,
              viewed_files: @viewed_files,
            )
          end
        end

        test "applies auto load single entry limit for #{label} user when multiple paths are requested" do
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: viewer,
          )

          diff = pull_comparison.diff
          diff.expects(:apply_auto_load_single_entry_limits!).once
          diff.expects(:maximize_single_entry_limits!).never
          diff.expects(:apply_top_only_limits!).never

          rpc_counts = {
            authzd: {
              single: 0,
              batch: 0,
            },
            # count_lines (2)
            # native_read_diff_toc_with_base
            # read_attributes
            # read_diff_pairs_with_base
            # read_diff_summary_with_base
            # read_objects (2)
            #
            # All features does not call read_diff_summary_with_base
            gitrpc: TestEnv.test_all_features? ? 7 : 8,
          }

          assert_rpc_calls(rpc_counts) do
            PullRequests::PageData::Diffs::Contents::Loader.load(
              diff: diff,
              ignore_whitespace: false,
              paths: ["file-to-modify.txt", "file-to-remove.txt"],
              repository: @repository,
              timeout: 1,
              top_only: false,
              viewed_files: @viewed_files,
            )
          end
        end

        test "applies maximum single entry limit for #{label} user when diff has 1 changed file and diff summary or deltas are already loaded" do
          # Creates pull request with single changed file
          pull = create(:pull_request, :with_mergeable_head, repository: @repository)
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: pull.base_sha,
            end_commit_oid: pull.head_sha,
            pull: pull,
            start_commit_oid: pull.merge_base,
            viewer: viewer,
          )

          diff = pull_comparison.diff
          # In addition to verifying that we've set up our test data correctly, calling changed_files
          # also loads diff summary and/or deltas, a prerequisite for this test case.
          assert_equal diff.changed_files, 1

          rpc_counts = {
            authzd: {
              single: 0,
              batch: 0,
            },
            # count_lines (2), read_attributes, read_diff_pairs_with_base, read_diff_summary_with_base, read_objects (2)
            # All features does not call read_diff_summary_with_base
            gitrpc: TestEnv.test_all_features? ? 6 : 7,
          }

          assert_rpc_calls(rpc_counts) do
            diff.expects(:apply_auto_load_single_entry_limits!).never
            diff.expects(:maximize_single_entry_limits!).once
            diff.expects(:apply_top_only_limits!).never

            PullRequests::PageData::Diffs::Contents::Loader.load(
              diff: diff,
              ignore_whitespace: false,
              repository: @repository,
              timeout: 1,
              top_only: false,
              viewed_files: @viewed_files,
            )
          end
        end

        test "applies auto load single entry limit for #{label} user when diff has multiple changed files and diff summary or deltas are already loaded" do
          pull_comparison = PullRequest::Comparison.find(
            base_commit_oid: @pull.base_sha,
            end_commit_oid: @pull.head_sha,
            pull: @pull,
            start_commit_oid: @pull.merge_base,
            viewer: viewer,
          )

          diff = pull_comparison.diff
          # In addition to verifying that we've set up our test data correctly, calling changed_files
          # also loads diff summary and/or deltas, a prerequisite for this test case.
          assert diff.changed_files > 1

          rpc_counts = {
            authzd: {
              single: 0,
              batch: 0,
            },
            # count_lines (2), read_attributes, read_diff_pairs_with_base, read_diff_summary_with_base, read_objects (2)
            # All features does not call read_diff_summary_with_base
            gitrpc: TestEnv.test_all_features? ? 6 : 7,
          }

          assert_rpc_calls(rpc_counts) do
            diff.expects(:apply_auto_load_single_entry_limits!).once
            diff.expects(:maximize_single_entry_limits!).never
            diff.expects(:apply_top_only_limits!).never

            PullRequests::PageData::Diffs::Contents::Loader.load(
              diff: diff,
              ignore_whitespace: false,
              repository: @repository,
              timeout: 1,
              top_only: false,
              viewed_files: @viewed_files,
            )
          end
        end
      end
    end
  end
end
