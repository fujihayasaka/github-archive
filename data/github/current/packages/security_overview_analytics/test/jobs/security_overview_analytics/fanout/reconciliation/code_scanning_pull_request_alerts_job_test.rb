# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  module Fanout
    module Reconciliation
      class CodeScanningPullRequestAlertsJobTest < GitHub::TestCase
        include DogstatsTestHelpers
        include JobTestHelper

        # This allow me to prepare sample refs during fixture instead of setup
        self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures

        fixtures do
          @user = create(:user)
          @org = create(:organization, admin: @user)
          @repo = create(:repository, owner: @org, admin: @user, from_example: :simple)

          @master_head = @repo.heads.find_or_build("master")
          @topic_branch_head_ref = @repo.heads.create("topic", @master_head.target, @user)
          @topic_branch_head_ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
            files.add("file001", "foo")
          end
          @another_topic_branch_head_ref = @repo.heads.create("another-topic", @master_head.target, @user)
          @another_topic_branch_head_ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
            files.add("file002", "foo")
          end

          # Merged PR will be included in fanout
          @pull = create(:pull_request,
            repository: @repo,
            base_repository: @repo,
            base_user: @user,
            base_ref: @repo.default_branch,
            head_repository: @repo,
            head_user: @user,
            head_ref: @topic_branch_head_ref.name,
            user: @user,
          )
          @pull.merge(@user, message_title: "msg", message: "body")
          @pull.reload

          # Forked PR will be included in fanout
          with_inline_repo_forking do
            @forked_repo = create(:fork_repository, forker: @user, fork_repo: @repo)
            @forked_repo_ref = @forked_repo.heads.find_or_build("master")
            @forked_repo_ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
              files.add("file005", "foo")
            end
            @forked_pull = create(:pull_request,
              repository: @repo,
              base_repository: @repo,
              base_user: @user,
              base_ref: "master",
              head_repository: @forked_repo,
              head_user: @user,
              head_ref: @forked_repo_ref.name,
              user: @user
            )
            @forked_pull.merge(@user, message_title: "msg", message: "body")
            @forked_pull.reload
            # Setup for test with `merged_at` window
            @forked_pull.merged_at = 10.days.ago
            @forked_pull.save!
          end

          # Non default branch based PR will NOT be included in fanout
          @pull_non_default_branch = create(:pull_request,
            repository: @repo,
            base_repository: @repo,
            base_user: @user,
            base_ref: @another_topic_branch_head_ref.name,
            head_repository: @repo,
            head_user: @user,
            head_ref: @topic_branch_head_ref.name,
            user: @user,
          )
          @pull_non_default_branch.merge(@user, message_title: "msg", message: "body")
          @pull_non_default_branch.reload

          # Unmerged PR will NOT be included in fanout
          @pull_not_merged = create(:pull_request,
            repository: @repo,
            base_repository: @repo,
            base_user: @user,
            base_ref: @repo.default_branch,
            head_repository: @repo,
            head_user: @user,
            head_ref: @another_topic_branch_head_ref.name,
            user: @user,
          )

          # Advisory workspace PR will NOT be included in fanout
          @advisory = create(:repository_advisory, repository: @repo, author: @user)
          @workspace_repo = perform_enqueued_jobs(only: [RepositoryCloneJob]) do
            GitHub.context.push(actor_id: @user.id)
            RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @user).tap(&:save!).tap(&:reload)
          end
          @workspace_repo_master_head = @workspace_repo.heads.find("master")
          @workspace_repo_master_head.append_commit({ message: "some changes", committer: @user }, @user) do |files|
            files.add("file003", "foo")
          end
          @workspace_pull = create(:pull_request,
            repository: @workspace_repo,
            base_repository: @repo,
            base_user: @user,
            base_ref: "master",
            head_repository: @workspace_repo,
            head_user: @user,
            head_ref: "master",
            issue: create(:issue, user: @user, repository: @workspace_repo),
            user: @user
          )

          on_multi_tenant_enterprise do
            @mt_user = create(:emu)
            @mt_business = @mt_user.enterprise_managed_business
            @mt_org = create :enterprise_linked_organization, :with_org_namespacing, business: @mt_business, admin: @mt_user
            @mt_repo = create(:private_repository, owner: @mt_org, admin: @mt_user, from_example: :simple)
            @mt_repo_master_head = @mt_repo.heads.find_or_build("master")
            @mt_repo_topic_head_ref = @mt_repo.heads.create("topic", @mt_repo_master_head.target, @mt_user)
            @mt_repo_topic_head_ref.append_commit({ message: "some changes", committer: @mt_user }, @mt_user) do |files|
              files.add("file001", "foo")
            end
            @mt_pull = create(:pull_request,
              repository: @mt_repo,
              base_repository: @mt_repo,
              base_user: @mt_user,
              base_ref: @mt_repo.default_branch,
              head_repository: @mt_repo,
              head_user: @mt_user,
              head_ref: @mt_repo_topic_head_ref.name,
              user: @mt_user,
            )
            @mt_pull.merge(@mt_user, message_title: "msg", message: "body")
            @mt_pull.reload
          end
        end

        setup do
          # Stubs for tenant validation
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
          # Stubs for code scanning availability
          ::Repository.any_instance.stubs(:code_scanning_usable?).returns(true)
          # Stubs for code scanning enablement
          ::Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(true)
        end

        context "#perform" do
          test "enqueues pull request alerts ingestion job" do
            CodeScanningPullRequestAlertsJob.stub_const(:BATCH_SIZE, 1) do
              perform_enqueued_jobs only: [CodeScanningPullRequestAlertsJob] do
                CodeScanningPullRequestAlertsJob.perform_now(repository_id: @repo.id, last_session_locked_at: nil)
              end
            end

            assert_enqueued_with(
              job: CodeScanningPullRequestAlertsIngestionJob,
              args: [{ pull_request_id: @pull.id, source_event: Types::Action::Reconcile.serialize }]
            )
            assert_enqueued_with(
              job: CodeScanningPullRequestAlertsIngestionJob,
              args: [{ pull_request_id: @forked_pull.id, source_event: Types::Action::Reconcile.serialize }]
            )

            assert_dogstats_distribution 1, "batched_job.total_time.dist"
            assert_dogstats_increment 3, "security_overview_analytics.repository_fanout.processed"
            refute_dogstats_increment "security_overview_analytics.repository_fanout.stopped"
          end

          test "enqueues for pull request merged within default lookback window if last_session_locked_at not passed " do
            CodeScanningPullRequestAlertsJob.stub_const(:DEFAULT_MAX_LOOKBACK_WINDOW_IN_DAYS, 5) do
              perform_enqueued_jobs only: [CodeScanningPullRequestAlertsJob] do
                CodeScanningPullRequestAlertsJob.perform_now(repository_id: @repo.id, last_session_locked_at: nil)
              end
            end

            assert_enqueued_with(
              job: CodeScanningPullRequestAlertsIngestionJob,
              args: [{ pull_request_id: @pull.id, source_event: Types::Action::Reconcile.serialize }]
            )
          end

          test "enqueues for pull request merged with last_session_locked_at if earlier than lookback window " do
            CodeScanningPullRequestAlertsJob.stub_const(:DEFAULT_MAX_LOOKBACK_WINDOW_IN_DAYS, 30) do
              perform_enqueued_jobs only: [CodeScanningPullRequestAlertsJob] do
                CodeScanningPullRequestAlertsJob.perform_now(repository_id: @repo.id, last_session_locked_at: 5.days.ago)
              end
            end

            assert_enqueued_with(
              job: CodeScanningPullRequestAlertsIngestionJob,
              args: [{ pull_request_id: @pull.id, source_event: Types::Action::Reconcile.serialize }]
            )
          end

          test "enqueues for pull request merged with default lookback window if last_session_locked_at is earlier than lookback window" do
            CodeScanningPullRequestAlertsJob.stub_const(:DEFAULT_MAX_LOOKBACK_WINDOW_IN_DAYS, 5) do
              perform_enqueued_jobs only: [CodeScanningPullRequestAlertsJob] do
                CodeScanningPullRequestAlertsJob.perform_now(repository_id: @repo.id, last_session_locked_at: 30.days.ago)
              end
            end

            assert_enqueued_with(
              job: CodeScanningPullRequestAlertsIngestionJob,
              args: [{ pull_request_id: @pull.id, source_event: Types::Action::Reconcile.serialize }]
            )
          end
        end

        context "input validations" do
          test "repository_id is required" do
            assert_no_enqueued_jobs(only: CodeScanningPullRequestAlertsJob) do
              assert_raises_with_message(ArgumentError, "Invalid repository_id input.") do
                CodeScanningPullRequestAlertsJob.perform_later
              end
            end
            refute CodeScanningPullRequestAlertsJob.new.locked?
          end

          test "stops if repository not found" do
            CodeScanningPullRequestAlertsJob.any_instance.expects(:perform).never

            CodeScanningPullRequestAlertsJob.perform_now(repository_id: 999999)

            assert_dogstats_increment 1, "security_overview_analytics.repository_fanout.stopped", tags: ["reason:repository_not_found"]
            refute_dogstats_increment "security_overview_analytics.repository_fanout.processed"
          end

          test "validates repository's tenant scope" do
            TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

            CodeScanningPullRequestAlertsJob.any_instance.expects(:perform).never

            CodeScanningPullRequestAlertsJob.perform_now(repository_id: @repo.id)

            assert_dogstats_increment 1, "security_overview_analytics.repository_fanout.stopped", tags: ["reason:ineligible_repo_owner"]
            refute_dogstats_increment "security_overview_analytics.repository_fanout.processed"
          end

          test "code scanning is required" do
            ::Repository.any_instance.stubs(:code_scanning_usable?).returns(false)

            CodeScanningPullRequestAlertsJob.any_instance.expects(:perform).never

            CodeScanningPullRequestAlertsJob.perform_now(repository_id: @repo.id)

            assert_dogstats_increment 1, "security_overview_analytics.repository_fanout.stopped", tags: ["reason:code_scanning_unavailable"]
            refute_dogstats_increment "security_overview_analytics.repository_fanout.processed"
          end

          test "code scanning enablement is required" do
            ::Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(false)

            CodeScanningPullRequestAlertsJob.any_instance.expects(:perform).never

            CodeScanningPullRequestAlertsJob.perform_now(repository_id: @repo.id)

            assert_dogstats_increment 1, "security_overview_analytics.repository_fanout.stopped", tags: ["reason:code_scanning_disabled"]
            refute_dogstats_increment "security_overview_analytics.repository_fanout.processed"
          end
        end

        context "resiliency" do
          test "it retries on standard conditions" do
            assert_retry_conditions(
              job: CodeScanningPullRequestAlertsJob,
              args: [repository_id: @repo.id, last_session_locked_at: Time.now],
              using_kwargs: true
            )
          end
        end

        context "hash lock" do
          test "does not allow concurrent jobs for the same pull request" do
            assert_enqueued_jobs 1, only: CodeScanningPullRequestAlertsJob do
              CodeScanningPullRequestAlertsJob.perform_later(repository_id: @repo.id, last_session_locked_at: Time.now)
              CodeScanningPullRequestAlertsJob.perform_later(repository_id: @repo.id)
            end
          end
        end

        context "on multi tenant enterprise" do
          test "sets the tenant context to the correct business" do
            on_multi_tenant_enterprise do
              ::Repositories::Public.expects(:resolve_tenant).with(id: @mt_repo.id).returns(@mt_business).once

              assert_enqueued_jobs 1, only: CodeScanningPullRequestAlertsIngestionJob do
                CodeScanningPullRequestAlertsJob.perform_now(repository_id: @mt_repo.id)
              end

              assert_dogstats_distribution 1, "batched_job.total_time.dist"
            end
          end
        end

        private

        def with_inline_repo_forking
          # This idea was taken from the `WithWorkingFork` module in another test.
          # Advice is a module in `test/test_helpers/advice.rb`
          advice_token = Advice.around(::Repository, :fork) do |_repo, callback|
            forked_repo = T.let(nil, T.nilable(Repository))
            status = T.let(nil, T.nilable(Symbol))
            errors = T.let(nil, T.nilable(T::Array[String]))

            perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
              forked_repo, status, errors = callback.call
            end
            forked_repo.reload if forked_repo
            [forked_repo, status, errors]
          end
          yield if block_given?
          Advice.unaround(advice_token)
        end
      end
    end
  end
end
