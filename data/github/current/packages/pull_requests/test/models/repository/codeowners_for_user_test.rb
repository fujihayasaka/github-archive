# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCodeownersForUserTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "owner", plan: "large"
    @user = create(:user)
    @reviewer = create(:user, login: "reviewer")
    @org = create :organization, login: "acme", admin: @user
    @collab_1     = create :user, login: "collab-1"
    @collab_2     = create :user, login: "collab-2"
    @collab_3     = create :user, login: "collab-3"
    @child_collab = create :user, login: "collab-child"
    @team = create(:team, organization: @org, name: "Employee", privacy: :closed)
    @child_team = create(:team, organization: @org, name: "Child", privacy: :closed, parent_team_id: @team.id)
    @secret_team = create(:team, organization: @org, name: "Secret")

    @repo = create :repository, owner: @org, from_example: :rebase_pull_request
    @repo.add_member @user
    @repo.add_member @collab_1
    @repo.add_member @collab_2
    @repo.add_member @collab_3, action: :read
    @repo.add_member @child_collab
    @repo.add_member @owner
    @team.add_member @collab_1
    @team.add_repository(@repo, :push)
    @child_team.add_member @child_collab

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

  context "#owned_path?" do
    test "is false when there's no code owners" do
      pull = PullRequest.create_for! @repo,
        base: "acme:master",
        head: "acme:readme-title",
        user: @user,
        title: "Update README title"

      refute pull.reload.codeowners.owned_by?(owner: @collab_1, path: "README")
    end

    test "is false when user is nil" do
      commit_codeowners_file(<<~CODEOWNERS, ref: "master")
        * @collab-1
      CODEOWNERS

      pull = PullRequest.create_for! @repo,
        base: "acme:master",
        head: "acme:readme-title",
        user: @user,
        title: "Update README title"

      refute pull.reload.codeowners.owned_by?(owner: nil, path: "README")
    end

    test "is true when code owners has requested the user's review on that file (from pattern)" do
      commit_codeowners_file(<<~CODEOWNERS, ref: "master")
        * @collab-1
      CODEOWNERS

      pull = PullRequest.create_for! @repo,
        base: "acme:master",
        head: "acme:readme-title",
        user: @user,
        title: "Update README title"

      assert pull.codeowners.owned_by?(owner: @collab_1, path: "README")
      refute pull.codeowners.owned_by?(owner: @collab_2, path: "README")
    end

    test "is true when the code owners has requested a user's team on that file" do
      commit_codeowners_file(<<~CODEOWNERS, ref: "master")
        * @#{@team.combined_slug}
      CODEOWNERS

      pull = PullRequest.create_for! @repo,
        base: "acme:master",
        head: "acme:readme-title",
        user: @user,
        title: "Update README title"

      assert pull.codeowners.owned_by?(owner: @collab_1, path: "README")
      refute pull.codeowners.owned_by?(owner: @collab_2, path: "README")
    end

    test "is true when the code owners has requested a user's parent team on that file" do
      commit_codeowners_file(<<~CODEOWNERS, ref: "master")
        * @#{@team.combined_slug}
      CODEOWNERS

      pull = PullRequest.create_for! @repo,
        base: "acme:master",
        head: "acme:readme-title",
        user: @user,
        title: "Update README title"

      assert pull.codeowners.owned_by?(owner: @collab_1, path: "README")
      assert pull.codeowners.owned_by?(owner: @child_collab, path: "README")
    end

    test "is false when the code owners has not requested the user's review on that file" do
      commit_codeowners_file(<<~CODEOWNERS, ref: "master")
        *.js @collab-1
        *.rb @collab-2
      CODEOWNERS

      @repo.refs.find("readme-title").append_commit({ message: "Update files", committer: @user }, @user) do |files|
        files.add("test.rb", "New content #{Time.now.to_i}")
        files.add("test.js", "New content #{Time.now.to_i}")
      end

      pull = PullRequest.create_for! @repo,
        base: "acme:master",
        head: "acme:readme-title",
        user: @user,
        title: "Update README title"

      assert pull.codeowners.owned_by?(owner: @collab_1, path: "test.js")
      refute pull.codeowners.owned_by?(owner: @collab_1, path: "test.rb")
      assert pull.codeowners.owned_by?(owner: @collab_2, path: "test.rb")
      refute pull.codeowners.owned_by?(owner: @collab_2, path: "test.js")
    end
  end
end
