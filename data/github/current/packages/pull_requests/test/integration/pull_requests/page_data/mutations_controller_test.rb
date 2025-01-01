# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::PageData::MutationsControllerTest < GitHub::IntegrationTestCase
  include PullRequestIntegrationTestHelpers
  include RepositoriesTestHelper
  include HydroTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @owner = create(:user)
    @forker = create(:user, login: "sweetsue")
    @rando = create(:user)
    @repo = create(:repository, owner: @owner, from_example: :simple)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :review_comment_fork)
    @reader = create(:collaborator, repository: @repo, action: :read)
    @pull = setup_pull_request(repository: @repo)
    @merged_pull_request = create(:pull_request, :with_mergeable_head, repository: @repo, user: @owner)
    assert @merged_pull_request.merge.first
    @closed_pull_request = create(:pull_request, :with_mergeable_head, :closed, repository: @repo, user: @owner)
    @closed_fork_pull_request =
      create(:pull_request,
        :closed,
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        user: @forker
      )
    @pull_draft = create(:pull_request, :with_mergeable_head, repository: @repo, draft: true)

    @repo.allow_auto_merge(actor: @owner)
    @repo.protect_branch(
      @pull.base_ref_name,
      creator: @owner,
      enforce_admins: true,
      required_pull_request_reviews: { required_approving_review_count: 0 },
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

    @org = create(:organization, admin: @owner)
    @team = create(:team, organization: @org, privacy: :closed)
    @hubber = create(:user)
    @user_to_request = create(:user)
    @org.add_member(@hubber)
    @org.add_member(@user_to_request)
    @private_repo = create(:private_repository, owner: @org, from_example: :simple)
    create(:collaborator, repository: @private_repo, user: @hubber, action: :write)
    create(:collaborator, repository: @private_repo, user: @user_to_request)
    @team.add_repository(@private_repo, :admin)
    @team.add_member(@user_to_request)

    @request_review_pull = setup_pull_request(repository: @private_repo, user: @hubber)

    example_repo_snapshot

    @page_data_path = "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data"

    GitHub.flipper[:mergebox_react_partial].enable
  end

  setup do
    example_repo_restore
  end

  context "#enable_auto_merge" do
    test "returns 200 for a valid request, creates an auto merge request with merge method and commit title and message", skip_with_all_emus: true do
      as @owner

      commit_title = "My updated commit title."
      commit_message = "My updated commit message."

      post "#{@page_data_path}/enable_auto_merge", params: {
        authorEmail: @owner.email,
        mergeMethod: "MERGE",
        commitTitle: commit_title,
        commitMessage: commit_message,
      }, xhr: true

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Auto merge request successfully created", json["message"]
      assert_equal "auto_merge", @pull.auto_merge_request.merge_method
      assert_equal @owner.email, @pull.auto_merge_request.commit_email_address.email
      assert_equal commit_title, @pull.auto_merge_request.commit_title
      assert_equal commit_message, @pull.auto_merge_request.commit_message
    end

    if TestEnv.test_with_all_emus?
      test "returns 200 for a valid request in emu mode, creates an auto merge request with merge method and commit title and message" do
        as @owner

        commit_title = "My updated commit title."
        commit_message = "My updated commit message."

        post "#{@page_data_path}/enable_auto_merge", params: {
          authorEmail: @owner.profile_email,
          mergeMethod: "MERGE",
          commitTitle: commit_title,
          commitMessage: commit_message,
        }, xhr: true

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal "Auto merge request successfully created", json["message"]
        assert_equal "auto_merge", @pull.auto_merge_request.merge_method
        assert_equal @owner.email, @pull.auto_merge_request.commit_email_address.email
        assert_equal commit_title, @pull.auto_merge_request.commit_title
        assert_equal commit_message, @pull.auto_merge_request.commit_message
      end

      test "returns 404 for if the email is not correct" do
        as @owner

        commit_title = "My updated commit title."
        commit_message = "My updated commit message."

        post "#{@page_data_path}/enable_auto_merge", params: {
          authorEmail: @owner.email,
          mergeMethod: "MERGE",
          commitTitle: commit_title,
          commitMessage: commit_message,
        }, xhr: true

        json = JSON.parse(response.body)

        assert_response :not_found
        assert_equal "Not Found", json["error"]
      end
    end

    test "returns 200 for a valid request, creates an auto merge request with squash merge method" do
      as @owner

      post "#{@page_data_path}/enable_auto_merge", params: {
        mergeMethod: "SQUASH",
      }, xhr: true

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Auto merge request successfully created", json["message"]
      assert_equal "auto_squash_and_merge", @pull.auto_merge_request.merge_method
    end

    test "returns 200 for a valid request, creates an auto merge request with rebase merge method" do
      as @owner

      post "#{@page_data_path}/enable_auto_merge", params: {
        mergeMethod: "REBASE",
      }, xhr: true

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Auto merge request successfully created", json["message"]
      assert_equal "auto_rebase_and_merge", @pull.auto_merge_request.merge_method
    end

    test "returns 200, creates an auto merge request with defaults if no params are passed" do
      as @owner

      post "#{@page_data_path}/enable_auto_merge", xhr: true

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Auto merge request successfully created", json["message"]
      assert_equal "auto_merge", @pull.auto_merge_request.merge_method
    end

    test "returns 200, and merges the pull request if it is ready to be merged" do
      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      as @owner

      commit_title = "My updated commit title."
      commit_message = "My updated commit message."

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge", params: {
        mergeMethod: "MERGE",
        commitTitle: commit_title,
        commitMessage: commit_message,
      }, xhr: true

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Pull request is merged.", json["message"]
    end

    test "if the pull request is ready to be merged, it handles mergeMethod being passed as lower case value (e.g. 'rebase' instead of 'REBASE')" do
      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?
      as @owner

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge", params: {
        commitTitle: "My first merge",
        commitMessage: "Really excited this is going to fix all of the things!",
        mergeMethod: "rebase"
      }, xhr: true

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Pull request is merged.", json["message"]
    end

    test "if the pull request is ready to be merged, returns 422 due to pre-receive hook failure" do
      as @owner

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      Repository.any_instance.stubs(:check_custom_hooks).raises(Git::Ref::HookFailed.new("stdout from a failing hook ✖✖".b))

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge", xhr: true

      assert_response :unprocessable_entity
      json_response = JSON.parse(response.body)
      assert_match  "Merging was blocked by pre-receive hooks.", json_response["error"]
      refute @pull.reload.merged?
    end

    test "if the pull request is ready to be merged, returns 422 if merge fails due to invalid state" do
      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      as @owner

      commit_title = "My updated commit title."
      commit_message = "My updated commit message."

      PullRequests::Merge.stub(:call, PullRequests::Merge::Failure.new(error_message: "Invalid state")) do
        post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge", params: {
          mergeMethod: "MERGE",
          commitTitle: commit_title,
          commitMessage: commit_message,
        }, xhr: true

        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        assert_equal "Invalid state", json["error"]
      end
    end

    context "on successful merge with :merge method" do
      test "sets sticky merge method as 'merge_commit'" do
        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge", xhr: true, params: { mergeMethod: "MERGE" }

        assert_response :success
        assert @pull.reload.merged?
        assert_equal "merge_commit", @repo.sticky_merge_method(@owner)
      end

      test "creates commit as merged commit" do
        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge", xhr: true, params: { mergeMethod: "MERGE" }

        assert_response :success
        assert @pull.reload.merged?

        merged_commit = @repo.commits.find(@pull.merge_commit_sha)
        assert_predicate merged_commit, :merge_commit?
        comparison = @repo.comparison(@pull.base_sha_on_merge, @pull.merge_commit_sha)
        # four commits on the topic branch plus the merge commit
        assert_equal 5, comparison.total_commits
      end
    end

    context "on successful merge with :squash method" do
      test "sets sticky merge method as 'squash'" do
        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge", xhr: true, params: { mergeMethod: "SQUASH" }

        assert_response :success
        assert @pull.reload.merged?
        assert_equal "squash", @repo.sticky_merge_method(@owner)
      end

      test "creates commit as squashed commit" do
        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge", xhr: true, params: { mergeMethod: "SQUASH" }

        assert_response :success
        assert @pull.reload.merged?

        merged_commit = @repo.commits.find(@pull.merge_commit_sha)
        refute_predicate merged_commit, :merge_commit?

        comparison = @repo.comparison(@pull.base_sha_on_merge, @pull.merge_commit_sha)
        # four commits from the topic branch squashed into one
        assert_equal 1, comparison.total_commits
      end
    end

    context "on successful merge with :rebase method" do
      test "sets sticky merge method as 'rebase'" do
        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge", xhr: true, params: { mergeMethod: "REBASE" }

        assert_response :success
        assert @pull.reload.merged?
        assert_equal "rebase", @repo.sticky_merge_method(@owner)
      end

      test "creates commit as rebased commit" do
        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data/enable_auto_merge", xhr: true, params: { mergeMethod: "REBASE" }

        assert_response :success
        assert @pull.reload.merged?

        merged_commit = @repo.commits.find(@pull.merge_commit_sha)
        refute_predicate merged_commit, :merge_commit?

        comparison = @repo.comparison(@pull.base_sha_on_merge, @pull.merge_commit_sha)
        # four commits rebased from the topic branch (one dropped)
        assert_equal 4, comparison.total_commits
      end
    end

    test "returns error message if enable_auto_merge request fails" do
      as @owner

      AutoMergeRequest.stubs(:enqueue!).raises(AutoMergeRequest::Invalid)

      post "#{@page_data_path}/enable_auto_merge", xhr: true

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "Failed enabling auto-merge for pull request", json["error"]
    end

    test "returns 404 when the user is not logged in" do
      post "#{@page_data_path}/enable_auto_merge", xhr: true

      json = JSON.parse(response.body)
      assert_response :not_found
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 when the user does not have push access" do
      as @reader

      post "#{@page_data_path}/enable_auto_merge", xhr: true

      json = JSON.parse(response.body)
      assert_response :not_found
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 when the author has an invalid email" do
      as @owner

      post "#{@page_data_path}/enable_auto_merge", params: {
        authorEmail: "invalid_email@github.com"
      }, xhr: true

      json = JSON.parse(response.body)
      assert_response :not_found
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 when the user is an enterprise managed user and the email does not match the user's profile email", skip_enterprise: true do
      emu = create(:emu)

      as emu

      post "#{@page_data_path}/enable_auto_merge", params: {
        authorEmail: emu.email
      }, xhr: true

      json = JSON.parse(response.body)
      assert_response :not_found
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @owner

      post "#{@page_data_path}/enable_auto_merge", xhr: true

      json = JSON.parse(response.body)
      assert_response :not_found
      assert_equal "Not Found", json["error"]
    end

    test "returns 406 for a non-XHR request" do
      as @owner

      post "#{@page_data_path}/enable_auto_merge"

      assert_response :not_acceptable
    end

    context "with merge queue" do
      test "create an auto merge merge queue request with group merge method" do
        create(:merge_queue, repository: @pull.repository)
        as @owner

        post "#{@page_data_path}/enable_auto_merge", params: { mergeMethod: "GROUP" }, xhr: true

        assert_response :success
        assert @pull.auto_merge_request
        assert_equal "merge_queue", @pull.auto_merge_request.merge_method
      end

      test "create an auto merge merge queue request with solo merge method" do
        create(:merge_queue, repository: @pull.repository)
        as @owner

        post "#{@page_data_path}/enable_auto_merge", params: { mergeMethod: "SOLO" }, xhr: true

        assert_response :success
        assert @pull.auto_merge_request
        assert_equal "merge_queue_solo", @pull.auto_merge_request.merge_method
      end

      test "is idempotent when an auto merge request exists" do
        as @owner

        queue = create(:merge_queue, repository: @pull.repository)
        create(:auto_merge_request, pull_request: @pull, user: @pull.user, merge_method: :merge_queue_solo)
        assert @pull.auto_merge_request

        post "#{@page_data_path}/enable_auto_merge", params: { mergeMethod: "GROUP" }, xhr: true

        assert_response :success
        assert_equal "merge_queue_solo", @pull.auto_merge_request.reload.merge_method
      end

      test "is idempotent when a merge queue entry exists" do
        as @owner

        queue = create(:merge_queue, repository: @pull.repository)
        @pull.create_merge_commit
        queue.enqueue!(pull_request: @pull, enqueuer: @pull.user)
        refute @pull.auto_merge_request

        post "#{@page_data_path}/enable_auto_merge", params: { mergeMethod: "GROUP" }, xhr: true

        assert_response :unprocessable_entity
        json = JSON.parse(response.body)
        assert_equal "Failed enabling auto-merge for pull request", json["error"]
        refute @pull.reload.auto_merge_request
      end

      # This should really be tested at the model level, but since it's not, let's port over the test from auto_merge_requests_controller_test.rb
      test "adds pull request directly to merge queue and skips auto merge request if pull is ready to be merged" do
        create(:merge_queue, repository: @pull.repository)
        @pull.create_merge_commit

        as @owner

        post "#{@page_data_path}/enable_auto_merge", params: { mergeMethod: "GROUP" }, xhr: true

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal "Auto merge request successfully created", json["message"]
        refute @pull.auto_merge_request
        assert @pull.reload.merge_queue_entry
        refute @pull.merge_queue_entry.solo?
        refute @pull.merge_queue_entry.jump_queue?
      end

      # This should really be tested at the model level, but since it's not, let's port over the test from auto_merge_requests_controller_test.rb
      test "adds pull request directly to merge queue solo and skips auto merge request if pull is ready to be merged" do
        create(:merge_queue, repository: @pull.repository)
        @pull.create_merge_commit

        as @owner

        post "#{@page_data_path}/enable_auto_merge", params: { mergeMethod: "SOLO" }, xhr: true

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal "Auto merge request successfully created", json["message"]
        refute @pull.auto_merge_request
        assert @pull.reload.merge_queue_entry
        assert @pull.merge_queue_entry.solo?
        refute @pull.merge_queue_entry.jump_queue?
      end
    end
  end

  context "#disable_auto_merge" do
    test "returns 200 for a valid request" do
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.reload
      refute_nil @pull.auto_merge_request
      as @owner

      post "#{@page_data_path}/disable_auto_merge", xhr: true

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Auto merge request successfully disabled", json["message"]
    end

    test "returns error message if disable_auto_merge request fails" do
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      refute_nil @pull.auto_merge_request
      as @owner

      AutoMergeRequest.any_instance.stubs(:disable).raises(AutoMergeRequest::Invalid)

      post "#{@page_data_path}/disable_auto_merge", xhr: true

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "Failed disabling auto-merge for pull request", json["error"]
    end

    test "returns 404 when the user does not have permission to disable auto merge" do
      create(:auto_merge_request, pull_request: @pull, user: @owner)
      @pull.reload
      refute_nil @pull.auto_merge_request

      as @reader

      post "#{@page_data_path}/disable_auto_merge", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 if auto merge request was never enabled" do
      as @owner

      post "#{@page_data_path}/disable_auto_merge", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 if the pull request is merged" do
      @pull.merge(@owner)

      as @owner

      post "#{@page_data_path}/disable_auto_merge", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @owner

      post "#{@page_data_path}/disable_auto_merge", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 406 for a non-XHR request" do
      as @owner

      post "#{@page_data_path}/disable_auto_merge"

      assert_response :not_acceptable
    end
  end

  context "#delete_head_ref" do
    context "forks" do
      test "forker can delete a head ref for a closed PR" do
        as @forker

        assert @closed_fork_pull_request.head_ref_exist?

        post "#{GitHub.url}/#{@closed_fork_pull_request.repository.name_with_display_owner}/pull/#{@closed_fork_pull_request.number}/page_data/delete_head_ref", xhr: true
        assert_response :success
        json = JSON.parse(response.body)
        assert_equal "Head ref was successfully deleted", json["message"]

        @closed_fork_pull_request.reload
        refute @closed_fork_pull_request.head_ref_exist?
      end
    end

    test "deletes a pull request head ref for a closed PR" do
      assert @merged_pull_request.head_ref_exist?

      as @owner
      post "#{GitHub.url}/#{@merged_pull_request.repository.name_with_display_owner}/pull/#{@merged_pull_request.number}/page_data/delete_head_ref", xhr: true
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Head ref was successfully deleted", json["message"]

      @merged_pull_request.reload
      refute @merged_pull_request.head_ref_exist?
    end

    test "returns error message if delete a head ref request fails" do
      @merged_pull_request.cleanup_head_ref(@owner)
      @merged_pull_request.reload

      assert @merged_pull_request.closed?
      as @owner

      post "#{GitHub.url}/#{@merged_pull_request.repository.name_with_display_owner}/pull/#{@merged_pull_request.number}/page_data/delete_head_ref", xhr: true
      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "Could not delete head ref", json["error"]
    end

    test "returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @owner

      post "#{GitHub.url}/#{@merged_pull_request.repository.name_with_display_owner}/pull/#{@merged_pull_request.number}/page_data/delete_head_ref", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 if the pull request is not found" do
      non_existent_pr = "0" * 40
      as @owner

      post "#{GitHub.url}/#{@merged_pull_request.repository.name_with_display_owner}/pull/#{non_existent_pr}/page_data/delete_head_ref", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 406 for a non-XHR request" do
      as @owner

      post "#{@page_data_path}/delete_head_ref"

      assert_response :not_acceptable
    end
  end

  context "#restore_pull_request_head_ref" do
    context "forks" do
      test "forker can restore head ref for a closed PR" do
        assert @closed_fork_pull_request.closed?
        assert @closed_fork_pull_request.cleanup_head_ref(@forker)
        refute @closed_fork_pull_request.head_ref_exist?
        @closed_fork_pull_request.reload

        as @forker

        post "#{GitHub.url}/#{@closed_fork_pull_request.repository.name_with_display_owner}/pull/#{@closed_fork_pull_request.number}/page_data/restore_head_ref", xhr: true

        assert @closed_fork_pull_request.head_ref_exist?

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal "Head ref was successfully restored", json["message"]
      end
    end

    test "restores the pull request head ref" do
      assert @merged_pull_request.closed?
      assert @merged_pull_request.cleanup_head_ref(@owner)
      refute @merged_pull_request.head_ref_exist?
      @merged_pull_request.reload

      as @owner

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@merged_pull_request.number}/page_data/restore_head_ref", xhr: true

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

      post "#{GitHub.url}/#{@merged_pull_request.repository.name_with_display_owner}/pull/#{@merged_pull_request.number}/page_data/restore_head_ref", xhr: true

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "Failed to restore head ref", json["error"]
    end

    test "returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @owner

      post "#{@page_data_path}/restore_head_ref", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 406 for non-XHR request" do
      as @owner

      post "#{@page_data_path}/restore_head_ref"

      assert_response :not_acceptable
    end
  end

  context "#mark_ready_for_review" do
    test "returns 200 for a valid request" do
      as @pull_draft.owner

      post "#{GitHub.url}/#{@pull_draft.repository.name_with_display_owner}/pull/#{@pull_draft.number}/page_data/mark_ready_for_review", xhr: true

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Pull request was successfully marked ready for review", json["message"]
    end

    test "updates pull request draft state to false on success" do
      as @pull_draft.owner

      post "#{GitHub.url}/#{@pull_draft.repository.name_with_display_owner}/pull/#{@pull_draft.number}/page_data/mark_ready_for_review", xhr: true

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Pull request was successfully marked ready for review", json["message"]
      refute @pull_draft.reload.draft?
    end

    test "returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @pull_draft.owner

      post "#{GitHub.url}/#{@pull_draft.repository.name_with_display_owner}/pull/#{@pull_draft.number}/page_data/mark_ready_for_review", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 when the user does not have push access to the pull request's repo" do
      as @reader

      post "#{GitHub.url}/#{@pull_draft.repository.name_with_display_owner}/pull/#{@pull_draft.number}/page_data/mark_ready_for_review", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 500 when database is down" do
      PullRequest.any_instance.stubs(:ready_for_review!).raises(ActiveRecord::ConnectionFailed)
      as @pull_draft.owner

      post "#{GitHub.url}/#{@pull_draft.repository.name_with_display_owner}/pull/#{@pull_draft.number}/page_data/mark_ready_for_review", xhr: true

      assert_response :internal_server_error
      json = JSON.parse(response.body)
      assert_equal "Pull request failed to be marked as ready for review", json["error"]
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

      post "#{GitHub.url}/#{pull_request.repository.name_with_display_owner}/pull/#{pull_request.number}/page_data/mark_ready_for_review", xhr: true

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Pull request was successfully marked ready for review", json["message"]
      refute pull_request.reload.draft?
    end

    test "allows for marking a workspace repo pull request as ready for review" do
      as @owner

      post "#{GitHub.url}/#{@draft_workspace_pull.repository.name_with_display_owner}/pull/#{@draft_workspace_pull.number}/page_data/mark_ready_for_review", xhr: true

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Pull request was successfully marked ready for review", json["message"]
      assert @draft_workspace_pull.reload.ready_for_review?
    end

    test "returns 406 for a non-XHR request" do
      as @owner

      post "#{GitHub.url}/#{@draft_workspace_pull.repository.name_with_display_owner}/pull/#{@draft_workspace_pull.number}/page_data/mark_ready_for_review"

      assert_response :not_acceptable
    end
  end

  context "#merge" do
    test "returns 404 for workspace repos" do
      as @owner

      post "#{GitHub.url}/#{@draft_workspace_pull.repository.name_with_display_owner}/pull/#{@draft_workspace_pull.number}/page_data/merge", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
      refute @draft_workspace_pull.reload.merged?
    end

    test "returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @pull_draft.owner

      post "#{@page_data_path}/merge", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    context "when timeout occurs" do
      test "it returns 504 and stops merge orchestration on the pull request" do
        PullRequest::Merge.any_instance.stubs(:prepare_and_validate).raises(Timeout::Error)

        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{@page_data_path}/merge", xhr: true

        assert_response :gateway_timeout
        json = JSON.parse(response.body)
        assert_equal "Merge attempt timed out.", json["error"]
      end

      test "it increments Datadog's 'pull_requests.merge_timeout_rescued'" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        PullRequest::Merge.any_instance.stubs(:prepare_and_validate).raises(Timeout::Error)

        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{@page_data_path}/merge", xhr: true

        assert_response :gateway_timeout

        refute @pull.reload.merged?
        assert_equal 1, GitHub.dogstats.increments("pull_requests.merge_timeout_rescued").count
      end
    end

    test "merges a pull request with a commit message and title" do
      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?
      as @owner

      post "#{@page_data_path}/merge", xhr: true, params: {
        commitTitle: "My first merge",
        commitMessage: "Really excited this is going to fix all of the things!",
        mergeMethod: "SQUASH"
      }

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Pull request is merged.", json["message"]
    end

    test "it handles mergeMethod being passed as lower case value (e.g. 'rebase' instead of 'REBASE')" do
      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?
      as @owner

      post "#{@page_data_path}/merge", xhr: true, params: {
        commitTitle: "My first merge",
        commitMessage: "Really excited this is going to fix all of the things!",
        mergeMethod: "rebase"
      }

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Pull request is merged.", json["message"]
    end

    test "merges a pull with a valid email", skip_with_all_emus: true do
      valid_email = create(:user_email, user: @owner).email
      @owner.emails.each(&:verify!)
      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      as @owner

      post "#{@page_data_path}/merge", xhr: true, params: {
        # Don't pass authorEmail param for enterprise test as GitHub.choose_commit_email_enabled? returns false and will fail validation
        authorEmail: TestEnv.enterprise? ? nil : valid_email
      }

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Pull request is merged.", json["message"]
    end

    test "returns 422 with an invalid email" do
      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      as @owner

      post "#{@page_data_path}/merge", xhr: true, params: {
        authorEmail: "invalid_email@github.com"
      }

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "Invalid email for web commit.", json["error"]
    end

    test "creates hydro PullRequestMerge event for an unapproved PR" do
      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      as @owner
      post "#{@page_data_path}/merge", xhr: true
      assert_response :success

      @pull.reload

      changed_files = @pull.changed_files_for_instrumentation.map do |file|
        Hydro::EntitySerializer.changed_file(file, overrides: { change_type: file.change_type_symbol })
      end

      expected_hydro_message = {
        actor: Hydro::EntitySerializer.user(@owner),
        author: Hydro::EntitySerializer.user(@pull.user),
        pull_request: Hydro::EntitySerializer.pull_request(@pull, overrides: { changed_files: changed_files }),
        issue: Hydro::EntitySerializer.issue(@pull.issue),
        repository: Hydro::EntitySerializer.repository(@pull.repository),
        repository_owner: Hydro::EntitySerializer.user(@pull.repository.owner),
        protected_branch: Hydro::EntitySerializer.protected_branch(@pull.base_branch_rule_evaluator&.original_protected_branch),
        merge_action: "DIRECT_MERGE",
        merge_method: "MERGE",
        pr_approved: false,
      }
      assert_hydro_published(expected_hydro_message, schema: "github.v1.PullRequestMerge", ignore_extra_keys: true)
    end

    test "creates hydro PullRequestMerge event with an approved PR" do
      @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
        body: "review body!",
        state: :approved,
      )

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      as @owner
      post "#{@page_data_path}/merge", xhr: true

      assert_response :success

      expected_hydro_message = {
        pr_approved: true,
      }
      assert_hydro_published_partial(expected_hydro_message, schema: "github.v1.PullRequestMerge")
    end

    test "creates hydro PullRequestMerge event and includes merge commit title and message and default bool as false if actor updates" do
      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      as @owner
      post "#{@page_data_path}/merge", xhr: true, params: { commitTitle: "not default title", commitMessage: "not default message" }

      assert_response :success
      expected_hydro_message = {
        merge_commit_title: "not default title",
        merge_commit_message: "not default message",
        default_merge_commit_message_and_title: false,
      }
      assert_hydro_published(expected_hydro_message, schema: "github.v1.PullRequestMerge", ignore_extra_keys: true)
    end

    test "creates hydro PullRequestMerge event and includes merge commit title and message and default bool as true if actor doesn't pass through any :commitTitle and :commitMessage params" do
      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      as @owner
      post "#{@page_data_path}/merge", xhr: true
      assert_response :success

      @pull.reload

      expected_hydro_message = {
      merge_commit_title: @pull.default_merge_commit_title,
      merge_commit_message: @pull.default_merge_commit_message,
      default_merge_commit_message_and_title: true,
      }
      assert_hydro_published(expected_hydro_message, schema: "github.v1.PullRequestMerge", ignore_extra_keys: true)
    end

    test "creates hydro PullRequestMerge event and includes merge commit title and message and default bool as true if actor pass through the defaults for :commitTitle and :commitMessage params" do
      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      as @owner
      post "#{@page_data_path}/merge", xhr: true, params: {
        commitTitle: @pull.default_merge_commit_title,
        commitMessage: @pull.default_merge_commit_message
      }
      assert_response :success

      @pull.reload

      expected_hydro_message = {
        merge_commit_title: @pull.default_merge_commit_title,
        merge_commit_message: @pull.default_merge_commit_message,
        default_merge_commit_message_and_title: true,
      }
      assert_hydro_published(expected_hydro_message, schema: "github.v1.PullRequestMerge", ignore_extra_keys: true)
    end

    test "when :bypassBranchProtections params is passed with 'true' value it sends 'ADMIN_OVERRIDE_MERGE' as :merge_action in Hydro message" do
      create(:profile, user: @owner, location: "Oakland, CA")
      as @owner

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      post "#{@page_data_path}/merge", xhr: true, params: { bypassBranchProtections: true }

      assert_response :success

      @pull.reload

      changed_files = @pull.changed_files_for_instrumentation.map do |file|
        Hydro::EntitySerializer.changed_file(file, overrides: { change_type: file.change_type_symbol })
      end

      expected_hydro_message = {
        merge_action: "ADMIN_OVERRIDE_MERGE",
      }
      assert_hydro_published(expected_hydro_message, schema: "github.v1.PullRequestMerge", ignore_extra_keys: true)
    end

    test "when :bypassBranchProtections params is passed with 'false' value it sends 'DIRECT_MERGE' as :merge_action in Hydro message" do
      create(:profile, user: @owner, location: "Oakland, CA")
      as @owner

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      post "#{@page_data_path}/merge", xhr: true, params: { bypassBranchProtections: false }

      assert_response :success

      @pull.reload

      changed_files = @pull.changed_files_for_instrumentation.map do |file|
        Hydro::EntitySerializer.changed_file(file, overrides: { change_type: file.change_type_symbol })
      end

      expected_hydro_message = {
        merge_action: "DIRECT_MERGE",
      }
      assert_hydro_published(expected_hydro_message, schema: "github.v1.PullRequestMerge", ignore_extra_keys: true)
    end

    test "successful merge counts datadog requested_reviewers" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      reviewer_one = create(:collaborator, repository: @repo)
      reviewer_two = create(:collaborator, repository: @repo)

      as @owner

      @pull.review_requests.create(reviewer: reviewer_one)
      @pull.review_requests.create(reviewer: reviewer_two)

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      post "#{@page_data_path}/merge", xhr: true

      assert_response :success

      @pull.reload
      assert @pull.merged?
      assert_equal 2, @pull.review_requests.pending.size
      assert_equal [2], GitHub.dogstats.histograms("pull_request.merged.requested_reviewers.count").map(&:value)
    end

    test "failed merge increments datadog's pull_request tags: action:merge and error:invalid" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      # ensure PR is not mergable
      refute @pull.git_merges_cleanly?

      as @owner

      post "#{@page_data_path}/merge", xhr: true
      assert_response :unprocessable_entity

      @pull.reload
      refute @pull.merged?

      assert_equal 1, GitHub.dogstats.increments("pull_request", tags: ["action:merge", "error:invalid"]).count
    end

    test "fails merging when required status checks aren't complete" do
      as @owner

      @pull.repository.protect_branch(@pull.base_ref_name, creator: @source_owner, required_status_checks: { contexts: %w[ci/janky], include_admins: true }, entry_point: :test_case)

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      post "#{@page_data_path}/merge", xhr: true

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "Required status check \"ci/janky\" is expected.", json["error"]

      refute @pull.reload.merged?
    end

    test "successfully merges as admin even though required status checks aren't completed" do
      as @owner

      @pull.repository.protect_branch(@pull.base_ref_name, creator: @source_owner, required_status_checks: { contexts: %w[ci/janky], include_admins: false }, entry_point: :test_case)

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      post "#{@page_data_path}/merge", xhr: true
      assert_response :ok
      assert @pull.reload.merged?
    end

    context "on successful merge with :merge method" do
      test "sets sticky merge method as 'merge_commit'" do
        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "MERGE" }

        assert_response :success
        assert @pull.reload.merged?
        assert_equal "merge_commit", @repo.sticky_merge_method(@owner)
      end

      test "creates commit as merged commit" do
        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "MERGE" }

        assert_response :success
        assert @pull.reload.merged?

        merged_commit = @repo.commits.find(@pull.merge_commit_sha)
        assert_predicate merged_commit, :merge_commit?
        comparison = @repo.comparison(@pull.base_sha_on_merge, @pull.merge_commit_sha)
        # four commits on the topic branch plus the merge commit
        assert_equal 5, comparison.total_commits
      end
    end

    context "on successful merge with :squash method" do
      test "sets sticky merge method as 'squash'" do
        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "SQUASH" }

        assert_response :success
        assert @pull.reload.merged?
        assert_equal "squash", @repo.sticky_merge_method(@owner)
      end

      test "creates commit as squashed commit" do
        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "SQUASH" }

        assert_response :success
        assert @pull.reload.merged?

        merged_commit = @repo.commits.find(@pull.merge_commit_sha)
        refute_predicate merged_commit, :merge_commit?

        comparison = @repo.comparison(@pull.base_sha_on_merge, @pull.merge_commit_sha)
        # four commits from the topic branch squashed into one
        assert_equal 1, comparison.total_commits
      end
    end

    context "on successful merge with :rebase method" do
      test "sets sticky merge method as 'rebase'" do
        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "REBASE" }

        assert_response :success
        assert @pull.reload.merged?
        assert_equal "rebase", @repo.sticky_merge_method(@owner)
      end

      test "creates commit as rebased commit" do
        as @owner

        assert @pull.create_merge_commit
        assert @pull.git_merges_cleanly?

        post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "REBASE" }

        assert_response :success
        assert @pull.reload.merged?

        merged_commit = @repo.commits.find(@pull.merge_commit_sha)
        refute_predicate merged_commit, :merge_commit?

        comparison = @repo.comparison(@pull.base_sha_on_merge, @pull.merge_commit_sha)
        # four commits rebased from the topic branch (one dropped)
        assert_equal 4, comparison.total_commits
      end
    end

    test "failed merge due to pre-receive hook failure" do
      as @owner

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      Repository.any_instance.stubs(:check_custom_hooks).raises(Git::Ref::HookFailed.new("stdout from a failing hook ✖✖".b))

      post "#{@page_data_path}/merge", xhr: true

      assert_response :unprocessable_entity
      json_response = JSON.parse(response.body)
      assert_match  "Merging was blocked by pre-receive hooks.", json_response["error"]
      refute @pull.reload.merged?
    end

    test "failed merge due to ruleset failures" do
      ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @repo)
      create(:repository_rule_configuration, :update, repository_ruleset: ruleset)

      as @owner

      assert @pull.create_merge_commit
      assert @pull.git_merges_cleanly?

      post "#{@page_data_path}/merge", xhr: true

      assert_response :unprocessable_entity
      json_response = JSON.parse(response.body)
      assert_equal  "Merging was blocked due to rule violation errors.", json_response["error"]
      assert_nil json_response["message"]

      refute @pull.reload.merged?
    end

    test "it can successfully merge with a deleted user" do
      forker = create(:user)
      fork_repo = create(:fork_repository, fork_repo: @repo, forker: forker, from_example: :pull_request_fork)
      example_repo :review_comment_fork, fork_repo
      pull_request = create(:pull_request,
        repository: @repo,
        base_repository: @repo,
        head_repository: fork_repo,
        user:  forker,
        draft: false
      )

      assert pull_request.create_merge_commit
      assert pull_request.git_merges_cleanly?

      pull_request.user.delete

      as @owner

      post "#{GitHub.url}/#{pull_request.repository.name_with_display_owner}/pull/#{pull_request.number}/page_data/merge", xhr: true

      assert_response :success
      pull_request.reload
      assert pull_request.merged?
      assert_nil pull_request.user
    end
  end

  if GitHub.choose_commit_email_enabled?
    test "merge can take custom author email", skip_with_all_emus: true do
      custom_email = create(:user_email, user: @owner).email
      @owner.emails.map(&:verify!)

      assert @pull.create_merge_commit

      as @owner

      post "#{@page_data_path}/merge", xhr: true, params: { authorEmail: custom_email }
      assert_response :success

      @pull.reload
      merged_commit = @repo.commits.find(@pull.merge_commit_sha)

      assert_equal "merge_commit", @repo.sticky_merge_method(@owner)
      assert_equal custom_email, merged_commit.author_email
    end

    test "merge does not accept custom email if not among author emails" do
      nefarious_email = "thisisfake@hacker.com"

      as @owner

      assert @pull.create_merge_commit

      post "#{@page_data_path}/merge", xhr: true, params: { authorEmail: nefarious_email }
      assert_response :unprocessable_entity
      json_response = JSON.parse(response.body)
      assert_match  "Invalid email for web commit.", json_response["error"]
    end

    test "squash allows custom author email from PR author", skip_with_all_emus: true do
      custom_email = create(:user_email, user: @owner).email
      @owner.emails.map(&:verify!)

      as @owner

      assert @pull.create_merge_commit

      post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "SQUASH", authorEmail: custom_email }
      assert_response :success

      @pull.reload
      merged_commit = @repo.commits.find(@pull.merge_commit_sha)

      assert_equal "squash", @repo.sticky_merge_method(@owner)
      assert_equal custom_email, merged_commit.author_email
      assert_equal GitHub.web_committer_email, merged_commit.committer_email
    end

    test "squash ignores custom author email from non PR author", skip_with_all_emus: true do
      collaborator = create(:collaborator, repository: @repo, action: :write)
      custom_email = create(:user_email, user: collaborator).email
      collaborator.emails.map(&:verify!)

      assert @pull.create_merge_commit

      as collaborator
      post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "SQUASH", authorEmail: custom_email }
      assert_response :success

      @pull.reload
      merged_commit = @repo.commits.find(@pull.merge_commit_sha)

      refute_equal custom_email, merged_commit.author_email
      assert_equal @pull.user.git_author_email, merged_commit.author_email
      assert_equal GitHub.web_committer_email, merged_commit.committer_email
    end

    test "squash allows custom author email from author", skip_with_all_emus: true do
      custom_email = create(:user_email, user: @owner).email
      @owner.emails.map(&:verify!)

      as @owner

      assert @pull.create_merge_commit

      post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "SQUASH", authorEmail: custom_email }

      assert_response :success

      @pull.reload
      merged_commit = @repo.commits.find(@pull.merge_commit_sha)

      assert_equal "squash", @repo.sticky_merge_method(@owner)
      assert_equal custom_email, merged_commit.author_email
      assert_equal GitHub.web_committer_email, merged_commit.committer_email
    end

    test "squash ignores custom author email from non author", skip_with_all_emus: true do
      collaborator = create(:collaborator, repository: @repo, action: :write)
      custom_email = create(:user_email, user: collaborator).email
      collaborator.emails.map(&:verify!)

      assert @pull.create_merge_commit

      as collaborator
      post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "SQUASH", authorEmail: custom_email }
      assert_response :success

      @pull.reload
      merged_commit = @repo.commits.find(@pull.merge_commit_sha)

      refute_equal custom_email, merged_commit.author_email
      assert_equal @pull.user.git_author_email, merged_commit.author_email
      assert_equal GitHub.web_committer_email, merged_commit.committer_email
    end

    test "squash does not accept custom email if not among author_emails" do
      nefarious_email = "thisisfake@hacker.com"

      as @owner

      assert @pull.create_merge_commit

      post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "SQUASH", authorEmail: nefarious_email }

      assert_response :unprocessable_entity
      json_response = JSON.parse(response.body)
      assert_match  "Invalid email for web commit.", json_response["error"]
    end
  else
    test "merge does not accept custom author email" do
      custom_email = create(:user_email, user: @owner).email
      @owner.emails.map(&:verify!)

      as @owner

      assert @pull.create_merge_commit
      post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "MERGE", authorEmail: custom_email }

      assert_response :unprocessable_entity
      json_response = JSON.parse(response.body)
      assert_match  "Invalid email for web commit.", json_response["error"]
    end

    test "squash does not accept custom author email" do
      custom_email = create(:user_email, user: @owner).email
      @owner.emails.map(&:verify!)

      as @owner

      assert @pull.create_merge_commit

      post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "SQUASH", authorEmail: custom_email }

      assert_response :unprocessable_entity
      json_response = JSON.parse(response.body)
      assert_match  "Invalid email for web commit.", json_response["error"]
    end

    test "rebase does not accept custom author email" do
      custom_email = create(:user_email, user: @owner).email
      @owner.emails.map(&:verify!)

      as @owner

      assert @pull.create_merge_commit

      post "#{@page_data_path}/merge", xhr: true, params: { mergeMethod: "rebase", authorEmail: custom_email }

      assert_response :unprocessable_entity
      json_response = JSON.parse(response.body)
      assert_match  "Invalid email for web commit.", json_response["error"]
    end
  end

  context "#update_pull_request_branch" do
    test "returns 200 if creating the update branch orchestration is successful" do
      as @owner

      #ensure we're not performing an unnecessary rebase during this request
      PullRequest::Prepare.any_instance.expects(:prepare_rebase).never

      post "#{@page_data_path}/update_pull_request_branch", params: { expectedHeadOid: @pull.head_sha }, xhr: true

      assert_response :success
      get JSON.parse(@response.body)["orchestration"]["url"]
    end

    test "when orchestration succeeds with merge, returns correct state and no errors" do
      as @owner

      #ensure we're not performing an unnecessary rebase during this request
      PullRequest::Prepare.any_instance.expects(:prepare_rebase).never

      post "#{@page_data_path}/update_pull_request_branch", params: { expectedHeadOid: @pull.head_sha }, xhr: true

      assert_response :success

      perform_enqueued_jobs(only: [PullRequestOrchestrationJob])

      get JSON.parse(@response.body)["orchestration"]["url"]
      assert_response :success
      assert_equal "succeeded", JSON.parse(@response.body)["orchestration"]["state"]
      assert_nil JSON.parse(@response.body)["orchestration"]["error_message"]
    end

    test "returns 200 when it succeeds with rebase" do
      as @owner

      @pull.create_merge_commit

      post "#{@page_data_path}/update_pull_request_branch", params: { expectedHeadOid: @pull.head_sha, updateMethod: :rebase }, xhr: true

      assert_response :success

      perform_enqueued_jobs(only: [PullRequestOrchestrationJob])

      get JSON.parse(@response.body)["orchestration"]["url"]
      assert_response :success
      assert_equal "succeeded", JSON.parse(@response.body)["orchestration"]["state"]
      assert_nil JSON.parse(@response.body)["orchestration"]["error_message"]
    end

    test "returns 200 for a closed PR, but updating branch fails" do
      as @owner

      post "#{GitHub.url}/#{@closed_pull_request.repository.name_with_display_owner}/pull/#{@closed_pull_request.number}/page_data/update_pull_request_branch", params: { expectedHeadOid: @closed_pull_request.head_sha }, xhr: true

      assert_response :success

      perform_enqueued_jobs(only: [PullRequestOrchestrationJob])

      get JSON.parse(@response.body)["orchestration"]["url"]
      assert_response :success
      assert_equal "skipped", JSON.parse(@response.body)["orchestration"]["state"]
      assert_equal "Merge conflict between head and base.", JSON.parse(@response.body)["orchestration"]["error_message"]
    end

    test "returns 200 for a closed PR, but updating branch with rebase fails" do
      as @owner

      post "#{GitHub.url}/#{@closed_pull_request.repository.name_with_display_owner}/pull/#{@closed_pull_request.number}/page_data/update_pull_request_branch", params: { expectedHeadOid: @closed_pull_request.head_sha, updateMethod: :rebase }, xhr: true

      assert_response :success

      perform_enqueued_jobs(only: [PullRequestOrchestrationJob])

      get JSON.parse(@response.body)["orchestration"]["url"]
      assert_response :success
      assert_equal "skipped", JSON.parse(@response.body)["orchestration"]["state"]
      assert_equal "Rebase conflict between head and base.", JSON.parse(@response.body)["orchestration"]["error_message"]
    end

    test "fails with error if head ref is a mismatch" do
      as @owner

      post "#{@page_data_path}/update_pull_request_branch", params: { expectedHeadOid: "1" * 40 }, xhr: true
      assert_response :success

      perform_enqueued_jobs(only: [PullRequestOrchestrationJob])

      get JSON.parse(@response.body)["orchestration"]["url"]
      assert_response :success
      assert_equal "skipped", JSON.parse(@response.body)["orchestration"]["state"]
      assert_equal "Head branch was modified. Review and try the merge again.", JSON.parse(@response.body)["orchestration"]["error_message"]
    end

    test "prevents duplicate orchestrations from being created, returns 422 for second request" do
      as @owner

      # create a job but don't run it
      post "#{@page_data_path}/update_pull_request_branch", params: { expectedHeadOid: @pull.head_sha }, xhr: true
      assert_response :success

      post "#{@page_data_path}/update_pull_request_branch", params: { expectedHeadOid: @pull.head_sha }, xhr: true

      assert_response :unprocessable_entity
      assert_equal "branch update already in progress", JSON.parse(@response.body)["error"]
    end

    test "returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @owner

      post "#{@page_data_path}/update_pull_request_branch", params: { expectedHeadOid: @pull.head_sha }, xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 if mergebox_react_partial feature flag is not enabled" do
      GitHub.flipper[:mergebox_react_partial].disable
      as @owner

      post "#{@page_data_path}/update_pull_request_branch", params: { expectedHeadOid: @pull.head_sha }, xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 406 if not an xhr request" do
      as @owner

      post "#{@page_data_path}/update_pull_request_branch", params: { expectedHeadOid: @pull.head_sha }

      assert_response :not_acceptable
    end
  end

  context "#dismiss_review" do
    test "returns 200 if the review is successfully dismissed" do
      review = create(:pull_request_review, pull_request: @pull, user: @reader)
      review.trigger(:approve)

      as @owner
      post "#{GitHub.url}/#{@repo.name_with_display_owner}/pull/#{@pull.number}/page_data/dismiss_review", xhr: true, params: { reviewId: review.id, message: "Dismissing" }

      assert_response :success
    end

    test "returns 404 if the review isn't for the given pull request" do
      other_pr = setup_pull_request
      review = create(:pull_request_review, pull_request: other_pr, user: other_pr.repository.owner)
      review.trigger(:approve)

      as @owner
      post "#{GitHub.url}/#{@repo.name_with_display_owner}/pull/#{@pull.number}/page_data/dismiss_review", xhr: true, params: { reviewId: review.id, message: "Dismissing" }

      assert_response :not_found
    end

    test "returns 422 if the review is already dismissed" do
      review = create(:pull_request_review, pull_request: @pull, user: @reader)
      review.trigger(:approve)

      review.trigger(:dismiss, actor: @owner, message: "Dismissed review")

      as @owner
      post "#{GitHub.url}/#{@repo.name_with_display_owner}/pull/#{@pull.number}/page_data/dismiss_review", xhr: true, params: { reviewId: review.id, message: "Dismissing" }

      assert_response :unprocessable_entity
    end

    test "returns 404 if the review is not found" do
      review = create(:pull_request_review, pull_request: @pull, user: @reader)
      review_id = review.id
      review.trigger(:approve)

      review.destroy

      as @owner
      post "#{GitHub.url}/#{@repo.name_with_display_owner}/pull/#{@pull.number}/page_data/dismiss_review", xhr: true, params: { reviewId: review_id, message: "Dismissing" }

      assert_response :not_found
    end

    test "returns 422 if branch protections prevent dismissal" do
      org_admin = create :user, login: "org-admin"
      org_writer = create :user, login: "org-writer"

      org = create(:organization, admin: org_admin)
      org.allow_private_repository_forking(actor: org.admins.first)

      org_repo = create :private_repository, owner: org, name: "org-repo", from_example: :pull_request_fork
      org_repo.add_member org_admin, action: :admin
      create(:collaborator, collaborator: org_writer, repository: org_repo, action: :write)
      org_repo_fork = create(:fork_repository, forker: org_admin, fork_repo: org_repo, from_example: :pull_request_fork)

      org_pr = create(:pull_request,
        repository: org_repo,
        base_repository: org_repo,
        base_ref: "master",
        head_repository: org_repo_fork,
        head_ref: "topic",
        user: org_admin,
        title:  "some title",
        body:  "some body",
      )

      protected_branch = create(:protected_branch, repository: org_repo, name: "*", pull_request_reviews_enforcement_level: :everyone)
      protected_branch.replace_dismissal_restricted_actors(user_ids: [org_admin], team_ids: [])

      refute protected_branch.review_dismissable_by?(org_writer)

      review = org_pr.reviews.create! user: org_writer, head_sha: org_pr.head_sha
      assert review.approve!

      as org_writer

      post "#{GitHub.url}/#{org_repo.name_with_display_owner}/pull/#{org_pr.number}/page_data/dismiss_review", xhr: true, params: { reviewId: review.id, message: "Dismissing" }
      assert_response :unprocessable_entity

      json = JSON.parse(response.body)
      assert_equal "You are not allowed to dismiss this review.", json["error"]
    end

    context "forks" do
      test "Users with write access can dismiss a review on forked prs" do
        forker = create(:user)
        fork_repo = create(:fork_repository, fork_repo: @repo, forker: forker, from_example: :pull_request_fork)
        fork_pull_request = create(:pull_request,
          repository: @repo,
          base_repository: @repo,
          head_repository: fork_repo,
          user:  forker,
          draft: true
        )
        review = create(:pull_request_review, pull_request: fork_pull_request, user: @reader)
        review.trigger(:approve)

        as @owner
        post "#{GitHub.url}/#{fork_pull_request.repository.name_with_display_owner}/pull/#{fork_pull_request.number}/page_data/dismiss_review", xhr: true, params: { reviewId: review.id, message: "Dismissing" }

        assert_response :success
      end
    end
  end

  context "#re_request_review_from_user" do
    test "returns 200 if the review is successfully re-requested" do
      review = @request_review_pull.reviews.create!(user: @user_to_request, head_sha: @request_review_pull.head_sha, body: "reviewed")
      review.comment!

      assert_empty @request_review_pull.review_requests.pending.reviewers

      as @hubber
      post "#{GitHub.url}/#{@private_repo.name_with_display_owner}/pull/#{@request_review_pull.number}/page_data/re_request_review_from_user", xhr: true, params: { reviewerLogin: @user_to_request.login }

      assert_response :success
      assert_equal [@user_to_request], @request_review_pull.review_requests.pending.reviewers
    end

    test "returns 422 if review is not able to be re-requested" do
      PullRequest.any_instance.stubs(:request_review_from).returns(false)
      review = @request_review_pull.reviews.create!(user: @user_to_request, head_sha: @request_review_pull.head_sha, body: "reviewed")
      review.comment!

      assert_empty @request_review_pull.review_requests.pending.reviewers

      as @hubber
      post "#{GitHub.url}/#{@private_repo.name_with_display_owner}/pull/#{@request_review_pull.number}/page_data/re_request_review_from_user", xhr: true, params: { reviewerLogin: @user_to_request.login }

      assert_response :unprocessable_entity
      assert_equal "Failed to re-request review.", JSON.parse(response.body)["error"]
    end
  end

  context "#re_request_review_from_team" do
    test "returns 200 if the review is successfully re-requested" do
      @request_review_pull.request_review_from(reviewers: [@team], actor: @hubber)
      review = @request_review_pull.reviews.create!(user: @user_to_request, head_sha: @request_review_pull.head_sha, body: "reviewed")
      review.comment!

      assert_empty @request_review_pull.review_requests.pending.reviewers
      team_name = "#{@org.login}/#{@team.name}"

      as @hubber
      post "#{GitHub.url}/#{@private_repo.name_with_display_owner}/pull/#{@request_review_pull.number}/page_data/re_request_review_from_team", xhr: true, params: { teamName: team_name }

      assert_response :success
      assert_equal [@team], @request_review_pull.review_requests.pending.reviewers
    end

    test "returns 404 if the review is from a nonexistent team" do
      @request_review_pull.request_review_from(reviewers: [@team], actor: @hubber)
      review = @request_review_pull.reviews.create!(user: @user_to_request, head_sha: @request_review_pull.head_sha, body: "reviewed")
      review.comment!

      assert_empty @request_review_pull.review_requests.pending.reviewers
      team_name = "#{@org.login}/#{@team.name}blabla"

      as @hubber
      post "#{GitHub.url}/#{@private_repo.name_with_display_owner}/pull/#{@request_review_pull.number}/page_data/re_request_review_from_team", xhr: true, params: { teamName: team_name }

      assert_response :not_found
    end

    test "returns 422 if not able to re-request for some reason" do
      PullRequest.any_instance.stubs(:request_review_from).returns(false)
      @request_review_pull.request_review_from(reviewers: [@team], actor: @hubber)
      review = @request_review_pull.reviews.create!(user: @user_to_request, head_sha: @request_review_pull.head_sha, body: "reviewed")
      review.comment!

      assert_empty @request_review_pull.review_requests.pending.reviewers
      team_name = "#{@org.login}/#{@team.name}"

      as @hubber
      post "#{GitHub.url}/#{@private_repo.name_with_display_owner}/pull/#{@request_review_pull.number}/page_data/re_request_review_from_team", xhr: true, params: { teamName: team_name }

      assert_response :unprocessable_entity
      assert_equal "Failed to re-request review.", JSON.parse(response.body)["error"]
    end
  end
