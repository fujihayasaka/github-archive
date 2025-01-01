# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    class StatusChecksSerializerTest < GitHub::TestCase
      include UrlHelper
      include StatusHelper

      fixtures do
        @owner = create(:user, login: "wiseguy")

        @repo = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
        branch_attributes = {
          name: "master",
          creator: @owner,
          required_status_checks_enforcement_level: :non_admins,
        }
        @protected_branch = @repo.protected_branches.create(branch_attributes)
        @status_check = RequiredStatusCheck.new(
          protected_branch: @protected_branch,
          context: "Testing",
        )
        @status_check.save!

        @pull = create(:pull_request,
            repository: @repo,
            base_repository: @repo,
            base_user: @repo.owner,
            base_ref: "master",
            head_repository: @repo,
            head_user: @repo.owner,
            head_ref: "topic",
            user: @owner
          )

        @actions_app = create :launch_integration
        # status context
        @oauth_application = create(:oauth_application, name: "Lofty-CI", url: "https://lofty-ci.com/")
        @status_context = create(:status,
          oauth_application: @oauth_application,
          repository: @repo,
          creator: @repo.owner,
          sha: @pull.head_sha,
          context: "context1",
          state: "success",
          description: "yeah",
          target_url: "https://github.com/"
        )

        # check run
        @github_app = create :integration, default_permissions: { "checks" => :write }
        @check_suite = create(:check_suite, repository: @repo, github_app: @github_app, head_sha: @pull.head_sha)
        @check_run = create(:check_run, name: "foo", check_suite: @check_suite, status: :completed, completed_at: Time.now, conclusion: :success)
      end

      test "serializes statusContexts, checkRuns, RequiredStatusChecks, and InMemoryRequiredStatusChecks" do
        merge_button_view = PullRequests::MergeButtonView.new(pull: @pull, current_user: @pull.user)

        rule_config = @protected_branch.required_status_checks_policy
        required_status_check = RequiredStatusCheck.new(protected_branch: @protected_branch, context: "plain text")
        in_memory_check = InMemoryRequiredStatusCheck.normalize_status_checks(rule_config, rule_config.param("required_status_checks"))
        wrapped_run = CombinedStatus::CheckRunAdapter.new(@check_run)

        # added this for enterprise mode to not create a second InMemoryRequiredStatusCheck
        PullRequest::MergeStatus.any_instance.stubs(:target_branch_policy_evaluator).returns(false)

        status_checks = merge_button_view.combined_status.status_checks + in_memory_check + [required_status_check]

        # RequiredStatusChecks and InMemoryRequiredStatusCheck use Time.now so freezing for tests
        freeze_time
        serializer = PullRequests::PageData::StatusChecksSerializer.new(
          status_checks: status_checks,
          pull_request: @pull,
          avatar_size: nil,
        )
        json_payload = {
          "aliveChannels" => {
            "commitHeadShaChannel" => GitHub::WebSocket::Channels.signed_commit(@pull.base_repository, @pull.head_sha)
          },
          "statusChecks" => [
            { "description" => T.must(in_memory_check[0]).description,
              "durationInSeconds" => T.must(in_memory_check[0]).duration_in_seconds,
              "stateChangedAt" => T.must(in_memory_check[0]).state_changed_at.to_time,
              "isRequired" => true,
              "displayName" => T.must(in_memory_check[0]).context,
              "state" => T.must(in_memory_check[0]).state.upcase,
              "targetUrl" => nil,
              "avatarUrl" => nil,
              "additionalContext" => additional_status_check_context(T.must(in_memory_check[0]).state, T.must(in_memory_check[0]).duration_in_seconds)
            },
            { "description" => required_status_check.description,
              "durationInSeconds" => required_status_check.duration_in_seconds,
              "stateChangedAt" => required_status_check.state_changed_at.to_time,
              "isRequired" => true,
              "displayName" => required_status_check.context,
              "state" => required_status_check.state.upcase,
              "targetUrl" => nil,
              "avatarUrl" => nil,
              "additionalContext" => additional_status_check_context(required_status_check.state, required_status_check.duration_in_seconds)
            },
            { "description" => @status_context.description,
              "durationInSeconds" => @status_context.duration_in_seconds,
              "stateChangedAt" => @status_context.created_at.to_time,
              "isRequired" => false,
              "displayName" => @status_context.contextual_name,
              "state" => @status_context.state.upcase,
              "targetUrl" => @status_context.target_url,
              "avatarUrl" => @status_context.application.preferred_avatar_url(size: 40),
              "additionalContext" => additional_status_check_context(@status_context.state, @status_context.duration_in_seconds)
            },
            { "description" => wrapped_run.description,
              "durationInSeconds" => wrapped_run.duration_in_seconds,
              "stateChangedAt" => wrapped_run.state_changed_at.to_time,
              "isRequired" => false,
              "displayName" => wrapped_run.context,
              "state" => wrapped_run.state.upcase,
              "targetUrl" => wrapped_run.target_url(pull: @pull),
              "avatarUrl" => wrapped_run.creator.primary_avatar_url(40),
              "additionalContext" => additional_status_check_context(wrapped_run.state, wrapped_run.duration_in_seconds)
            },
          ],
         "statusRollup" => {
            "summary" => [
              { "count" => 2, "state" => "SUCCESS" },
              { "count" => 2, "state" => "EXPECTED" },
            ],
            "combinedState" => "PENDING",
          }
        }
        assert_equal json_payload.to_json, serializer.to_hash.to_json
      end

      test "handles serializing every possible status defined in StatusCheckConfig without type errors" do
        StatusCheckConfig::STATUSES.each do |status|
          assert_nothing_raised do
            PullRequests::PageData::StatusChecksSerializer::StatusCheckState.deserialize(status.enum.to_s.upcase)
          end
        end
      end
    end
  end
end
