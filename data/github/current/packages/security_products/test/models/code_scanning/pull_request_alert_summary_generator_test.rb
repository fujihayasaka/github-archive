# typed: true
# frozen_string_literal: true

require "test_helper"

module CodeScanning
  class PullRequestAlertSummaryGeneratorTest < GitHub::TestCase
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

    context "changed_lines" do
      test "line_ranges" do
        assert_equal [], CodeScanning::PullRequestAlertSummaryGenerator.line_ranges([]).to_a
        assert_equal [[1, 1]], CodeScanning::PullRequestAlertSummaryGenerator.line_ranges([1]).to_a
        assert_equal [[1, 2]], CodeScanning::PullRequestAlertSummaryGenerator.line_ranges([1, 2]).to_a
        assert_equal [[1, 2], [5, 5], [9, 10]], CodeScanning::PullRequestAlertSummaryGenerator.line_ranges([1, 2, 5, 9, 10]).to_a
        assert_equal [[1, 2], [5, 5], [9, 10]], CodeScanning::PullRequestAlertSummaryGenerator.line_ranges([1, 9, 2, 10, 5]).to_a
        assert_equal [[1, 5]], CodeScanning::PullRequestAlertSummaryGenerator.line_ranges([1, 2, 3, 4, 5]).to_a
        assert_equal [[1, 1], [10, 10], [15, 15], [100, 100]], CodeScanning::PullRequestAlertSummaryGenerator.line_ranges([1, 10, 15, 100]).to_a
      end

      test "returns the right blocks" do

        pull_request = make_pr(@repository, @repository, branch: "branch")

        changed_lines = CodeScanning::PullRequestAlertSummaryGenerator.changed_lines(pull_request.diffs, include_deletions: false)
        assert_equal 2, changed_lines.size

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
        changed_line = T.must(changed_lines.first)

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
        assert_equal "numbers", changed_lines.second[:file_path]
        assert_equal 5, changed_lines.second[:changes].size

        assert_equal({ start_line: 1, end_line: 3, added: true }, changed_lines.second[:changes][0])

        assert_equal({ start_line: 7, end_line: 9, added: true }, changed_lines.second[:changes][1])

        assert_equal({ start_line: 19, end_line: 19, added: true }, changed_lines.second[:changes][2])

        assert_equal({ start_line: 21, end_line: 21, added: true }, changed_lines.second[:changes][3])

        assert_equal({ start_line: 25, end_line: 29, added: true }, changed_lines.second[:changes][4])

        # Now with the `include_deletions` flag set to true
        changed_lines = CodeScanning::PullRequestAlertSummaryGenerator.changed_lines(pull_request.diffs, include_deletions: true)
        assert_equal 2, changed_lines.size

        changed_line = T.must(changed_lines.first)

        assert_equal "letters", changed_line[:file_path]
        assert_equal 4, changed_line[:changes].size

        assert_equal({ start_line: 2, end_line: 2, added: true }, changed_line[:changes][0])

        assert_equal({ start_line: 5, end_line: 5, added: true }, changed_line[:changes][1])

        assert_equal({ start_line: 7, end_line: 8, added: true }, changed_line[:changes][2])

        assert_equal({ start_line: 5, end_line: 5, added: false }, changed_line[:changes][3])


        assert_equal "numbers", changed_lines.second[:file_path]
        assert_equal 8, changed_lines.second[:changes].size

        assert_equal({ start_line: 1, end_line: 3, added: true }, changed_lines.second[:changes][0])

        assert_equal({ start_line: 7, end_line: 9, added: true }, changed_lines.second[:changes][1])

        assert_equal({ start_line: 19, end_line: 19, added: true }, changed_lines.second[:changes][2])

        assert_equal({ start_line: 21, end_line: 21, added: true }, changed_lines.second[:changes][3])

        assert_equal({ start_line: 25, end_line: 29, added: true }, changed_lines.second[:changes][4])

        assert_equal({ start_line: 4, end_line: 6, added: false }, changed_lines.second[:changes][5])
        assert_equal({ start_line: 16, end_line: 16, added: false }, changed_lines.second[:changes][6])
        assert_equal({ start_line: 18, end_line: 18, added: false }, changed_lines.second[:changes][7])
      end

      test "no additions found with only deletions in the diff" do
        pull_request = make_pr(@repository, @repository, branch: "remove")

        changed_lines = CodeScanning::PullRequestAlertSummaryGenerator.changed_lines(pull_request.diffs, include_deletions: false)
        assert_equal 0, changed_lines.size
      end

      test "works with only deletions in the diff" do
        pull_request = make_pr(@repository, @repository, branch: "remove")

        changed_lines = CodeScanning::PullRequestAlertSummaryGenerator.changed_lines(pull_request.diffs, include_deletions: true)
        assert changed_lines.all? { |f| f[:changes].all? { |c| !c[:added] } }
      end
    end
  end
end
