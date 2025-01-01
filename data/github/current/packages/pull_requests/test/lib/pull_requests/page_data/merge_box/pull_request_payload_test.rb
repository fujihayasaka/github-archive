# typed: true
# frozen_string_literal: true


require "test_helper"
module PullRequests
  module PageData
    module MergeBox
      class PullRequestPayloadTest < GitHub::TestCase
        fixtures do
          @owner = create(:user, login: "wiseguy")
          @forker = create(:user, login: "sweetsue")
          @org = create :organization, plan: "bronze", admin: @owner

          @source = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
          create(:collaborator, collaborator: @forker, repository: @source)
          @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

          @team = create(:team, organization: @org, privacy: :closed)
          @team.add_member(@team_reviewer)
          @team.add_repository(@source, :pull)

          @issue = create(:issue, user: @forker, repository: @source, title: "A Title")
          @pull = create(:pull_request,
            repository: @source,
            base_repository: @source,
            base_user: @source.owner,
            base_ref: "master",
            head_repository: @fork,
            head_user: @fork.owner,
            head_ref: "topic",
            issue: @issue,
            user: @forker
          )
          @pull.request_review_from(reviewers: [@team], actor: @owner)
          @submitted_review = @pull.reviews.create!(
            user: @owner,
            head_sha: @pull.head_sha,
            body: ":+1:",
          )

          @submitted_review.approve!

          example_repo_snapshot
        end

        setup do
          example_repo_restore
        end

        context "#call" do
          test "builds and returns a PullRequestPayload object" do
            pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @pull.user)
            actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)

            expected_payload = {
              "autoMergeRequest" => nil,
              "baseRefName" => @pull.base_ref_name,
              "headRefOid" => @pull.head_sha,
              "headRefName" => @pull.head_ref,
              "headRepository" => { "ownerLogin" => @fork.owner.display_login, "name" => @fork.name },
              "id" => @pull.global_relay_id,
              "isDraft" => false,
              "isInMergeQueue" => false,
              "latestOpinionatedReviews" => [build_latetest_opionated_review(@submitted_review)],
              "mergeBoxAliveChannels" =>
                { "stateChannel" => GitHub::WebSocket::Channels.signed_pull_request_state(@pull),
                  "deployedChannel" => GitHub::WebSocket::Channels.signed_pull_request_deployed(@pull),
                  "reviewStateChannel" => GitHub::WebSocket::Channels.signed_pull_request_review_state(@pull),
                  "workflowsChannel" => GitHub::WebSocket::Channels.signed_pull_request_workflow_run_state(@pull),
                  "mergeQueueChannel" => GitHub::WebSocket::Channels.signed_pull_request_merge_queue_entry_state(@pull),
                  "headRefChannel" => GitHub::WebSocket::Channels.signed_branch(@pull.head_repository, @pull.display_head_ref_name),
                  "baseRefChannel" => GitHub::WebSocket::Channels.signed_branch(@pull.base_repository, @pull.display_base_ref_name),
                  "commitHeadShaChannel" => GitHub::WebSocket::Channels.signed_commit(@pull.base_repository, @pull.head_sha),
                  "gitMergeStateChannel" => GitHub::WebSocket::Channels.signed_pull_request_git_merge_state(@pull)
                  },
              "mergeQueue" => nil,
              "mergeQueueEntry" => nil,
              "mergeStateStatus" => "UNKNOWN",
              "numberOfCommits" => @pull.total_commits,
              "resourcePath" => @pull.url,
              "state" => @pull.state.upcase,
              "viewerCanAddAndRemoveFromMergeQueue" => false,
              "viewerCanDeleteHeadRef" => false,
              "viewerCanDisableAutoMerge" => false,
              "viewerCanEnableAutoMerge" => false,
              "viewerCanRestoreHeadRef" => false,
              "viewerCanUpdateBranch" => false,
              "viewerCanUpdate" => true,
              "viewerDidAuthor" => true,
              "viewerMergeActions" => build_viewer_merge_actions
            }

            assert_equal expected_payload.as_json, actual_payload.as_json
            assert_no_queries do
              PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
            end
          end
        end

        test "returns the correct enum value for mergeStateStatus" do
          PullRequest::MergeState.any_instance.stubs(:status).returns(:unknown)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @pull.user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
          assert_equal "UNKNOWN", actual_payload.mergeStateStatus.as_json

          PullRequest::MergeState.any_instance.stubs(:status).returns(:behind)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @pull.user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
          assert_equal "BEHIND", actual_payload.mergeStateStatus.as_json

          PullRequest::MergeState.any_instance.stubs(:status).returns(:blocked)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @pull.user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
          assert_equal "BLOCKED", actual_payload.mergeStateStatus.as_json

          PullRequest::MergeState.any_instance.stubs(:status).returns(:clean)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @pull.user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
          assert_equal "CLEAN", actual_payload.mergeStateStatus.as_json

          PullRequest::MergeState.any_instance.stubs(:status).returns(:dirty)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @pull.user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
          assert_equal "DIRTY", actual_payload.mergeStateStatus.as_json

          PullRequest::MergeState.any_instance.stubs(:status).returns(:draft)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @pull.user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
          assert_equal "DRAFT", actual_payload.mergeStateStatus.as_json

          PullRequest::MergeState.any_instance.stubs(:status).returns(:has_hooks)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @pull.user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
          assert_equal "HAS_HOOKS", actual_payload.mergeStateStatus.as_json

          PullRequest::MergeState.any_instance.stubs(:status).returns(:unstable)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @pull.user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
          assert_equal "UNSTABLE", actual_payload.mergeStateStatus.as_json
        end

        test "returns the correct enum value for state" do
          PullRequest.any_instance.stubs(:state).returns(:closed)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @pull.user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
          assert_equal "CLOSED", actual_payload.state.as_json

          PullRequest.any_instance.stubs(:state).returns(:open)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @pull.user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
          assert_equal "OPEN", actual_payload.state.as_json

          PullRequest.any_instance.stubs(:state).returns(:merged)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: @pull, current_user: @pull.user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)
          assert_equal "MERGED", actual_payload.state.as_json
        end

        test "builds and returns a PullRequestPayload object for a PullRequest in a Merge queue" do
          entry = create(:merge_queue_entry)
          pull = entry.pull_request
          repo = pull.repository
          repo.enable_feature(:merge_queue)
          user = repo.owner
          queue = entry.queue

          MergeQueueEntry.any_instance.stubs(:state).returns(:waiting)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: pull, current_user: user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)

          expected_merge_queue = { "url" => "#{GitHub.url}#{queue.async_path_uri.sync.path}" }.as_json
          expected_merge_queue_entry = { "position" => entry.position, "state" => "WAITING" }.as_json
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data).as_json

          assert_equal expected_merge_queue, actual_payload["mergeQueue"]
          assert_equal expected_merge_queue_entry, actual_payload["mergeQueueEntry"]

          MergeQueueEntry.any_instance.stubs(:state).returns(:awaiting_checks)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: pull, current_user: user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)

          expected_merge_queue_entry = { "position" => entry.position, "state" => "AWAITING_CHECKS" }.as_json
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data).as_json
          assert_equal expected_merge_queue_entry, actual_payload["mergeQueueEntry"]

          MergeQueueEntry.any_instance.stubs(:state).returns(:mergeable)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: pull, current_user: user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)

          expected_merge_queue_entry = { "position" => entry.position, "state" => "MERGEABLE" }.as_json
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data).as_json

          assert_equal expected_merge_queue_entry, actual_payload["mergeQueueEntry"]

          MergeQueueEntry.any_instance.stubs(:state).returns(:queued)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: pull, current_user: user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)

          expected_merge_queue_entry = { "position" => entry.position, "state" => "QUEUED" }.as_json
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data).as_json

          assert_equal expected_merge_queue_entry, actual_payload["mergeQueueEntry"]

          MergeQueueEntry.any_instance.stubs(:state).returns(:unmergeable)
          pull_request_data = PullRequests::PageData::MergeBox::PullRequestLoader.load(pull_request: pull, current_user: user)
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data)

          expected_merge_queue_entry = { "position" => entry.position, "state" => "UNMERGEABLE" }.as_json
          actual_payload = PullRequests::PageData::MergeBox::PullRequestPayload.call(pull_request_data).as_json

          assert_equal expected_merge_queue_entry, actual_payload["mergeQueueEntry"]
        end

        def build_latetest_opionated_review(review)
          PullRequests::PageData::MergeBox::PullRequestPayload::OpinionatedReviewPayload.new(
            authorCanPushToRepository: true,
            author: build_review_author(review.user),
            onBehalfOf: [],
            state: PullRequests::PageData::MergeBox::PullRequestPayload::PullRequestReviewState.deserialize(
              PullRequestReview.state_name(review.state)&.upcase.to_s)
          )
        end

        def build_review_author(reviewer)
          PullRequests::PageData::MergeBox::PullRequestPayload::AuthorPayload.new(
            login: reviewer.login,
            avatarUrl: reviewer.primary_avatar_url,
            name: reviewer.name,
            url: reviewer.permalink
          )
        end

        def build_viewer_merge_actions
          [
            build_viewer_merge_action(name: "MERGE_QUEUE", merge_methods: [
              build_viewer_merge_methods(name: "MERGE", is_allowable: false, is_allowable_with_bypass: false, is_default: true),
              build_viewer_merge_methods(name: "SQUASH", is_allowable: false, is_allowable_with_bypass: false, is_default: false),
              build_viewer_merge_methods(name: "REBASE", is_allowable: false, is_allowable_with_bypass: false, is_default: false)
            ]),
            build_viewer_merge_action(name: "DIRECT_MERGE", merge_methods: [
              build_viewer_merge_methods(name: "MERGE", is_allowable: true, is_allowable_with_bypass: false, is_default: true),
              build_viewer_merge_methods(name: "SQUASH", is_allowable: true, is_allowable_with_bypass: false, is_default: false),
              build_viewer_merge_methods(name: "REBASE", is_allowable: true, is_allowable_with_bypass: false, is_default: false)
            ])
          ]
        end

        def build_viewer_merge_methods(name:, is_allowable:, is_allowable_with_bypass:, is_default:)
          PullRequests::PageData::MergeBox::PullRequestPayload::ViewerMergeMethods.new(
            isAllowable: is_allowable,
            isAllowableWithBypass: is_allowable_with_bypass,
            name: PullRequests::PageData::MergeBox::PullRequestPayload::MergeMethod.deserialize(name.to_s.upcase),
            isDefault: is_default
          )
        end

        def build_viewer_merge_action(name: "MERGE_QUEUE", is_allowable_with_bypass: false, merge_methods:)
          PullRequests::PageData::MergeBox::PullRequestPayload::ViewerMergeActions.new(
            isAllowable: name == "MERGE_QUEUE" ? false : true,
            mergeMethods: merge_methods,
            isAllowableWithBypass: is_allowable_with_bypass,
            name: PullRequests::PageData::MergeBox::PullRequestPayload::MergeAction.deserialize(name.to_s.upcase)
          )
        end
      end
    end
  end
end
