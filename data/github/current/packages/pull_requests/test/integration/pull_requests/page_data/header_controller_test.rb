# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::HeaderControllerTest < GitHub::IntegrationTestCase
  include ResiliencyHelpers

  fixtures do
    @owner = create(:user, login: "wiseguy")
    @no_write_permissions_user = create(:user, login: "noWritePermissions")
    @blocked_user = create(:user, login: "blockedUser")

    @public_source = create(:public_repository, owner: @owner, name: "public source", from_example: :review_comment_fork)
    @private_source = create(:private_repository, owner: @owner, name: "secret source", from_example: :review_comment_fork)

    @public_source.add_member(@blocked_user)

    public_issue = create(:issue, user: @owner, repository: @public_source, title: "A Title")
    private_issue = create(:issue, user: @owner, repository: @private_source, title: "A Title")
    @public_pull =
      create(:pull_request,
        repository: @public_source,
        base_repository: @public_source,
        base_user: @public_source.owner,
        base_ref: "master",
        head_repository: @public_source,
        head_user: @public_source.owner,
        head_ref: "topic",
        issue: public_issue,
        user: @public_source.owner
      )
    @private_pull =
      create(:pull_request,
        repository: @private_source,
        base_repository: @private_source,
        base_user: @private_source.owner,
        base_ref: "master",
        head_repository: @private_source,
        head_user: @private_source.owner,
        head_ref: "topic",
        issue: private_issue,
        user: @private_source.owner
      )

    @public_pr_url = "#{@public_pull.url}/page_data/header"
    @public_pr_incorrect_url = "#{@public_pull.url}123/page_data/header"
    @public_pr_update_title_url = "#{@public_pull.url}/page_data/update_title"
    @public_pr_change_base_url = "#{@public_pull.url}/page_data/change_base"

    @private_pr_url = "#{@private_pull.url}/page_data/header"
    @private_pr_incorrect_url = "#{@private_pull.url}123/page_data/header"

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  def successful_response_assertions(expected_title:, patch: false)
    assert_response_success
    json = JSON.parse(response.body)
    assert_equal expected_title, json["pullRequest"]["title"]
    unless patch
      # These assertions are based on the default pull request factory
      assert_equal 4, json["pullRequest"]["commitsCount"]
    end
  end

  def failure_response_text_assertion(expected_status:, expected_text:)
    assert_response expected_status
    json = JSON.parse(response.body)
    assert_equal expected_text, json["error"]
  end

  def get_candidate_base_branch(pull_request)
    available_branches = (pull_request.repository.heads.map(&:name) - [pull_request.head_ref, pull_request.base_ref])
    available_branches.sample
  end

  context "when logged into GitHub and with write permissions", feature_enabled: :prx_commits do
    test "returns header information as a logged in user on a public repo" do
      as @owner
      get @public_pr_url

      successful_response_assertions(expected_title: "A Title")
    end

    test "returns header information as a logged in user private repo" do
      as @owner
      get @private_pr_url

      successful_response_assertions(expected_title: "A Title")
    end

    test "returns a 404 when accessing a nonexistent PR in a public repo" do
      as @owner
      get @public_pr_incorrect_url

      failure_response_text_assertion(expected_status: :not_found,
                                      expected_text: "Not Found")
    end

    test "returns a 404 when accessing a nonexistent PR as a logged in user private repo" do
      as @owner
      get @private_pr_incorrect_url

      failure_response_text_assertion(expected_status: :not_found,
                                      expected_text: "Not Found")
    end

    test "does allow editing of a PR title" do
      as @owner
      patch @public_pr_update_title_url, params: { title: "New Title" }

      successful_response_assertions(expected_title: "New Title", patch: true)
    end

    test "params cannot be an empty string" do
      as @owner
      patch @public_pr_update_title_url, params: { title: "" }

      failure_response_text_assertion(expected_status: 422,
                                      expected_text: "Title can't be blank")
    end

    test "updating a title requires params" do
      as @owner
      patch @public_pr_update_title_url

      failure_response_text_assertion(expected_status: 422,
                                      expected_text: "Title can't be blank")
    end
  end

  # These tests are skippable in multitenant mode as it redirects to an SSO link
  context "when not logged into GitHub", skip_with_all_emus: true, feature_enabled: :prx_commits do
    test "returns header information without being a logged in user on public repo" do
      get @public_pr_url

      successful_response_assertions(expected_title: "A Title")
    end

    test "does not return header information without being a logged in user on a private repo" do
      get @private_pr_url

      failure_response_text_assertion(expected_status: :not_found,
                                      expected_text: "Not Found")
    end

    test "returns a 404 when accessing a nonexistent PR without being a logged in user on a public repo" do
      get @private_pr_url

      failure_response_text_assertion(expected_status: :not_found,
                                      expected_text: "Not Found")
    end

    test "does not allow editing of a PR title" do
      patch @public_pr_update_title_url, params: { title: "New Title" }

      failure_response_text_assertion(expected_status: :not_found,
                                      expected_text: "Not Found")
    end
  end

  context "when logged into GitHub without write permissions", feature_enabled: :prx_commits do
    test "does not allow editing of a PR title" do
      as @no_write_permissions_user
      patch @public_pr_update_title_url, params: { title: "New Title" }

      failure_response_text_assertion(expected_status: :not_found,
                                      expected_text: "Not Found")
    end
  end

  context "when logged into GitHub and blocked by the owner", spammy_only: true, feature_enabled: :prx_commits do
    test "user loses write privileges after being blocked" do
      as @blocked_user
      patch @public_pr_update_title_url, params: { title: "New Title" }

      successful_response_assertions(expected_title: "New Title", patch: true)

      @public_source.owner.block(@blocked_user)

      patch @public_pr_update_title_url, params: { title: "Second New Title" }

      failure_response_text_assertion(expected_status: :not_found,
                                      expected_text: "Not Found")
    end
  end

  context "#change_base", feature_enabled: :prx_commits do
    test "successfully changes base branch" do
      Spokesd.enable_spokesd
      candidate_base = get_candidate_base_branch(@public_pull)
      candidate_base_binary = Base64.encode64(candidate_base)

      as @owner
      perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
        patch @public_pr_change_base_url, params: { new_base_binary: candidate_base_binary }
      end
      assert_response_success

      json = JSON.parse(response.body)
      assert_equal "#{@public_pull.url}/orchestration/#{PullRequestOrchestration.last.id}", json["orchestration"]["url"]
      assert_equal candidate_base, @public_pull.reload.base_ref
    end

    test "returns not found if user is not logged in", skip_with_all_emus: true do
      candidate_base = get_candidate_base_branch(@public_pull)
      candidate_base_binary = Base64.encode64(candidate_base)

      patch @public_pr_change_base_url, params: { new_base_binary: candidate_base_binary }
      failure_response_text_assertion(expected_status: :not_found, expected_text: "Not Found")
    end

    test "returns not found if user does not have required permissions" do
      candidate_base = get_candidate_base_branch(@public_pull)
      candidate_base_binary = Base64.encode64(candidate_base)

      as @no_write_permissions_user
      patch @public_pr_change_base_url, params: { new_base_binary: candidate_base_binary }
      failure_response_text_assertion(expected_status: :not_found, expected_text: "Not Found")
    end

    test "requires non-empty ref name param" do
      as @owner
      patch @public_pr_change_base_url, params: { new_base_binary: "" }
      failure_response_text_assertion(expected_status: 422, expected_text: "Please select a base branch")
    end

    test "requires params" do
      as @owner
      patch @public_pr_change_base_url
      failure_response_text_assertion(expected_status: 422, expected_text: "Please select a base branch")
    end

    test "returns error message if base already changing" do
      Spokesd.enable_spokesd
      initial_base = @public_pull.base_ref
      candidate_base = get_candidate_base_branch(@public_pull)
      candidate_base_binary = Base64.encode64(candidate_base)

      as @owner
      patch @public_pr_change_base_url, params: { new_base_binary: candidate_base_binary }
      perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
        patch @public_pr_change_base_url, params: { new_base_binary: candidate_base_binary }
      end
      assert_response :unprocessable_entity
      assert_equal JSON.parse(response.body)["error"], "Base already being changed."
      assert_equal initial_base, @public_pull.reload.base_ref
    end

    test "returns error if PR is closed" do
      candidate_base = get_candidate_base_branch(@public_pull)
      candidate_base_binary = Base64.encode64(candidate_base)
      @public_pull.close
      assert_predicate @public_pull, :closed?

      as @owner
      perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
        patch @public_pr_change_base_url, params: { new_base_binary: candidate_base_binary }
      end
      assert_response :unprocessable_entity
      assert_equal JSON.parse(response.body)["error"], "Cannot change the base branch of a closed pull request."
    end

    if GitHub.merge_queues_enabled?
      test "returns error if in merge queue" do
        GitHub.flipper[:merge_queue].enable(@public_source)
        user = TestEnv.test_with_all_emus? ? @public_source.owner.admins.first : @public_source.owner

        # Protect default branch
        @public_source.protect_branch(@public_source.default_branch,
          creator: user,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )

        # Create mergeable pull request
        pull = create(:pull_request, :with_mergeable_head,
          repository: @public_source,
          user: user,
        )

        # Enqueue pull request
        queue = @public_source.default_merge_queue
        queue.enqueue!(pull_request: pull, enqueuer: pull.user)

        candidate_base = get_candidate_base_branch(pull)
        candidate_base_binary = Base64.encode64(candidate_base)

        as user
        perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
          patch "#{pull.url}/page_data/change_base", params: { new_base_binary: candidate_base_binary }
        end
        assert_response :unprocessable_entity
        assert_equal JSON.parse(response.body)["error"], "Cannot change the base branch because the branch has been added to a merge queue."
      end

      test "allows changing base branch if the repo loses access to merge queue" do
        Spokesd.enable_spokesd
        Repository.any_instance.stubs(:merge_queue_enabled?).returns(true)
        user = TestEnv.test_with_all_emus? ? @public_source.owner.admins.first : @public_source.owner

        # Protect default branch
        @public_source.protect_branch(@public_source.default_branch,
          creator: user,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )

        # Create mergeable pull request
        pull = create(:pull_request, :with_mergeable_head,
          repository: @public_source,
          user: user,
        )

        # Enqueue pull request
        queue = @public_source.default_merge_queue
        queue.enqueue!(pull_request: pull, enqueuer: pull.user)

        candidate_base = get_candidate_base_branch(pull)
        candidate_base_binary = Base64.encode64(candidate_base)

        # Disable merge queue
        Repository.any_instance.stubs(:merge_queue_enabled?).returns(false)

        as user
        perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
          patch "#{pull.url}/page_data/change_base", params: { new_base_binary: candidate_base_binary }
        end

        assert_response_success
        json = JSON.parse(response.body)
        assert_equal "#{pull.url}/orchestration/#{PullRequestOrchestration.last.id}", json["orchestration"]["url"]
        assert_equal candidate_base, pull.reload.base_ref
      end
    end
  end
end
