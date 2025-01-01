# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCodeownersForPathTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "owner", plan: "large"
    @user = create(:user)
    @reviewer = create(:user, login: "reviewer")
    @org = create :organization, login: "acme", admin: @user
    @collab_1     = create :user, login: "collab-1"
    @collab_2     = create :user, login: "collab-2"
    @collab_3     = create :user, login: "collab-3"
    @collab_4     = create :user, login: "collab-4"
    @team = create(:team, organization: @org, name: "Employee", privacy: :closed)
    @secret_team = create(:team, organization: @org, name: "Secret")

    @repo = create :repository, owner: @org, from_example: :rebase_pull_request
    @repo.add_member @user
    @repo.add_member @collab_1
    @repo.add_member @collab_2
    @repo.add_member @collab_3, action: :read
    @repo.add_member @collab_4
    @repo.add_member @owner
    @team.add_member @collab_1
    @team.add_repository(@repo, :push)

    @issue = create(:issue, repository: @repo, user: @owner)

    @protected_branch = create(:protected_branch, repository: @repo, creator: @owner)

    @pull = create :pull_request,
      repository:       @repo,
      base_repository:  @repo,
      base_user:        @repo.owner,
      base_ref:         "master",
      head_repository:  @repo,
      head_user:        @repo.owner,
      head_ref:         "contrib",
      issue:            @issue,
      draft:            false
  end

  setup do
    reset_repo_root
    example_repo :rebase_pull_request, @repo
  end

  def commit_codeowners_file(contents, ref: "master")
    @repo.refs.find(ref).append_commit({ message: "Add CODEOWNERS file", committer: @user }, @user) do |files|
      files.add("CODEOWNERS", contents)
    end
  end

  def commit_readme_changes(pull, base_or_head)
    repo = pull.send(:"#{base_or_head}_repository")
    ref_name = pull.send(:"#{base_or_head}_ref")

    perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      repo.refs.find(ref_name).append_commit({ message: "Update README", committer: @user }, @user) do |files|
        files.add("README", "New content #{Time.now.to_i}")
      end
    end
  end

  context "#owners_for_path" do
    test "is empty when no codeowners" do
      commit_codeowners_file(<<~CODEOWNERS, ref: "master")
        NOPE @collab-1
      CODEOWNERS

      pull = PullRequest.create_for! @repo,
        base: "acme:master",
        head: "acme:readme-title",
        user: @user,
        title: "Update README title"

      assert_predicate pull.reload.codeowners.owners_for_path("README"), :empty?
    end

    test "contains users" do
      commit_codeowners_file(<<~CODEOWNERS, ref: "master")
        * @collab-1
      CODEOWNERS

      pull = PullRequest.create_for! @repo,
        base: "acme:master",
        head: "acme:readme-title",
        user: @user,
        title: "Update README title"

      assert_equal [@collab_1], pull.codeowners.owners_for_path("README")
    end

    test "contains teams" do
      commit_codeowners_file(<<~CODEOWNERS, ref: "master")
        * @#{@team.combined_slug}
      CODEOWNERS

      pull = PullRequest.create_for! @repo,
        base: "acme:master",
        head: "acme:readme-title",
        user: @user,
        title: "Update README title"

      assert_equal [@team], pull.codeowners.owners_for_path("README")
    end

    test "owners aren't duplicated when path matches multiple rules" do
      commit_codeowners_file(<<~CODEOWNERS, ref: "master")
        *       @collab-1
        README  @collab-1
      CODEOWNERS

      # Add a new file that matches the `*` rule. The list of matching rules is
      # later looped over and matched against to build the list of owners by paths.
      @repo.refs.find("readme-title").append_commit({ message: "Add another file", committer: @user }, @user) do |files|
        files.add("another.txt", "this is another file")
      end

      pull = PullRequest.create_for! @repo,
        base: "acme:master",
        head: "acme:readme-title",
        user: @user,
        title: "Update README title"

      assert_equal [@collab_1], pull.codeowners.owners_for_path("README")
    end

    test "lower-precedence owners for a path aren't included" do
      commit_codeowners_file(<<~CODEOWNERS, ref: "master")
        *       @collab-1
        READM*  @#{@team.combined_slug}
        README  @collab-2 @collab-4
      CODEOWNERS

      # Add a new file that matches the `*` rule. The list of matching rules is
      # later looped over and matched against to build the list of owners by paths.
      @repo.refs.find("readme-title").append_commit({ message: "Add another file", committer: @user }, @user) do |files|
        files.add("another.txt", "this is another file")
        files.add("FEADME", "too hungry to spell")
        files.add("READMOI", "who me?")
      end

      pull = PullRequest.create_for! @repo,
        base: "acme:master",
        head: "acme:readme-title",
        user: @user,
        title: "Update README title"

      assert_same_elements [@collab_2, @collab_4], pull.codeowners.owners_for_path("README")
    end
  end
end
