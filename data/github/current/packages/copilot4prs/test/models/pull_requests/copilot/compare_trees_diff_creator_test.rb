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

    @master_sha = @base_repo.heads.find("master").sha
  end

  setup do
    copilot_business = Copilot::Business.new(@org.business)
    copilot_business.copilot_for_dotcom_enabled!

    @feature_branch_name = "feature-#{SecureRandom.hex(5)}"
    @feature = @head_repo.heads.create(@feature_branch_name, @master_sha, @head_repo.owner)
    @feature.append_commit({ committer: @head_repo.owner, message: "testing" }, @head_repo.owner) do |files|
      files.add("test2.txt", "change")
    end
    @feature.append_commit({ committer: @head_repo.owner, message: "adding file" }, @head_repo.owner) do |files|
      files.add("second-file.txt", "the contents of another file")
    end
    @feature_sha = @head_repo.heads.find(@feature_branch_name).sha
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

  context "#file_contents" do
    test "removes the blob of a rename witout changes for base file contents" do
      @feature.append_commit({ message: "Rename without changes", committer: @head_repo.owner }, @head_repo.owner) do |files|
        files.add("empty_file", "line1\nline2\nline3\n")
        # this is from a file in the simple example fixture
        files.move("a", "renamed.txt", "a\nb\nc\n")
      end
      head_sha = @head_repo.heads.find(@feature_branch_name).sha
      diff_creator = PullRequests::Copilot::CompareTreesDiffCreator.new(
        base_repo: @base_repo,
        head_repo: @head_repo,
        base_revision: @feature_sha,
        head_revision: head_sha,
      )
      result = diff_creator.base_file_contents

      # checking we did not get rescued from a GitRPC::Error and return []
      refute_empty result
      assert_equal 1, result.size
      assert_equal "empty_file", T.must(result.first)[:path]
    end

    test "keeps the blob of a rename with a modification for base file contents" do
      @feature.append_commit({ message: "Rename with changes", committer: @head_repo.owner }, @head_repo.owner) do |files|
        files.add("empty_file", "line1\nline2\nline3\n")
        # this is from a file in the simple example fixture
        files.move("a", "renamed.txt", "a\nb\nc\nd\ne\n")
      end
      head_sha = @head_repo.heads.find(@feature_branch_name).sha
      diff_creator = PullRequests::Copilot::CompareTreesDiffCreator.new(
        base_repo: @base_repo,
        head_repo: @head_repo,
        base_revision: @feature_sha,
        head_revision: head_sha,
      )
      result = diff_creator.base_file_contents

      refute_empty result
      assert_equal 2, result.size
      paths = result.map { |r| r[:path] }
      assert_same_elements ["empty_file", "renamed.txt"], paths
    end

    test "use the b_path as the key for both left and right blobs" do
      @feature.append_commit({ message: "Rename with changes", committer: @head_repo.owner }, @head_repo.owner) do |files|
        files.add("empty_file", "line1\nline2\nline3\n")
        # this is from a file in the simple example fixture
        files.move("a", "renamed.txt", "a\nb\nc\nd\ne\n")
      end
      head_sha = @head_repo.heads.find(@feature_branch_name).sha
      diff_creator = PullRequests::Copilot::CompareTreesDiffCreator.new(
        base_repo: @base_repo,
        head_repo: @head_repo,
        base_revision: @feature_sha,
        head_revision: head_sha,
      )
      base_result = diff_creator.base_file_contents
      paths = base_result.map { |r| r[:path] }
      assert_same_elements ["empty_file", "renamed.txt"], paths

      head_result = diff_creator.head_file_contents
      paths = base_result.map { |r| r[:path] }
      assert_same_elements ["empty_file", "renamed.txt"], paths
    end
  end

  context "#copilot_content_exclusion_paths" do
    test "returns an empty list when there are no content exclusions" do
      diff_creator = PullRequests::Copilot::CompareTreesDiffCreator.new(
        base_repo: @base_repo,
        head_repo: @head_repo,
        base_revision: @master_sha,
        head_revision: @feature_sha,
      )

      assert_empty diff_creator.copilot_content_exclusion_paths
    end

    test "returns a list of excluded file paths" do
      diff_creator = PullRequests::Copilot::CompareTreesDiffCreator.new(
        base_repo: @base_repo,
        head_repo: @head_repo,
        base_revision: @master_sha,
        head_revision: @feature_sha,
      )

      ## Create ignore rules for this repo
      Copilot::ContentExclusionConfiguration.create(
        resource: @base_repo,
        updated_by: @user,
        resource_type: "Repository",
        document: "- /**/*.txt"
      )

      assert_same_elements ["test2.txt", "second-file.txt"], diff_creator.copilot_content_exclusion_paths
    end
  end
end
