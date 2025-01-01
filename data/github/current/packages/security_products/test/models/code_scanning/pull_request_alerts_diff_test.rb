# typed: true
# frozen_string_literal: true

require "test_helper"

module CodeScanning
  class PullRequestAlertsDiffTest < GitHub::TestCase
    include GitHub::PullRequestTestHelpers

    fixtures do
      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

      @user = create(:user)
      @org = create(:organization, admin: @user)
      @repository = create(:repository, owner: @org, from_example: :diff_lines)
      example_repo_snapshot
    end

    setup do
      example_repo_restore
    end

    test "returns the right blocks" do
      pull_request = make_pr(@repository, @repository, branch: "branch")

      pr_alerts_diff = CodeScanning::PullRequestAlertsDiff.new(pull_request)
      pr_alerts_diff.detect_changes!

      changed_lines = pr_alerts_diff.file_changes
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
      assert_equal "letters", changed_lines.first[:file_path] # It is safe to assume 'letters' is the first file as the diff returns the files in alphabetical order
      assert_equal 3, changed_lines.first[:changes].size

      assert_equal({ start_line: 2, end_line: 2, added: true }, changed_lines.first[:changes][0])
      assert_equal({ start_line: 5, end_line: 5, added: true }, changed_lines.first[:changes][1])
      assert_equal({ start_line: 7, end_line: 8, added: true }, changed_lines.first[:changes][2])

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
    end

    test "skips deletions in the diff" do
      pull_request = make_pr(@repository, @repository, branch: "remove")

      pr_alerts_diff = CodeScanning::PullRequestAlertsDiff.new(pull_request)
      pr_alerts_diff.detect_changes!

      assert_equal [], pr_alerts_diff.file_changes
    end

    context "diff unavailable" do
      test "returns unavailable reason" do
        GitHub::Diff.any_instance.stubs(:unavailable_reason).returns("corrupt")

        pull_request = make_pr(@repository, @repository, branch: "branch")

        pr_alerts_diff = CodeScanning::PullRequestAlertsDiff.new(pull_request)
        pr_alerts_diff.detect_changes!

        assert_equal [], pr_alerts_diff.file_changes
        assert_equal "corrupt", pr_alerts_diff.unavailable_reason
        assert_equal :corrupt, pr_alerts_diff.unavailable_reason_symbol
      end
    end

    context "diff truncated" do
      test "returns truncated reason" do
        GitHub::Diff.any_instance.stubs(:truncated?).returns(true)
        GitHub::Diff.any_instance.stubs(:truncated_reason).returns("maximum file count exceeded: total=1234")

        pull_request = make_pr(@repository, @repository, branch: "branch")

        pr_alerts_diff = CodeScanning::PullRequestAlertsDiff.new(pull_request)
        pr_alerts_diff.detect_changes!

        assert_equal [], pr_alerts_diff.file_changes
        assert_equal "maximum file count exceeded: total=1234", pr_alerts_diff.truncated_reason
        assert_equal :truncated_for_max_files, pr_alerts_diff.truncated_reason_symbol
      end
    end

    context "capped" do
      test "returns capped? true if changes exceed max changes" do
        head_ref = @repository.heads.create("large-branch", @repository.heads.find("master").target_oid, @user)
        metadata = { message: "blah", committer: @user }

        head_ref.append_commit(metadata, @user) do |files|
          500.times do |i|
            files.add("blah-#{i}.txt", "blahblahblah")
          end
        end

        pull_request = PullRequest.create_for!(
          @repository,
          user: @user,
          base: "master",
          head: "large-branch",
          title: "title",
          body: "body"
        )

        pr_alerts_diff = CodeScanning::PullRequestAlertsDiff.new(pull_request, max_changes: 100)
        pr_alerts_diff.detect_changes!

        assert_equal 100, pr_alerts_diff.file_changes.count
        assert pr_alerts_diff.capped?

        pr_alerts_diff = CodeScanning::PullRequestAlertsDiff.new(pull_request, max_changes: 1000)
        pr_alerts_diff.detect_changes!

        assert_equal 500, pr_alerts_diff.file_changes.count
        refute pr_alerts_diff.capped?
      end
    end
  end
end
