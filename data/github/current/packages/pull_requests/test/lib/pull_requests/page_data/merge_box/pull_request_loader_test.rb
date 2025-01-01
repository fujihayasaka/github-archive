# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    module MergeBox
      class PullRequestLoaderTest < GitHub::TestCase
        fixtures do
          create(:merge_queue_integration)
          @owner = create(:user, login: "wiseguy")
          @forker = create(:user, login: "sweetsue")
          @org = create :organization, plan: "bronze", admin: @owner
          @org_repo = create(:private_repository, owner: @org, name: "org_repo", from_example: :review_comment_fork)

          @source = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
          @collaborator = create(:collaborator, collaborator: @forker, repository: @source)

          @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

          @viewer = create(:user, login: "viewer")
          @team = create(:team, organization: @org, privacy: :closed)
          @team.add_member(@owner)
          @team.add_member(@viewer)
          @team.add_repository(@source, :pull)

          @pull =
            create(:pull_request,
              repository: @source,
              base_repository: @source,
              base_user: @source.owner,
              base_ref: "master",
              head_repository: @fork,
              head_user: @fork.owner,
              head_ref: "topic",
              user: @forker
            )

          @org_pull =
            create(:pull_request,
              repository: @org_repo,
              base_repository: @org_repo,
              base_user: @owner,
              base_ref: "master",
              head_repository: @org_repo,
              head_user: @owner,
              head_ref: "topic",
              user: @owner
            )

          @additional_reviewer = create(:collaborator, repository: @source, login: "betty")
          @code_owner_reviewer = create(:collaborator, repository: @source, login: "juan-mayor")
          @pull.request_review_from(reviewers: [@team, @additional_reviewer, @code_owner_reviewer], actor: @owner)

          review_request = ReviewRequest.find_by(reviewer_id: @code_owner_reviewer.id)
          review_request&.reasons&.create!(
            reason_type: "codeowners",
            codeowners_tree_oid: "725a9899207f0b65f51f27dba5eb77822edaf740",
            codeowners_path: "CODEOWNERS",
            codeowners_line: 1,
            codeowners_pattern: /foobar/,
          )

          @submitted_review = @pull.reviews.create!(
            user: @owner,
            head_sha: @pull.head_sha,
            body: ":+1:",
          )
          @submitted_review.approve!

          @pull2 =
            create(:pull_request,
              repository: @source,
              base_repository: @source,
              base_user: @source.owner,
              base_ref: @source.default_branch,
              head_repository: @source,
              head_user: @source.owner,
              head_ref: "topic",
              user: @forker
            )

          enable_feature_flag(:linear_history_check_consider_missing_head_success, @pull.repository)
        end

        test "returns expected data" do
          expected_pull_request_data = {
            auto_merge_request: nil,
            base_repository: @source,
            codespaces: [],
            pull_request: @pull,
            head_repository: @fork,
            head_repository_owner: @fork.owner,
            merge_queue: nil,
            merge_queue_entry: nil,
            merge_state: :unknown,
            total_commits: @pull.total_commits,
            viewer_can_add_and_remove_from_merge_queue: false,
            viewer_did_author: false,
            viewer_can_delete_head_ref: false,
            viewer_can_disable_auto_merge: false,
            viewer_can_enable_auto_merge: false,
            viewer_can_restore_head_ref: false,
            viewer_can_update: true,
            viewer_can_update_branch: false,
          }
          actual_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          # Just assert the merge actions with merge methods are returned
          assert actual_data.allowable_merge_actions

          first_merge_action = actual_data.allowable_merge_actions.first
          assert_equal :blocked, T.must(first_merge_action).allowable_status
          assert T.must(first_merge_action).name
          assert T.must(first_merge_action).merge_methods

          assert_equal expected_pull_request_data[:viewer_can_update], actual_data.viewer_can_update
          assert_equal expected_pull_request_data[:viewer_can_update_branch], actual_data.viewer_can_update_branch
          assert_equal expected_pull_request_data[:viewer_can_restore_head_ref], actual_data.viewer_can_restore_head_ref
          assert_equal expected_pull_request_data[:viewer_can_enable_auto_merge], actual_data.viewer_can_enable_auto_merge
          assert_equal expected_pull_request_data[:viewer_can_disable_auto_merge], actual_data.viewer_can_disable_auto_merge
          assert_equal expected_pull_request_data[:viewer_can_delete_head_ref], actual_data.viewer_can_delete_head_ref
          assert_equal expected_pull_request_data[:viewer_did_author], actual_data.viewer_did_author
          assert_equal expected_pull_request_data[:viewer_can_add_and_remove_from_merge_queue], actual_data.viewer_can_add_and_remove_from_merge_queue
          assert_equal expected_pull_request_data[:total_commits], actual_data.total_commits
          assert_equal [], actual_data.deprovisionable_codespaces

          assert actual_data.latest_opinionated_reviews
          first_opinionated_review = T.must(actual_data.latest_opinionated_reviews.first)
          assert first_opinionated_review.author_can_push_to_repository
          assert_equal [], first_opinionated_review.on_behalf_of
          assert_equal @submitted_review.user, first_opinionated_review.author
          assert_equal @submitted_review.state, first_opinionated_review.state

          assert actual_data.pending_review_requests
          assert_equal 2, actual_data.pending_review_requests.count
          pending_review_requests = T.must(actual_data.pending_review_requests)
          code_owner_review_request = T.must(pending_review_requests.find { |request| T.must(request.reviewer).name == @code_owner_reviewer.name })
          additional_reviewer_review_request = T.must(pending_review_requests.find { |request| T.must(request.reviewer).name == @additional_reviewer.name })
          assert_equal @additional_reviewer, additional_reviewer_review_request.reviewer
          assert_equal @code_owner_reviewer, code_owner_review_request.reviewer
          refute additional_reviewer_review_request.is_code_owner
          assert code_owner_review_request.is_code_owner

          assert_equal expected_pull_request_data[:merge_state], actual_data.merge_state
          assert_nil actual_data.merge_queue_entry
          assert_nil actual_data.merge_queue
          assert_equal expected_pull_request_data[:head_repository], actual_data.head_repository
          assert_equal expected_pull_request_data[:base_repository], actual_data.base_repository
          assert_equal expected_pull_request_data[:pull_request], actual_data.pull_request
          assert_equal expected_pull_request_data[:head_repository_owner], actual_data.head_repository_owner
          assert_nil actual_data.auto_merge_request
        end

        test "loads and returns the auto merge request when it exists" do
          auto_merge_request = create(:auto_merge_request, user: @owner)
          assert auto_merge_request.pull_request

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: auto_merge_request.pull_request, current_user: @owner)

          assert T.must(data.auto_merge_request)
        end

        test "loads and returns merge queue when it exists" do
          merge_queue = create(:merge_queue, repository: @source)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull2, current_user: @owner)

          assert T.must(data.merge_queue)
        end

        test "loads and returns merge queue entry when it exists" do
          merge_queue = create(:merge_queue, repository: @source)
          merge_queue_entry = create(:merge_queue_entry, queue: merge_queue)
          pull = merge_queue_entry.pull_request
          assert pull

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: pull, current_user: @owner)

          assert T.must(data.merge_queue_entry)
        end

        test "loads and returns codespaces associated to Pull Request that can be deprovisioned when they exist" do
          codespace = create(:codespace, pull_request: @pull, owner: @owner)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          assert_equal [codespace], data.deprovisionable_codespaces
        end

        test "uses fallback value when total commits count query fails" do
          PullRequest.any_instance.stubs(:total_commits).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          assert_equal 0, data.total_commits
        end

        test "uses fallback value when #async_can_add_to_merge_queue? query fails" do
          PullRequest.any_instance.stubs(:async_can_add_to_merge_queue?).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          assert_equal false, data.viewer_can_add_and_remove_from_merge_queue
        end

        test "uses fallback value when #can_disable_auto_merge? query fails" do
          PullRequest.any_instance.stubs(:can_disable_auto_merge?).with(actor: @owner).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          assert_equal false, data.viewer_can_disable_auto_merge
        end

        test "uses fallback value when #can_enable_auto_merge? query fails" do
          PullRequest.any_instance.stubs(:can_enable_auto_merge).with(actor: @owner).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          assert_equal false, data.viewer_can_enable_auto_merge
        end

        test "uses fallback value when #head_ref_restorable_by query fails" do
          PullRequest.any_instance.stubs(:head_ref_restorable_by?).with(@owner).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          assert_equal false, data.viewer_can_restore_head_ref
        end

        test "uses fallback value when #async_viewer_can_update? query fails" do
          PullRequest.any_instance.stubs(:async_viewer_can_update?).with(@owner).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          assert_equal false, data.viewer_can_update
        end

        test "uses fallback value when #async_branch_is_updatable_by? query fails" do
          PullRequest.any_instance.stubs(:async_branch_is_updatable_by?).with(@owner).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          assert_equal false, data.viewer_can_update_branch
        end

        test "uses fallback value when #head_ref_deleteable_by? query fails" do
          PullRequest.any_instance.stubs(:head_ref_deleteable_by?).with(@owner).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          assert_equal false, data.viewer_can_delete_head_ref
        end

        test "uses fallback value when #latest_opinionated_reviews query fails" do
          PullRequest.any_instance.stubs(:latest_enforced_reviews).with(writers_only: false).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          assert_equal [], data.latest_opinionated_reviews
        end

        test "uses fallback value when #pending_review_requests query fails" do
          PullRequest.any_instance.stubs(:review_requests_pending).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          assert_equal [], data.pending_review_requests
        end

        test "uses fallback value when MergeState#status query fails" do
          skip "Skipping this test as it will be deleted in a follow-up PR"

          PullRequest::MergeState.any_instance.stubs(:status).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)

          assert_equal :unknown, data.merge_state
        end

        context "#viewer_can_add_to_merge_queue_solo field" do
          test "returns false if no merge queue exists" do
            assert_nil @pull.merge_queue
            refute PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner).viewer_can_add_to_merge_queue_solo
          end

          test "returns false if merge queue doesn't require deployments" do
            enable_feature_flag(:merge_queue_deploy_then_merge, @source)
            merge_queue = create(:merge_queue, repository: @source, branch: @source.default_branch)
            MergeQueue.any_instance.stubs(:requires_deployments_before_merging?).returns(false)

            refute PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner).viewer_can_add_to_merge_queue_solo
          end

          test "returns true if merge queue requires deployments and user has access to add to merge queue solo" do
            enable_feature_flag(:merge_queue_deploy_then_merge, @source)
            merge_queue = create(:merge_queue, repository: @source, branch: @source.default_branch)
            MergeQueue.any_instance.stubs(:requires_deployments_before_merging?).returns(true)

            # As this is a paid organization used in the test, the owner will have access to add to the merge queue solo
            assert PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner).viewer_can_add_to_merge_queue_solo
          end

          test "returns false if merge queue requires deployments and user does not have access to add to merge queue solo" do
            enable_feature_flag(:merge_queue_deploy_then_merge, @source)
            merge_queue = create(:merge_queue, repository: @source, branch: @source.default_branch)
            MergeQueue.any_instance.stubs(:requires_deployments_before_merging?).returns(true)

            # As this is a paid organization used in the test, the @viewer will not have access to add to the merge queue solo
            refute PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @viewer).viewer_can_add_to_merge_queue_solo
          end

          test "uses fallback value when #viewer_can_add_to_merge_queue_solo query fails" do
            PullRequest.any_instance.stubs(:can_add_to_merge_queue_solo?).raises(ActiveRecord::ActiveRecordError.new)
            refute PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner).viewer_can_add_to_merge_queue_solo
          end
        end

        context "#viewer_can_admin_bypass_merge_requirements" do
          test "returns false when merge type is 'squash' and the only failing rule is linear history" do
            PullRequest::MergeState.any_instance.stubs(:merge_method).returns(:squash)

            ruleset = create(:repository_ruleset, :repo_admin_bypass, enforcement: :enabled, source: @org_repo)
            create(:repository_rule_condition, :targets_branch, branch_name: "refs/heads/master", repository_ruleset: ruleset)
            create(:repository_rule_configuration, rule_type: "required_linear_history", repository_ruleset: ruleset)

            @org_pull.create_merge_commit

            data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @org_pull, current_user: @owner)
            refute data.viewer_can_admin_bypass_merge_requirements
          end

          test "returns true when merge type is 'merge' and the only failing rule is linear history" do
            PullRequest::MergeState.any_instance.stubs(:merge_method).returns(:merge)

            ruleset = create(:repository_ruleset, :repo_admin_bypass, enforcement: :enabled, source: @org_repo)
            create(:repository_rule_condition, :targets_branch, branch_name: "refs/heads/master", repository_ruleset: ruleset)
            create(:repository_rule_configuration, rule_type: "required_linear_history", repository_ruleset: ruleset)

            @org_pull.create_merge_commit

            data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @org_pull, current_user: @owner)
            assert data.viewer_can_admin_bypass_merge_requirements
          end

          test "returns false when merge type is 'merge' and the only failing rule is linear history but the user is not an admin" do
            PullRequest::MergeState.any_instance.stubs(:merge_method).returns(:merge)

            ruleset = create(:repository_ruleset, :repo_admin_bypass, enforcement: :enabled, source: @org_repo)
            create(:repository_rule_condition, :targets_branch, branch_name: "refs/heads/master", repository_ruleset: ruleset)
            create(:repository_rule_configuration, rule_type: "required_linear_history", repository_ruleset: ruleset)

            @org_pull.create_merge_commit

            data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @org_pull, current_user: @viewer)
            refute data.viewer_can_admin_bypass_merge_requirements
          end
        end

        context "#allowable_update_methods" do
          test "only rebase is allowed when linear history is required" do
            enable_feature_flag(:mergebox_update_branch_methods, @owner)
            @pull.head_repository.protect_branch(@pull.head_ref_name, creator: @owner, required_linear_history: true, entry_point: :test_case)
            PullRequest::Updateability.any_instance.stubs(:check_rebaseability).with(@owner).returns(PullRequest::Updateability::Success.new)

            data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)
            rebase_option = data.allowable_update_methods&.find { |method| method.name == :rebase }
            merge_option = data.allowable_update_methods&.find { |method| method.name == :merge }
            assert_equal :allowed, T.must(rebase_option).allowable_status
            assert_equal :blocked, T.must(merge_option).allowable_status
          end

          test "when cprmc ff is enabled and repo rules disallow rebase methods" do
            enable_feature_flag(:mergebox_update_branch_methods, @owner)
            enable_feature_flag(:cprmc_skip_rebase_via_api, @source)
            @pull.stubs(:merge_commit_allowed?).returns(false)
            @pull.stubs(:rebase_merge_allowed?).returns(false)

            PullRequest::Updateability.any_instance.stubs(:check_mergeability).with(@owner).returns(PullRequest::Updateability::Success.new)

            data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)
            rebase_option = T.must(data.allowable_update_methods).find { |method| method.name == :rebase }
            merge_option = T.must(data.allowable_update_methods).find { |method| method.name == :merge }
            assert_equal :blocked, T.must(rebase_option).allowable_status
            assert_equal :allowed, T.must(merge_option).allowable_status
          end

          test "by default merge and rebase methods are allowed" do
            enable_feature_flag(:mergebox_update_branch_methods, @owner)
            PullRequest::Updateability.any_instance.stubs(:check_mergeability).with(@owner).returns(PullRequest::Updateability::Success.new)
            PullRequest::Updateability.any_instance.stubs(:check_rebaseability).with(@owner).returns(PullRequest::Updateability::Success.new)

            data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)
            rebase_option = T.must(data.allowable_update_methods).find { |method| method.name == :rebase }
            merge_option = T.must(data.allowable_update_methods).find { |method| method.name == :merge }
            assert_equal :allowed, T.must(rebase_option).allowable_status
            assert_equal :allowed, T.must(merge_option).allowable_status
          end

          test "when mergeability_check fails, and merge method is not allowed" do
            enable_feature_flag(:mergebox_update_branch_methods, @owner)
            PullRequest::Updateability.any_instance.stubs(:check_mergeability).with(@owner).returns(PullRequest::Updateability::Failure.new("This branch is up to date."))
            PullRequest::Updateability.any_instance.stubs(:check_rebaseability).with(@owner).returns(PullRequest::Updateability::Success.new)

            data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)
            rebase_option = T.must(data.allowable_update_methods).find { |method| method.name == :rebase }
            merge_option = T.must(data.allowable_update_methods).find { |method| method.name == :merge }
            assert_equal :allowed, T.must(rebase_option).allowable_status
            assert_equal :blocked, T.must(merge_option).allowable_status
            assert_equal "This branch is up to date.", T.must(merge_option).failure_reason
          end


          test "when there are rebase conflicts, and rebase method is unavailable" do
            enable_feature_flag(:mergebox_update_branch_methods, @owner)
            PullRequest::Updateability.any_instance.stubs(:check_mergeability).with(@owner).returns(PullRequest::Updateability::Success.new)
            PullRequest::Updateability.any_instance.stubs(:check_rebaseability).with(@owner).returns(PullRequest::Updateability::Failure.new("This branch has rebase conflicts with the base branch"))
            PullRequest.any_instance.stubs(:rebase_conflicts?).returns(true)

            data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @owner)
            rebase_option = T.must(data.allowable_update_methods).find { |method| method.name == :rebase }
            merge_option = T.must(data.allowable_update_methods).find { |method| method.name == :merge }
            assert_equal :unavailable, T.must(rebase_option).allowable_status
            assert_equal :allowed, T.must(merge_option).allowable_status
            assert_equal "This branch cannot be rebased due to conflicts.", T.must(rebase_option).failure_reason
          end
        end
      end
    end
  end
end
