# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::Copilot::CompareTreesDiffCreatorTest < GitHub::TestCase
  fixtures do
    if TestEnv.test_in_multitenancy_mode?
      emu_business = create(:business, :enterprise_managed)
      @user = create :emu, business: emu_business
      @org = create(:copilot_feature_enabled_enterprise_organization,
        :copilot_plan_enterprise,
        business: emu_business,
        admin: @user,
      )
    else
      @user = create(:user)
      @org = create(:copilot_feature_enabled_enterprise_organization,
        :copilot_plan_enterprise,
        admin: @user,
      )
      @org.add_member(@user)
    end

    @access_token = Copilot::User::CopilotApi.generate_token(
      method: :post,
      path: "/github/chat",
      user: @user,
      session: create(:user_session, user: @user),
    )

    @base_repo = create(:repository, :org_owned_internal, owner: @org, from_example: :simple)
    @head_repo = create(:repository, :org_owned_internal, owner: @org, from_example: :simple)

    @issue = create(:issue, repository: @base_repo, user: @user)

    feature_branch_name = "feature-#{SecureRandom.hex(5)}"
    @master_sha = @base_repo.heads.find("master").sha
    feature = @head_repo.heads.create(feature_branch_name, @master_sha, @head_repo.owner)
    feature.append_commit({ committer: @head_repo.owner, message: "testing" }, @head_repo.owner) do |files|
      files.add("test2.txt", "change")
    end
    feature.append_commit({ committer: @head_repo.owner, message: "adding file" }, @head_repo.owner) do |files|
      files.add("second-file.txt", "the contents of another file")
    end
    @feature_sha = @head_repo.heads.find(feature_branch_name).sha
  end

  setup do
    copilot_business = Copilot::Business.new(@org.business)
    copilot_business.copilot_for_dotcom_enabled!
  end

  context ".call" do
    test "returns the diff between two trees" do
      result = PullRequests::Copilot::CompareTreesDiffCreator.call(
        base_repo: @base_repo,
        head_repo: @head_repo,
        base_revision: @master_sha,
        head_revision: @feature_sha,
      )

      diff_hunks = result[:diff_hunks]
      refute_nil diff_hunks
      assert diff_hunks.is_a?(Array)
      assert_equal 2, diff_hunks.length

      first_hunk = diff_hunks[0]
      assert_equal "F172657cR1", first_hunk[:change_reference]
      assert_equal "second-file.txt", first_hunk[:file_path]
      assert_equal "```diff\n@@ -0,0 +1 @@\n[-1,1]+the contents of another file\n```\n", first_hunk[:diff]

      second_hunk = diff_hunks[1]
      assert_equal "F8013df8R1", second_hunk[:change_reference]
      assert_equal "test2.txt", second_hunk[:file_path]
      assert_equal "```diff\n@@ -0,0 +1 @@\n[-1,1]+change\n```\n", second_hunk[:diff]
    end

    test "returns the diff for a specific path" do
      result = PullRequests::Copilot::CompareTreesDiffCreator.call(
        base_repo: @base_repo,
        head_repo: @head_repo,
        base_revision: @master_sha,
        head_revision: @feature_sha,
        paths: ["second-file.txt"],
      )

      diff_hunks = result[:diff_hunks]
      refute_nil diff_hunks
      assert diff_hunks.is_a?(Array)
      assert_equal 1, diff_hunks.length

      hunk = diff_hunks[0]
      assert_equal "F172657cR1", hunk[:change_reference]
      assert_equal "second-file.txt", hunk[:file_path]
      assert_equal "```diff\n@@ -0,0 +1 @@\n[-1,1]+the contents of another file\n```\n", hunk[:diff]
    end

    test "payload contains diff lines between two trees" do
      result = PullRequests::Copilot::CompareTreesDiffCreator.call(
        base_repo: @base_repo,
        head_repo: @head_repo,
        base_revision: @master_sha,
        head_revision: @feature_sha,
      )

      diff_hunks = result[:diff_hunks]
      refute_nil diff_hunks
      assert diff_hunks.is_a?(Array)
      assert_equal 2, diff_hunks.length

      first_hunk = diff_hunks[0]
      expected_first_hunk_diff_lines = [
        { line_number: "0", line_content: "@@ -0,0 +1 @@", line_side: "R" },
        { line_number: "1", line_content: "+the contents of another file", line_side: "R" }
      ]
      assert_equal expected_first_hunk_diff_lines, first_hunk[:diff_lines]

      second_hunk = diff_hunks[1]
      expected_second_hunk_diff_lines = [
        { line_number: "0", line_content: "@@ -0,0 +1 @@", line_side: "R" },
        { line_number: "1", line_content: "+change", line_side: "R" },
      ]
      assert_equal expected_second_hunk_diff_lines, second_hunk[:diff_lines]
    end
  end
end
