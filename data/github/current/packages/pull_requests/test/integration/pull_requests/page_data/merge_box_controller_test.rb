# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::MergeBoxControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @owner = create(:user, login: "wiseguy")
    @rando  = create(:user)
    @source = create(:repository, owner: @owner, name: "source", from_example: :pr_mergeability)
    @private_repo = create(:private_repository, name: "repo", owner: @owner, from_example: :pull_request_source)
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
        head_ref: "ahead",
        issue: @issue,
        user: @owner
      )

    @pull_behind_and_conflicted =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @source,
        head_user: @source.owner,
        head_ref: "behind-and-conflicted",
        user: @owner,
        title: "PR that is behind base branch with conflicts",
        body: "can't be nil",
        )

    @private_pull = create(:pull_request, :with_mergeable_head, repository: @private_repo, user: @owner)
  end

  test "returns not found if user is not logged in", skip_with_all_emus: true do
    get "#{GitHub.url}/#{@public_pull.repository.name_with_display_owner}/pull/#{@public_pull.number}/page_data/merge_box", xhr: true
    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal "Not Found", json["error"]
  end

  test "returns 200 for a valid request and basic fields" do
    @pull.create_merge_commit
    as @owner

    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/merge_box", xhr: true

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "MERGEABLE", json["mergeRequirements"]["state"]
    assert_equal @owner.git_author_email, json["mergeRequirements"]["defaultCommitAuthorEmail"]
    commit_message = @pull.determine_merging_message(:merge, nil, nil)
    assert_equal commit_message[0], json["mergeRequirements"]["commitMessageHeadline"]
    assert_equal commit_message[1], json["mergeRequirements"]["commitMessageBody"]
  end

  test "returns 404 for user without read access to the repository" do
    as @rando
    get "#{@private_pull.url}/page_data/merge_box", xhr: true

    assert_response_not_found
  end

  test "returns 404 if pull request is not found" do
    as @owner
    get "#{@pull.url}000/page_data/merge_box", xhr: true

    assert_response_not_found
  end

  test "returns rule conditions for a failed rule suite" do
    @pull.create_merge_commit

    ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @source)
    create(:repository_rule_configuration, :update, repository_ruleset: ruleset)

    as @owner

    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/merge_box", xhr: true

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "UNMERGEABLE", json["mergeRequirements"]["state"]

    rule_condition = json["mergeRequirements"]["conditions"].find { |c| c["type"] == "PULL_REQUEST_RULES" }
    assert_equal "FAILED", rule_condition["result"]
    assert_equal "FAILED", rule_condition["ruleRollups"].find { |r| r["ruleType"] == "UPDATE" }["result"]
  end

  test "returns rule conditions for a merge conflict" do
    @pull_behind_and_conflicted.create_merge_commit
    as @owner

    get "#{GitHub.url}/#{@pull_behind_and_conflicted.repository.name_with_display_owner}/pull/#{@pull_behind_and_conflicted.number}/page_data/merge_box", xhr: true

    assert_response :ok
    json = JSON.parse(response.body)

    assert_equal "UNMERGEABLE", json["mergeRequirements"]["state"]
    assert condition = json["mergeRequirements"]["conditions"].find { |c| c["type"] == "PULL_REQUEST_MERGE_CONFLICT_STATE" }
    assert_same_elements ["file2.txt"], condition["conflicts"]
    assert_equal "PULL_REQUEST_MERGE_CONFLICT_STATE", condition["type"]
    assert condition["isConflictResolvableInWeb"]
    assert condition["webEditorConflictResolution"]["viewerCanResolve"]
  end

  test "returns rule conditions for a merge conflict that cannot be resolved in the web" do
    @pull_behind_and_conflicted.create_merge_commit
    # create a complex conflict that cannot be resolved in web editor
    @pull_behind_and_conflicted.store_conflicts({
      base: @pull_behind_and_conflicted.mergeable_base_sha,
      head: @pull_behind_and_conflicted.mergeable_head_sha,
      conflicted_files: {
        "file2.txt" => { "type" => "not_regular_conflict" },
      },
      conflict_type: :merge_conflict,
    })
    as @owner

    get "#{GitHub.url}/#{@pull_behind_and_conflicted.repository.name_with_display_owner}/pull/#{@pull_behind_and_conflicted.number}/page_data/merge_box", xhr: true

    assert_response :ok
    json = JSON.parse(response.body)

    assert_equal "UNMERGEABLE", json["mergeRequirements"]["state"]
    assert condition = json["mergeRequirements"]["conditions"].find { |c| c["type"] == "PULL_REQUEST_MERGE_CONFLICT_STATE" }
    assert_same_elements ["file2.txt"], condition["conflicts"]
    assert_equal "PULL_REQUEST_MERGE_CONFLICT_STATE", condition["type"]
    refute condition["isConflictResolvableInWeb"]

    web_conflict_resolution = condition["webEditorConflictResolution"]
    refute web_conflict_resolution["viewerCanResolve"]
    assert_equal "TOO_COMPLEX", web_conflict_resolution["viewerCannotResolve"]["reason"]
    assert_equal "These conflicts are too complex to resolve in the web editor.", web_conflict_resolution["viewerCannotResolve"]["message"]
  end

  test "does not return mergeRequirements for a closed PR" do
    T.must(@pull.issue).update(state: "closed")
    @pull.reload
    as @owner

    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/merge_box", xhr: true

    assert_response :ok
    json = JSON.parse(response.body)

    refute json["mergeRequirements"]
    assert_equal "CLOSED", json["pullRequest"]["state"]
  end

  test "accepts and handles requests with params for merge_method, merge_action, and bypass_requirements" do
    @pull.create_merge_commit

    ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @source)
    create(:repository_rule_configuration, :update, repository_ruleset: ruleset)

    as @owner

    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/merge_box?merge_method=MERGE", xhr: true

    assert_response :ok

    as @owner

    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/merge_box?merge_action=DIRECT_MERGE", xhr: true

    assert_response :ok

    as @owner

    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/merge_box?bypass_requirements=TRUE", xhr: true

    assert_response :ok
  end

  test "returns 406 if not an xhr request" do
    as @owner

    get "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/merge_box"

    assert_response :not_acceptable
  end
end
