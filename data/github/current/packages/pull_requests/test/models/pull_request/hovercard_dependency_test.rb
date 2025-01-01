# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestHovercardDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @anon = create(:user)

    @org = create(:organization, admin: @user)
    @member = create(:user).tap { |u| @org.add_member(u) }
    @member2 = create(:user).tap { |u| @org.add_member(u) }

    @team = create(:team, organization: @org, privacy: :closed)
    @secret_team = create(:team, organization: @org, privacy: :secret)

    # Create a prior PR
    other_repo = create(:repository, owner: @user, from_example: :pull_request_source)
    @first_ever_pr = PullRequest.create_for!(other_repo, title: "hello", user: @user, base: "master", head: "topic-partial-merge")

    # Create a PR
    @private_repo = create(:private_repository, owner: @org, from_example: :pull_request_source)
    @pull_request = PullRequest.create_for!(@private_repo, title: "hello", user: @user, base: "master", head: "topic-partial-merge")
  end

  setup do
    Spokesd.enable_spokesd
  end

  context "user_hovercard_parent" do
    test "returns the containing repository" do
      assert_equal @private_repo, @pull_request.user_hovercard_parent
    end
  end

  context "creator context" do
    context "when the user has less repositories than REPO_LIMIT_FOR_ORG_HOVERCARD" do
      test "returns status if this is the first user PR in the org" do
        context = @pull_request.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

        assert_equal "Opened this pull request (their first in @#{@org})", context.message

        # not visible if the viewer cannot view the repo
        assert_nil @pull_request.user_hovercard_context_for(@user, viewer: @anon, limit: :creator)
        assert_nil @pull_request.user_hovercard_context_for(@user, viewer: nil, limit: :creator)
      end
    end

    context "when the user has pull requests greater than REPO_LIMIT_FOR_ORG_HOVERCARD" do
      test "returns status if this is the first user PR in the org" do
        PullRequest::HovercardDependency.stub_const(:REPO_LIMIT_FOR_ORG_HOVERCARD, 1) do
          context = @pull_request.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

          assert_equal "Opened this pull request (their first in #{@private_repo.nwo})", context.message

          # not visible if the viewer cannot view the repo
          assert_nil @pull_request.user_hovercard_context_for(@user, viewer: @anon, limit: :creator)
          assert_nil @pull_request.user_hovercard_context_for(@user, viewer: nil, limit: :creator)
        end
      end

      test "returns status if the creator has created other PRs in this repo & org" do
        PullRequest::HovercardDependency.stub_const(:REPO_LIMIT_FOR_ORG_HOVERCARD, 1) do
          second_pr_in_repo = PullRequest.create_for!(@private_repo, title: "hello", user: @user, base: "master", head: "master-forward-2")

          context = second_pr_in_repo.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

          assert_equal "Opened this pull request", context.message
        end
      end
    end

    test "returns status if this is the first PR the user ever created" do
      context = @first_ever_pr.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Opened this pull request (their first ever)", context.message
    end

    test "returns status if this is the first user PR in this repo, but not the first in the org" do
      other_repo = create(:private_repository, owner: @org, from_example: :pull_request_source)
      first_pr_in_other_org_repo = PullRequest.create_for!(other_repo, title: "hello", user: @user, base: "master", head: "topic-partial-merge")

      context = first_pr_in_other_org_repo.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Opened this pull request (their first in #{other_repo.nwo})", context.message
    end

    test "returns status if the creator has created other PRs in this repo & org" do
      second_pr_in_repo = PullRequest.create_for!(@private_repo, title: "hello", user: @user, base: "master", head: "master-forward-2")

      context = second_pr_in_repo.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Opened this pull request", context.message
    end

    test "returns status if this is the first user PR in a non-org repo" do
      # ensure it does not get confused with contributions to other non-org repos
      other_user_repo = create(:repository, owner: @user, from_example: :pull_request_source)
      PullRequest.create_for!(other_user_repo, title: "hello", user: @user, base: "master", head: "master-forward-2")

      # create first contribution in another repo
      user_repo = create(:repository, owner: @user, from_example: :pull_request_source)
      first_pr = PullRequest.create_for!(user_repo, title: "hello", user: @user, base: "master", head: "master-forward-2")

      context = first_pr.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_equal "Opened this pull request (their first in #{user_repo.nwo})", context.message
    end

    test "returns nil if the repository is private and viewer is not a member that can view the pull request" do
      context = @pull_request.user_hovercard_context_for(@user, viewer: @anon, limit: :creator)

      assert_nil context
    end

    test "returns nil if the user has no relation to the pull request" do
      context = @pull_request.user_hovercard_context_for(@anon, viewer: @user, limit: :creator)

      assert_nil context
    end

    # See https://github.com/github/github/issues/87599
    test "returns nil if the pull request doesn't have an issue" do
      @pull_request.issue.delete
      @pull_request.reload
      assert_nil @pull_request.issue

      context = @pull_request.user_hovercard_context_for(@user, viewer: @user, limit: :creator)

      assert_nil context
    end
  end

  context "codeowner context" do
    test "returns a status if the user is a codeowner" do
      @private_repo.heads.find(@pull_request.base_ref).append_commit({ message: "add codeowner", committer: @user }, @user) do |files|
        files.add("CODEOWNERS", "file3 @#{@user}")
      end

      context = @pull_request.user_hovercard_context_for(@user, viewer: @user, limit: :codeowner)

      assert_equal "Code owner of 1 file in this pull request", context.message

      # not viewable by a non-org member
      assert_nil @pull_request.user_hovercard_context_for(@user, viewer: @anon, limit: :codeowner)
      assert_nil @pull_request.user_hovercard_context_for(@user, viewer: nil, limit: :codeowner)
    end

    test "returns a status if the user is a codeowner through a team that has write access" do
      @team.add_member(@user)
      @team.add_repository(@private_repo, :push)

      @private_repo.refs.find(@pull_request.base_ref).append_commit({ message: "add codeowner", committer: @user }, @user) do |files|
        files.add("CODEOWNERS", "file3 @#{@team.combined_slug}")
      end

      context = @pull_request.user_hovercard_context_for(@user, viewer: @member, limit: :codeowner)

      assert_equal "Code owner of 1 file in this pull request", context.message
    end

    test "returns no status if the user is a codeowner through a team that has write access but is secret" do
      @secret_team.add_member(@user)
      @secret_team.add_repository(@private_repo, :push)

      @private_repo.refs.find(@pull_request.base_ref).append_commit({ message: "add codeowner", committer: @user }, @user) do |files|
        files.add("CODEOWNERS", "file3 @#{@secret_team.combined_slug}")
      end

      context = @pull_request.user_hovercard_context_for(@user, viewer: @member, limit: :codeowner)

      assert_nil context
    end

    test "returns no status if the user is a codeowner but they have no write permission on the repository" do
      @org.add_member(@anon)

      @private_repo.refs.find(@pull_request.base_ref).append_commit({ message: "add codeowner", committer: @user }, @user) do |files|
        files.add("CODEOWNERS", "file3 @#{@anon}")
      end

      context = @pull_request.user_hovercard_context_for(@anon, viewer: @user, limit: :codeowner)

      assert_nil context
    end

    test "returns no status if the user is a codeowner but the file they own is not changed in this PR" do
      @private_repo.add_member(@anon)

      @private_repo.refs.find(@pull_request.base_ref).append_commit({ message: "add codeowner", committer: @user }, @user) do |files|
        files.add("CODEOWNERS", "another-path @#{@anon}")
      end

      context = @pull_request.user_hovercard_context_for(@anon, viewer: @user, limit: :codeowner)

      assert_nil context
    end

    test "doesn't blow up if it has trouble detrmining codeowners for the PR" do
      @private_repo.heads.find(@pull_request.base_ref).append_commit({ message: "add codeowner", committer: @user }, @user) do |files|
        files.add("CODEOWNERS", "file3 @#{@user}")
      end

      @pull_request.historical_comparison.init_diffs.stubs(:deltas).raises(GitRPC::ObjectMissing)
      # stub for asynchronous version
      GitHub::Diff.any_instance.stubs(:deltas).raises(GitRPC::ObjectMissing)

      context = assert_nothing_raised do
        @pull_request.user_hovercard_context_for(@user, viewer: @user, limit: :codeowner)
      end

      assert_nil context
    end
  end

  context "recency context" do
    test "returns a status if the user has edited or reviewed these files recently" do
      # Edits and reviews on a PR before this one
      @private_repo.refs.find(@pull_request.base_ref).append_commit({ message: "change", committer: @user }, @user) { |f| f.add("file", "this is not the file 3") }

      # A PR to ask questions about
      ref = @private_repo.refs.find("refs/heads/new-branch") || @private_repo.refs.create("refs/heads/new-branch", @private_repo.heads.find(@pull_request.base_ref).target_oid, @member)
      ref.append_commit({ message: "change", committer: @member }, @member) { |f| f.add("file", "you're looking for") }
      second_pr = PullRequest.create_for!(@private_repo, title: "2", user: @member, base: "master", head: "new-branch")

      # Status for a user that edited files in the first PR
      context = second_pr.user_hovercard_context_for(@user, viewer: @member, limit: :recency)
      assert_equal "Recently edited these files", context.message

      # not viewable by non-org member
      assert_nil second_pr.user_hovercard_context_for(@user, viewer: @anon, limit: :recency)
      assert_nil second_pr.user_hovercard_context_for(@user, viewer: nil, limit: :recency)
    end

    test "does not return a status if the user has edited the file but it was too long ago" do
      # Edits and reviews on a PR before this one
      @private_repo.refs.find(@pull_request.base_ref).append_commit({ message: "change", committer: @user, committed_date: 1.year.ago.iso8601 }, @user) do |f|
        f.add("file", "change to file 3")
      end

      # A PR to ask questions about
      ref = @private_repo.refs.find("refs/heads/new-branch-2") || @private_repo.refs.create("refs/heads/new-branch-2", @private_repo.heads.find(@pull_request.base_ref).target_oid, @member)
      ref.append_commit({ message: "change", committer: @member }, @member) { |f| f.add("file", "you're looking for") }
      second_pr = PullRequest.create_for!(@private_repo, title: "2", user: @member, base: "master", head: "new-branch-2")

      # Status for a user that edited files in the first PR
      assert_nil second_pr.user_hovercard_context_for(@user, viewer: @member, limit: :recency)
    end
  end
end
