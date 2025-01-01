# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::MutationsControllerTest < GitHub::IntegrationTestCase
  include DocumentObjectModelHelper
  include PullRequestIntegrationTestHelpers
  include RepositoriesTestHelper

  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner, from_example: :simple)
    @pull = setup_pull_request(repository: @repo)
    @merged_pull_request = create(:pull_request, :with_mergeable_head, repository: @repo, user:  @owner)
    assert @merged_pull_request.merge.first
    @pull_draft = create(:pull_request, :with_mergeable_head, repository: @repo, draft: true)

    @repo.allow_auto_merge(actor: @owner)
    @repo.protect_branch(
      @pull.base_ref_name,
      creator: @owner,
      enforce_admins: true,
      required_pull_request_reviews: { required_approving_review_count: 1 },
      entry_point: :test_case,
    )

    advisory = create(:repository_advisory, repository: @repo, author: @owner)
    @workspace_repo = perform_enqueued_jobs(only: [RepositoryCloneJob, WorkspaceAbilitySetupJob]) do
      GitHub.context.push(actor_id: @owner.id)
      RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, @owner).tap(&:save!).tap(&:reload)
    end
    master_head = @workspace_repo.heads.find_or_build("master")
    topic_branch_head_ref = @workspace_repo.heads.find("topic")
    topic_branch_head_ref.append_commit({ message: "some changes", committer: @owner }, @owner) do |files|
      files.add("file001", "foo")
    end
    @draft_workspace_pull = create(:pull_request,
      repository: @workspace_repo,
      base_repository: @repo,
      head_repository: @workspace_repo,
      user:  @owner,
      base_ref: "master",
      head_ref: "topic",
      draft: true
    )

    example_repo_snapshot

    GitHub.flipper[:mergebox_react_partial].enable
  end

  setup do
    example_repo_restore
  end

  context "enable_auto_merge" do
    test "returns 200 for a valid request" do
      as @owner

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge"

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Auto merge request successfully created", json["message"]
    end

    test "returns error message if enable_auto_merge request fails" do
      as @owner

      AutoMergeRequest.stubs(:enqueue!).raises(AutoMergeRequest::Invalid)

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge"

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "Failed enabling auto-merge for pull request", json["message"]
    end

    test "returns 404 when the user is not logged in" do
      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge"

      assert_response :not_found
    end

    test "returns 404 when the user does not have push access" do
      random_user = create(:user)

      as random_user

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge"

      assert_response :not_found
    end

    test "returns 404 when the providing an invalid email" do
      as @owner

      post "#{@repo.name_with_display_owner}/pull/#{@pull.number}/auto_merge_requests", params: {
        author_email: "inavlid_email@github.com"
      }, xhr: true

      assert_response :not_found
    end

    test "returns 404 when the user is an enterprise managed user and the email does not match the user's profile email", skip_enterprise: true do
      emu = create(:emu)

      as emu

      post "#{@repo.name_with_display_owner}/pull/#{@pull.number}/auto_merge_requests", params: {
        author_email: emu.email
      }, xhr: true

      assert_response :not_found

    end

    test "for enable_auto_merge returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @owner

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge"

      assert_response :not_found
    end
  end

  context "disable_auto_merge" do
    test "returns 200 for a valid request" do
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.reload
      refute_nil @pull.auto_merge_request
      as @owner

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/disable_auto_merge"

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Auto merge request successfully disabled", json["message"]
    end

    test "returns error message if disable_auto_merge request fails" do
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      refute_nil @pull.auto_merge_request
      as @owner

      AutoMergeRequest.any_instance.stubs(:disable).raises(AutoMergeRequest::Invalid)

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/disable_auto_merge"

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "Failed disabling auto-merge for pull request", json["message"]
    end

    test "returns 404 when the user does not have permission to disable auto merge" do
      random_user = create(:user)
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.reload
      refute_nil @pull.auto_merge_request
      as random_user

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/disable_auto_merge"

      assert_response :not_found
    end

    test "returns 404 if auto merge request was never enabled" do
      as @owner

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/disable_auto_merge"

      assert_response :not_found
    end

    test "returns 404 if the pull request is merged" do
      @pull.merge(@owner)

      as @owner

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/disable_auto_merge"

      assert_response :not_found
    end

    test "returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @owner

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/disable_auto_merge"

      assert_response :not_found
    end
  end

  context "delete_head_ref" do

    test "deletes a pull request head ref for a closed PR" do
      assert @merged_pull_request.head_ref_exist?

      as @owner
      post "#{GitHub.url}/#{@merged_pull_request.repository.name_with_display_owner}/pull/#{@merged_pull_request.number}/page_data/delete_head_ref"
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Head ref was successfully deleted", json["message"]

      @merged_pull_request.reload
      refute @merged_pull_request.head_ref_exist?
    end

    test "returns error message if deletes a head ref request fails" do
      @merged_pull_request.cleanup_head_ref(@owner)
      @merged_pull_request.reload

      assert @merged_pull_request.closed?
      as @owner

      post "#{GitHub.url}/#{@merged_pull_request.repository.name_with_display_owner}/pull/#{@merged_pull_request.number}/page_data/delete_head_ref"
      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "Could not delete head ref", json["message"]
    end

    test "returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @owner

      post "#{GitHub.url}/#{@merged_pull_request.repository.name_with_display_owner}/pull/#{@merged_pull_request.number}/page_data/delete_head_ref"

      assert_response :not_found
    end

    test "returns 404 if the pull request is not found" do
      non_existent_pr = "0" * 40
      as @owner

      post "#{GitHub.url}/#{@merged_pull_request.repository.name_with_display_owner}/pull/#{non_existent_pr}/page_data/disable_auto_merge"

      assert_response :not_found
    end
  end

  context "mark_ready_for_review" do
    test "returns 200 for a valid request" do
      as @pull_draft.owner

      post "#{GitHub.url}/#{@pull_draft.repository.name_with_display_owner}/pull/#{@pull_draft.number}/page_data/mark_ready_for_review"

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Pull request was successfully marked ready for review", json["message"]
    end

    test "updates pull request draft state to false on success" do
      as @pull_draft.owner

      post "#{GitHub.url}/#{@pull_draft.repository.name_with_display_owner}/pull/#{@pull_draft.number}/page_data/mark_ready_for_review"

      assert_response :success
      refute @pull_draft.reload.draft?
    end

    test "returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @pull_draft.owner

      post "#{GitHub.url}/#{@pull_draft.repository.name_with_display_owner}/pull/#{@pull_draft.number}/page_data/mark_ready_for_review"

      assert_response :not_found
    end

    test "returns 404 when the user does not have push access to the pull request's repo" do
      random_user = create(:user)
      as random_user

      post "#{GitHub.url}/#{@pull_draft.repository.name_with_display_owner}/pull/#{@pull_draft.number}/page_data/mark_ready_for_review"

      assert_response :not_found
    end

    test "returns 500 when database is down" do
      PullRequest.any_instance.stubs(:ready_for_review!).raises(ActiveRecord::ConnectionFailed)
      as @pull_draft.owner

      post "#{GitHub.url}/#{@pull_draft.repository.name_with_display_owner}/pull/#{@pull_draft.number}/page_data/mark_ready_for_review"

      assert_response :internal_server_error
      json = JSON.parse(response.body)
      assert_equal "Pull request failed to be marked as ready for review", json["message"]
    end

    test "allows forker to mark ready for review" do
      forker = create(:user)
      fork_repo = create(:fork_repository, fork_repo: @repo, forker: forker, from_example: :pull_request_fork)
      pull_request = create(:pull_request,
        repository: @repo,
        base_repository: @repo,
        head_repository: fork_repo,
        user:  forker,
        draft: true
      )

      as forker

      post "#{GitHub.url}/#{pull_request.repository.name_with_display_owner}/pull/#{pull_request.number}/page_data/mark_ready_for_review"

      assert_response :success
      refute pull_request.reload.draft?
    end

    test "allows for marking a workspace repo pull request as ready for review" do
      as @owner

      post "#{GitHub.url}/#{@draft_workspace_pull.repository.name_with_display_owner}/pull/#{@draft_workspace_pull.number}/page_data/mark_ready_for_review"

      assert_response :success
      assert @draft_workspace_pull.reload.ready_for_review?
    end
  end

  context "restore_pull_request_head_ref" do

    test "restores the pull request head ref" do
      assert @merged_pull_request.closed?
      assert @merged_pull_request.cleanup_head_ref(@owner)
      refute @merged_pull_request.head_ref_exist?
      @merged_pull_request.reload

      as @owner

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@merged_pull_request.number}/page_data/restore_head_ref"

      assert @merged_pull_request.head_ref_exist?

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Head ref was successfully restored", json["message"]
    end

    test "returns an error message if the restore request fails" do
      assert @merged_pull_request.closed?
      @merged_pull_request.reload

      @merged_pull_request.stubs(:restore_head_ref).returns(false)

      as @owner

      post "#{GitHub.url}/#{@merged_pull_request.repository.name_with_display_owner}/pull/#{@merged_pull_request.number}/page_data/restore_head_ref"

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "Failed to restore head ref", json["message"]
    end

    test "returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @owner

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/restore_head_ref"

      assert_response :not_found
    end
  end
end
