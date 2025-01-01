# typed: true
# frozen_string_literal: true
require "test_helper"

class RepositoryActionRunTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)

    @user = create(:staff_admin_user)
    @repo = create :repository, owner: @user, name: "hello-world", from_example: :rebase_pull_request

    # Use existing git repo `rebase_pull_request`
    # Which lives in test/fixtures/git/examples/rebase_pull_request.git

    @another_repo = create :repository, owner: @user, name: "hello-other-world", from_example: :rebase_pull_request
    make_integration_installation(integration: @launch_app, repositories: [@repo, @another_repo])

    # Use existing git repo `rebase_pull_request`
    # Which lives in test/fixtures/git/examples/rebase_pull_request.git

    @repo_action = create(:repository_action, name: "Action Name", repository: @repo, icon_name: "github", color: "ASDFJ4",
                        description: "This is my description about this action", path: "somewhere/to/somewhere/Dockerfile")
    @repo_action_in_root = create(:repository_action, name: "Action At Root", repository: @repo, icon_name: "github", color: "ASDFJ4",
                        description: "This is my description about this action", path: "Dockerfile")
    @local_only_action = create(:repository_action, name: "Local Action in .github", repository: @repo, icon_name: "github", color: "ASDFJ4",
                        description: "This is my description about this action", path: ".github/lint/Dockerfile")

    # "<user>/<repo>@<commit-ish>" /* path defaults to ""
    @repo_head_oid_path = "#{@repo.nwo}@THIS_IS_A_SHA"

    # <user>/<repo>/<path>@<commit-ish>
    @repo_head_base_path = "#{@repo.nwo}/#{@repo_action.base_path}@THIS_IS_A_SHA"

    # "./path/to/dir" /* repo = "<current repo>", ref is always "<current ref>" */
    @repo_head_local_path = "./#{@repo_action.base_path}"
    GitHub.stubs(:launch_github_app).returns(@launch_app)
  end

  context "external use" do
    test "action is default path" do
      check_run_external_id_test(uses: @repo_head_oid_path, repo_action: @repo_action_in_root, repo: @another_repo)
    end

    test "action is in a folder" do
      check_run_external_id_test(uses: @repo_head_base_path, repo_action: @repo_action, repo: @another_repo)
    end

    test "action within same repo" do
      check_run_external_id_test(uses: @repo_head_local_path, repo_action: @repo_action, repo: @repo_action.repository)
    end
  end

  context "local use" do
    test "action is in a folder" do
      check_run_external_id_test(uses: "./#{@repo_action.base_path}", repo_action: @repo_action, repo: @repo_action.repository)
    end

    test "action within same repo" do
      check_run_external_id_test(uses: "./#{@local_only_action.base_path}", repo_action: @local_only_action, repo: @local_only_action.repository)
    end
  end

  def check_run_external_id_test(uses:, repo_action:, repo:)
    check_suite2 = create :check_suite, github_app: GitHub.launch_github_app, repository: repo
    valid_run = create :check_run, check_suite: check_suite2, external_id: uses, name: "heroku deploy"
    invalid_run = create :check_run, check_suite: check_suite2, external_id: "SOME_RANDOM_ID", name: "Mr.Task"

    action_runs = repo_action.action_runs
    assert_equal(1, action_runs.length, "expect to see 1 action run.")
    assert_equal valid_run, action_runs[0]
  end

end unless GitHub.enterprise?