end

class PullRequests::PageData::MergeQueueMutationsControllerTest < GitHub::IntegrationTestCase
  fixtures do
    # This is required to make the MergeQueues.system_actor, which is used in dispatching the webhook
    create(:merge_queue_integration)

    @owner = create(:user)
    @repo = create(:repository, owner: @owner, from_example: :simple)
    @reader = create(:collaborator, repository: @repo, action: :read)
    @merge_queue = create(:merge_queue, repository: @repo)
    @entry = create(:merge_queue_entry, :awaiting_checks, queue: @merge_queue, enqueuer: @owner)
    @pull = @entry.pull_request

    example_repo_snapshot

    @page_data_path = "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{@pull.number}/page_data"

    GitHub.flipper[:mergebox_react_partial].enable
    GitHub.flipper[:merge_queue].enable
  end

  setup do
    example_repo_restore
  end

  context "#dequeue_pull_request" do
    test "returns 200 for a successful request" do
      as @owner

      post "#{@page_data_path}/dequeue_pull_request", xhr: true

      refute @pull.reload.merge_queue_entry
      refute @pull.in_merge_queue?

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "Pull request was successfully removed from the merge queue.", json["message"]
    end

    test "returns 404 unless the mergebox_react_partial feature flag is enabled" do
      GitHub.flipper[:mergebox_react_partial].disable
      as @owner

      post "#{@page_data_path}/dequeue_pull_request", xhr: true

      assert @pull.reload.merge_queue_entry
      assert @pull.in_merge_queue?
      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 if no pull request found" do
      nonexistent_pull_number = 302
      as @owner

      post "#{GitHub.url}/#{@pull.repository.name_with_display_owner}/pull/#{nonexistent_pull_number}/page_data/dequeue_pull_request", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 if user does not have write permissions to repo" do
      as @reader

      post "#{@page_data_path}/dequeue_pull_request", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 if content authorization fails" do
      ContentAuthorizer.any_instance.stubs(:failed?).returns(true)

      as @owner

      post "#{@page_data_path}/dequeue_pull_request", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 404 if merge queue is not enabled or no merge queue found" do
      @merge_queue.destroy!

      as @owner

      post "#{@page_data_path}/dequeue_pull_request", xhr: true

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Not Found", json["error"]
    end

    test "returns 422 if dequeue request fails because of a group locked exception" do
      MergeQueue.any_instance.stubs(:dequeue).raises(MergeQueues::Errors::GroupLocked)
      as @owner

      post "#{@page_data_path}/dequeue_pull_request", xhr: true

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "Failed to remove pull request from the merge queue because the group is locked.", json["error"]
    end

    test "returns 422 if the pull request failed to dequeue" do
      MergeQueue.any_instance.stubs(:dequeue).returns(false)
      as @owner

      post "#{@page_data_path}/dequeue_pull_request", xhr: true

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_equal "Failed to remove pull request from the merge queue.", json["error"]
    end

    test "returns 422 if something else went wrong" do
      @merge_queue.errors[:base] << "whoops"
      MergeQueue.any_instance.stubs(:entry_for).raises(ActiveRecord::RecordInvalid.new(@merge_queue))

      as @owner

      post "#{@page_data_path}/dequeue_pull_request", xhr: true

      assert_response :unprocessable_entity
      json = JSON.parse(response.body)
      assert_match /Failed to remove pull request from the merge queue/, json["error"]
    end

    test "returns 406 for a non-XHR request" do
      as @owner

      post "#{@page_data_path}/dequeue_pull_request"

      assert_response :not_acceptable
    end
  end
end
