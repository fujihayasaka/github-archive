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

        file_changes = CodeScanning::PullRequestAlerts.file_changes(commit.diff, include_deletions: false)
        assert_equal 500, file_changes.count
        expected_first = { file_path: "file001", changes: [{ added: true, start_line: 1, end_line: 1 }] }
        expected_last = { file_path: "file500", changes: [{ added: true, start_line: 1, end_line: 4294967295 }] }
        assert_equal expected_first, file_changes.first
        assert_equal expected_last, file_changes.last

        # Summary diff fallback on timeout
        commit.diff.stubs(:truncated_for_timeout?).returns(true)
        file_changes = CodeScanning::PullRequestAlerts.file_changes(commit.diff, include_deletions: false)
        assert_equal 500, file_changes.count
        expected_first = { file_path: "file001", changes: [{ added: true, start_line: 1, end_line: 4_294_967_295 }] }
        expected_last = { file_path: "file500", changes: [{ added: true, start_line: 1, end_line: 4_294_967_295 }] }
        assert_equal expected_first, file_changes.first
        assert_equal expected_last, file_changes.last
      end
    end
  end
end
