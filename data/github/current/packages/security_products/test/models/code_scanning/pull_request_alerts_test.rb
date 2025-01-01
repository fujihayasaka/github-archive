# typed: true
# frozen_string_literal: true

require "test_helper"

module CodeScanning
  class PullRequestAlertsTest < GitHub::TestCase
    include GitHub::PullRequestTestHelpers

    fixtures do
      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

      @user = create(:user)
      @org = create(:organization, admin: @user)
      @repository = create(:repository, owner: @org, from_example: :diff_lines)
      example_repo_snapshot

      make_trusted_oauth_apps_owner
      @code_scanning_app = create(:code_scanning_integration)
    end

    context ".file_changes" do
      test "returns all files included in pr.diffs" do
        big_file_contents = "".dup
        3.times do
          big_file_contents << ("a" * 30_000) + "\n"
        end
        commit = @repository.commits.create({ message: "too many lines and files overall", committer: @repository.owner }) do |files|
          250.times do |i|
            files.add(sprintf("file%03d", i + 1), "a\n")
          end
          250.times do |i|
            files.add(sprintf("file%03d", i + 251), big_file_contents)
          end
        end
        assert_equal true, commit.diff.truncated?
        assert_equal 300, commit.diff.entries.count
        assert_equal 500, commit.diff.changed_files
        assert_equal false, commit.diff.entries[0].truncated?
        assert_equal true, commit.diff.entries[299].truncated?

        file_changes_wrapper = CodeScanning::PullRequestAlerts.file_changes(commit.diff, include_deletions: false)
        file_changes = file_changes_wrapper.array
        assert_equal 500, file_changes.count
        expected_first = { file_path: "file001", changes: [{ added: true, start_line: 1, end_line: 1 }] }
        expected_last = { file_path: "file500", changes: [{ added: true, start_line: 1, end_line: 4294967295 }] }
        assert_equal expected_first, file_changes.first
        assert_equal expected_last, file_changes.last

        # Summary diff fallback on timeout
        commit.diff.stubs(:truncated_for_timeout?).returns(true)
        file_changes_wrapper = CodeScanning::PullRequestAlerts.file_changes(commit.diff, include_deletions: false)
        file_changes = file_changes_wrapper.array
        assert_equal 500, file_changes.count
        expected_first = { file_path: "file001", changes: [{ added: true, start_line: 1, end_line: 4_294_967_295 }] }
        expected_last = { file_path: "file500", changes: [{ added: true, start_line: 1, end_line: 4_294_967_295 }] }
        assert_equal expected_first, file_changes.first
        assert_equal expected_last, file_changes.last
      end

      test "returns the right blocks" do
        pull_request = make_pr(@repository, @repository, branch: "branch")

        file_changes_wrapper = CodeScanning::PullRequestAlerts.file_changes(pull_request.diffs, include_deletions: false)
        file_changes = file_changes_wrapper.array
        assert_equal 2, file_changes.size

        # Diff patch:
        # letters
        # a
        # +alpha
        # b
        # c
        # +charly
        # d
        # -e
        # +delta
        # +echo
        # f
        # g
        # h
        changed_line = T.must(file_changes.first)

        assert_equal "letters", changed_line[:file_path] # It is safe to assume 'letters' is the first file as the diff returns the files in alphabetical order
        assert_equal 3, changed_line[:changes].size

        assert_equal({ start_line: 2, end_line: 2, added: true }, changed_line[:changes][0])
        assert_equal({ start_line: 5, end_line: 5, added: true }, changed_line[:changes][1])
        assert_equal({ start_line: 7, end_line: 8, added: true }, changed_line[:changes][2])

        # Second file
        # numbers
        # +-3
        # +-2
        # +-1
        # 0
        # 1
        # 2
        # -3
        # -4
        # -5
        # +three
        # +four
        # +five
        # 6
        # 7
        # 8
        # @@ -13,9 +16,14 @@
        # 12
        # 13
        # 14
        # -15
        # +fifteen
        # 16
        # -17
        # +seventeen
        # 18
        # 19
        # 20
        # +21
        # +22
        # +23
        # +24
        # +25
        changed_line = T.must(file_changes.second)

        assert_equal "numbers", changed_line[:file_path]
        assert_equal 5, changed_line[:changes].size

        assert_equal({ start_line: 1, end_line: 3, added: true }, changed_line[:changes][0])
        assert_equal({ start_line: 7, end_line: 9, added: true }, changed_line[:changes][1])
        assert_equal({ start_line: 19, end_line: 19, added: true }, changed_line[:changes][2])
        assert_equal({ start_line: 21, end_line: 21, added: true }, changed_line[:changes][3])
        assert_equal({ start_line: 25, end_line: 29, added: true }, changed_line[:changes][4])

        # Now with the `include_deletions` flag set to true
        file_changes_wrapper = CodeScanning::PullRequestAlerts.file_changes(pull_request.diffs, include_deletions: true)
        file_changes = file_changes_wrapper.array
        assert_equal 2, file_changes.size

        changed_line = T.must(file_changes.first)

        assert_equal "letters", changed_line[:file_path]
        assert_equal 4, changed_line[:changes].size

        assert_equal({ start_line: 2, end_line: 2, added: true }, changed_line[:changes][0])
        assert_equal({ start_line: 5, end_line: 5, added: true }, changed_line[:changes][1])
        assert_equal({ start_line: 7, end_line: 8, added: true }, changed_line[:changes][2])
        assert_equal({ start_line: 5, end_line: 5, added: false }, changed_line[:changes][3])

        changed_line = T.must(file_changes.second)

        assert_equal "numbers", changed_line[:file_path]
        assert_equal 8, changed_line[:changes].size

        assert_equal({ start_line: 1, end_line: 3, added: true }, changed_line[:changes][0])
        assert_equal({ start_line: 7, end_line: 9, added: true }, changed_line[:changes][1])
        assert_equal({ start_line: 19, end_line: 19, added: true }, changed_line[:changes][2])
        assert_equal({ start_line: 21, end_line: 21, added: true }, changed_line[:changes][3])
        assert_equal({ start_line: 25, end_line: 29, added: true }, changed_line[:changes][4])
        assert_equal({ start_line: 4, end_line: 6, added: false }, changed_line[:changes][5])
        assert_equal({ start_line: 16, end_line: 16, added: false }, changed_line[:changes][6])
        assert_equal({ start_line: 18, end_line: 18, added: false }, changed_line[:changes][7])
      end

      test "no additions found with only deletions in the diff" do
        pull_request = make_pr(@repository, @repository, branch: "remove")

        file_changes_wrapper = CodeScanning::PullRequestAlerts.file_changes(pull_request.diffs, include_deletions: false)
        file_changes = file_changes_wrapper.array
        assert_equal 0, file_changes.size
      end

      test "works with only deletions in the diff" do
        pull_request = make_pr(@repository, @repository, branch: "remove")

        file_changes_wrapper = CodeScanning::PullRequestAlerts.file_changes(pull_request.diffs, include_deletions: false)
        file_changes = file_changes_wrapper.array
        assert file_changes.all? { |f| f[:changes].all? { |c| !c[:added] } }
      end
    end

    test ".line_ranges" do
      assert_equal [], CodeScanning::PullRequestAlerts.line_ranges([]).to_a
      assert_equal [[1, 1]], CodeScanning::PullRequestAlerts.line_ranges([1]).to_a
      assert_equal [[1, 2]], CodeScanning::PullRequestAlerts.line_ranges([1, 2]).to_a
      assert_equal [[1, 2], [5, 5], [9, 10]], CodeScanning::PullRequestAlerts.line_ranges([1, 2, 5, 9, 10]).to_a
      assert_equal [[1, 2], [5, 5], [9, 10]], CodeScanning::PullRequestAlerts.line_ranges([1, 9, 2, 10, 5]).to_a
      assert_equal [[1, 5]], CodeScanning::PullRequestAlerts.line_ranges([1, 2, 3, 4, 5]).to_a
      assert_equal [[1, 1], [10, 10], [15, 15], [100, 100]], CodeScanning::PullRequestAlerts.line_ranges([1, 10, 15, 100]).to_a
    end
  end
end
