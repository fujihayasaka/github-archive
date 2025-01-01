# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::StatusChecksControllerTest < GitHub::IntegrationTestCase
  include ResiliencyHelpers

  fixtures do
    @owner = create(:user, login: "wiseguy")
    @forker = create(:user, :verified, login: "forker")
    @rando  = create(:user)

    @source = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
    @source.add_member @forker, action: :write

    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, create_owner: true, from_example: :review_comment_fork)

    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    @public_source = create(:public_repository, owner: @owner, name: "public source", from_example: :pr_mergeability)

    @issue = create(:issue, user: @owner, repository: @source, title: "A Title")
    @public_issue = create(:issue, user: @owner, repository: @public_source, title: "A Title")
    @public_pull = create(:pull_request,
        repository: @public_source,
        base_repository: @public_source,
        base_user: @public_source.owner,
        base_ref: "master",
        head_repository: @public_source,
        head_user: @public_source.owner,
        head_ref: "ahead",
        issue:  @public_issue,
        user: @owner
    )

    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @source,
        head_user: @source.owner,
        head_ref: "topic",
        issue: @issue,
        user: @owner
      )

    @no_status_pr =
      create(:pull_request,
        repository: @fork,
        base_repository: @fork,
        base_user: @fork.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        user: @forker
      )

    #statusContext
    @oauth_application = create(:oauth_application, name: "Lofty-CI", url: "https://lofty-ci.com/")
    @status_context1 = create(:status,
      oauth_application: @oauth_application,
      repository: @source,
      creator: @source.owner,
      sha: @pull.head_sha,
      context: "context1",
      state: "success",
      description: "yeah #3",
      target_url: "https://github.com/"
    )
    @status_context2 = create(:status,
      oauth_application: @oauth_application,
      repository: @source,
      creator: @source.owner,
      sha: @pull.head_sha,
      context: "context2",
      state: "pending",
      description: "yeah #2",
      target_url: "https://github.com/"
    )

    github_app = create :integration, default_permissions: { "checks" => :write }
    check_suite = create(:check_suite, repository: @source, github_app: github_app, head_sha: @pull.head_sha)
    @check_run1  = create(:check_run, name: "foo", check_suite: check_suite, status: :completed, completed_at: Time.now, conclusion: :success)

    # required Workflow
    github_app2 = create :integration, default_permissions: { "checks" => :write }
    workflow_check_suite = create(:check_suite_for_actions_app,
      :success,
      repository: @source,
      github_app: github_app2,
      workflow_file_path: "required/#{@source.id}/.github/workflows/req_workflow1.yml",
      name: "Required Ruleset Workflow 1",
      head_sha: @pull.head_sha
    )

    @org_2 = create(:enterprise_linked_organization, admin: @admin)
    @source_repo = create(:internal_repository, owner: @org_2, from_example: :simple)
    @target_repo = create(:repository, owner: @org_2, from_example: :pull_request_source)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    @org_2.stubs(:actions_enabled?).returns(true)
    GitHub.stubs(:launch_github_app).returns(@launch_app)
  end

  test "returns not found if user is not logged in", skip_with_all_emus: true do
    get "#{GitHub.url}/#{@public_pull.repository.name_with_display_owner}/pull/#{@public_pull.number}/page_data/status_checks", xhr: true
    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal "Not Found", json["error"]
  end

  test "returns 200 response even if there are no checks" do
    as @no_status_pr.user
    get "#{GitHub.url}/#{@no_status_pr.repository.name_with_display_owner}/pull/#{@no_status_pr.number}/page_data/status_checks", xhr: true

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 0, json["statusChecks"].count
  end

  test "returns 404 for user without read access to the repository" do
    as @rando
    get "#{GitHub.url}/#{@no_status_pr.repository.name_with_display_owner}/pull/#{@no_status_pr.number}/page_data/status_checks", xhr: true

    assert_response :not_found
  end

  test "returns 404 if pull request is not found" do
    as @owner
    non_existent_pr = "0" * 40
    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{non_existent_pr}/page_data/status_checks", xhr: true

    assert_response :not_found
  end

  test "returns 200 response for status checks" do
    as @pull.user
    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/status_checks", xhr: true

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal 4, json["statusChecks"].count
    assert_same_elements(
      [{ "count" => 3, "state" => "SUCCESS" }, { "count" => 1, "state" => "PENDING" }],
      json["statusRollup"]["summary"]
    )
  end

  test "returns 200 response for workflow runs" do
    @source_repo.set_actions_repository_share_policy(
      policy: Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_ORGANIZATION,
      actor: @owner
    )

    ruleset_workflow_path = ".github/workflows/test.yml"
    ruleset_workflow_ref = @source_repo.heads.read(@source_repo.default_branch)

    ruleset_workflow_ref.append_commit({ message: "add workflow", committer: @source_repo.owner.admin }, @source_repo.owner) do |files|
      files.add(ruleset_workflow_path, "some content")
    end

    ruleset = create :repository_ruleset, source: @org_2
    configuration = create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
      workflows: [{
        repository_id: @source_repo.id,
        path: ruleset_workflow_path,
        ref: "refs/heads/#{@source_repo.default_branch}"
      }]
    })

    before = @target_repo.heads[@target_repo.default_branch].target_oid
    after = @target_repo.commits.create({ message: "New commit", committer: @target_repo.owner }, before) do |files|
      files.add "New file", "New file"
    end.oid

    pull = create :pull_request, :with_mergeable_head, repository: @target_repo
    check_suite = create(:check_suite_for_actions_app, repository: @target_repo, head_sha: pull.head_sha, name: "CI", event: "pull_request", workflow_file_path: "required/#{@source_repo.id}/#{ruleset_workflow_path}")
    check_run = create :check_run_for_actions_app, check_suite: check_suite, name: "req-workflow-context1", status: "pending", conclusion: nil

    CheckSuite.any_instance.stubs(:imposer_repo_id).returns(@source_repo.id)
    Actions::WorkflowRun.any_instance.stubs(:workflow_file_ref).returns("refs/heads/#{@source_repo.default_branch}")

    as pull.user
    get "#{GitHub.url}/#{pull.repository.name_with_display_owner}/pull/#{pull.number}/page_data/status_checks", xhr: true

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal 1, json["statusChecks"].count
  end

  test "returns 500 response when required clusters fail" do
    prevent_connections_to(ApplicationRecord::RepositoriesActionsChecks) do
      as @pull.user
      get "/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/status_checks", xhr: true

      assert_response :internal_server_error
    end
  end

  test "it fails when rate limited", skip_unless: :rate_limiting_enabled? do
    expected_key = "pull_requests/page_data/shared_controller.status_checks:#{@pull.user.id}"
    expected_opts = {
      max_tries: 400,
      ttl: 1.minute.to_i,
    }

    PullRequests::PageData::SharedController.any_instance.expects(:rate_limit_increment_limited?).with(expected_key, expected_opts).once.returns(true)

    as @pull.user
    get "/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/status_checks", xhr: true
    assert_equal 429, response.status
  end

  test "can pass in avatar_size param to set avatar_url field" do
    as @pull.user
    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/status_checks?avatar_size=20", xhr: true

    assert_response :success
  end

  test "returns 406 if not an xhr request" do
    as @pull.user

    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/status_checks"

    assert_response :not_acceptable
  end

  context "with workflows pending approval" do
    test "returns the workflow pending approval data rollup" do
      create(:check_suite_for_actions_app, repository: @pull.repository, head_sha: @pull.head_sha, conclusion: :action_required)

      as @pull.user
      get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/status_checks", xhr: true

      assert_response :success
      json = JSON.parse(response.body)
      assert json["statusRollup"]["pendingWorkflowApprovalRollup"]
    end
  end
end
