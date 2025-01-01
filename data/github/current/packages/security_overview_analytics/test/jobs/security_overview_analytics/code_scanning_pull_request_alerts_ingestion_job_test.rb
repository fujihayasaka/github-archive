# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "turboscan"

module SecurityOverviewAnalytics
  class CodeScanningPullRequestAlertsIngestionJobTest < GitHub::TestCase
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
      test "ingests pull request alerts" do
        ::Turboscan::ResultsClient.any_instance.expects(:pull_request_introduced_alerts)
          .returns(Twirp::ClientResp.new(
            data: ::Turboscan::Proto::PullRequestIntroducedAlertsResponse.new(
              alerts: [
                ::Turboscan::Proto::AlertInPullRequest.new(
                  alert_number: 1,
                  analysis_id: 2,
                  autofix_accepted: false,
                  created_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-23").to_i),
                  has_autofix: true,
                  ref_name_bytes: "refs/pull/1/merge",
                  resolution: :NO_RESOLUTION,
                  fixed: false,
                  rule_sarif_identifier: "rb/unsafe-deserialization",
                  severity: :CRITICAL,
                  tool: "CodeQL",
                  updated_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-31").to_i)
                ),
              ],
              total_count: 1
            )
          ))

        assert_nil CodeScanningPullRequestAlert.find_by(pull_request_id: @pull.id, alert_number: 1)

        CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: "woof")

        pr_alert = CodeScanningPullRequestAlert.find_by(pull_request_id: @pull.id, alert_number: 1)
        refute_nil pr_alert
        assert_equal 20240723, pr_alert&.date_id
        assert_equal @pull.repository_id, pr_alert&.repository_id
        assert_equal @pull.id, pr_alert&.pull_request_id
        assert_equal 1, pr_alert&.alert_number
        assert_equal 2, pr_alert&.analysis_id
        refute pr_alert&.autofix_accepted
        assert_equal Time.parse("2024-07-23"), pr_alert&.alert_created_at
        assert pr_alert&.has_autofix
        assert_equal "topic", pr_alert&.ref
        assert_nil pr_alert&.alert_resolution
        refute pr_alert&.alert_resolved
        assert_equal "rb/unsafe-deserialization", pr_alert&.rule_sarif_identifier
        assert_equal "CRITICAL", pr_alert&.alert_severity
        assert_equal "CodeQL", pr_alert&.tool
        assert_equal Time.parse("2024-07-31"), pr_alert&.alert_updated_at

        assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert_ingestion.processed"
        refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert_ingestion.stopped"
      end

      test "uses CodeScanningPullRequestAlert::UpdatePayload.from_pull_request_alert to compose payloads" do
        ::Turboscan::ResultsClient.any_instance.expects(:pull_request_introduced_alerts)
          .returns(Twirp::ClientResp.new(
            data: ::Turboscan::Proto::PullRequestIntroducedAlertsResponse.new(
              alerts: [
                ::Turboscan::Proto::AlertInPullRequest.new(
                  alert_number: 1,
                  analysis_id: 2,
                  autofix_accepted: false,
                  created_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-23").to_i),
                  has_autofix: true,
                  ref_name_bytes: "refs/pull/1/merge",
                  resolution: :NO_RESOLUTION,
                  fixed: false,
                  rule_sarif_identifier: "rb/unsafe-deserialization",
                  severity: :CRITICAL,
                  tool: "CodeQL",
                  updated_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-31").to_i)
                ),
              ],
              total_count: 1
            )
          ))

        now = Time.now
        CodeScanningPullRequestAlert::UpdatePayload.expects(:from_pull_request_alert).once.returns(
          CodeScanningPullRequestAlert::UpdatePayload.new(
            repository_id: @pull.repository_id,
            alert_number: 1,
            pull_request_id: @pull.id,
            analysis_id: 2,
            ref: "refs/pull/1/merge",
            tool: "CodeQL",
            rule_sarif_identifier: "rb/unsafe-deserialization",
            alert_created_at: Time.parse("2024-07-23"),
            alert_updated_at: Time.parse("2024-07-31"),
            alert_severity: "CRITICAL",
            alert_resolved: false,
            has_autofix: true,
            autofix_accepted: false
          )
        )
        CodeScanningPullRequestAlert::UpdatePayload.expects(:new).never

        CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: "woof")
      end

      test "does not update alert resolution state when updating existing records" do
        ::Turboscan::ResultsClient.any_instance.expects(:pull_request_introduced_alerts)
          .returns(Twirp::ClientResp.new(
            data: ::Turboscan::Proto::PullRequestIntroducedAlertsResponse.new(
              alerts: [
                ::Turboscan::Proto::AlertInPullRequest.new(
                  alert_number: 1,
                  analysis_id: 2,
                  autofix_accepted: false,
                  created_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-23").to_i),
                  has_autofix: true,
                  ref_name_bytes: "refs/pull/1/merge",
                  resolution: :NO_RESOLUTION,
                  fixed: false,
                  rule_sarif_identifier: "rb/unsafe-deserialization",
                  severity: :CRITICAL,
                  tool: "CodeQL",
                  updated_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-31").to_i)
                ),
              ],
              total_count: 1
            )
          ))

        CodeScanningPullRequestAlert
          .expects(:upsert)
          .with(anything, has_entry(update_except: %w[alert_resolved alert_resolution alert_resolved_at]))
          .once

        CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: "woof")
      end

      context "is reconciliation" do
        test "does not upsert if no deviation found" do
          ::Turboscan::ResultsClient.any_instance.expects(:pull_request_introduced_alerts)
            .returns(Twirp::ClientResp.new(
              data: ::Turboscan::Proto::PullRequestIntroducedAlertsResponse.new(
                alerts: [
                  ::Turboscan::Proto::AlertInPullRequest.new(
                    alert_number: 1,
                    analysis_id: 2,
                    autofix_accepted: false,
                    created_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-23").to_i),
                    has_autofix: true,
                    ref_name_bytes: "refs/pull/1/merge",
                    resolution: :NO_RESOLUTION,
                    fixed: false,
                    rule_sarif_identifier: "rb/unsafe-deserialization",
                    severity: :CRITICAL,
                    tool: "CodeQL",
                    updated_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-31").to_i)
                  ),
                ],
                total_count: 1
              )
            )).twice
          CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: "woof")
          existing_alert = CodeScanningPullRequestAlert.find_by(pull_request_id: @pull.id, alert_number: 1)

          assert_no_changes -> { existing_alert } do
            CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: Fanout::Types::Action::Reconcile.serialize)
          end

          refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert_ingestion.deviation"
        end

        test "resolves missing alert" do
          ::Turboscan::ResultsClient.any_instance.expects(:pull_request_introduced_alerts)
            .returns(Twirp::ClientResp.new(
              data: ::Turboscan::Proto::PullRequestIntroducedAlertsResponse.new(
                alerts: [
                  ::Turboscan::Proto::AlertInPullRequest.new(
                    alert_number: 1,
                    analysis_id: 2,
                    autofix_accepted: false,
                    created_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-23").to_i),
                    has_autofix: true,
                    ref_name_bytes: "refs/pull/1/merge",
                    resolution: :NO_RESOLUTION,
                    fixed: false,
                    rule_sarif_identifier: "rb/unsafe-deserialization",
                    severity: :CRITICAL,
                    tool: "CodeQL",
                    updated_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-31").to_i)
                  ),
                ],
                total_count: 1
              )
            )).once

          CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: Fanout::Types::Action::Reconcile.serialize)
          refute_nil CodeScanningPullRequestAlert.find_by(pull_request_id: @pull.id, alert_number: 1)

          assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert_ingestion.deviation", tags: ["deviation:missing_alert"]
        end

        test "reports orphaned alert" do
          ::Turboscan::ResultsClient.any_instance.expects(:pull_request_introduced_alerts)
            .returns(Twirp::ClientResp.new(
              data: ::Turboscan::Proto::PullRequestIntroducedAlertsResponse.new(
                alerts: [
                  ::Turboscan::Proto::AlertInPullRequest.new(
                    alert_number: 1,
                    analysis_id: 2,
                    autofix_accepted: false,
                    created_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-23").to_i),
                    has_autofix: true,
                    ref_name_bytes: "refs/pull/1/merge",
                    resolution: :NO_RESOLUTION,
                    fixed: false,
                    rule_sarif_identifier: "rb/unsafe-deserialization",
                    severity: :CRITICAL,
                    tool: "CodeQL",
                    updated_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-31").to_i)
                  ),
                ],
                total_count: 1
              )
            )).twice
          CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: "woof")
          extra_alert = create(:soa_code_scanning_pr_alert, repository_id: @repo.id, pull_request_id: @pull.id, alert_number: 2)

          CodeScanningPullRequestAlert.expects(:upsert).never
          CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: Fanout::Types::Action::Reconcile.serialize)
          refute_nil CodeScanningPullRequestAlert.find_by(id: extra_alert.id)

          assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert_ingestion.deviation", tags: ["deviation:orphaned_alert"]
        end

        test "resolves deviation of existing alert" do
          existing_alert = create(:soa_code_scanning_pr_alert, repository_id: @repo.id, pull_request_id: @pull.id)
          refute existing_alert.alert_resolved
          refute existing_alert.autofix_accepted

          ::Turboscan::ResultsClient.any_instance.expects(:pull_request_introduced_alerts)
            .returns(Twirp::ClientResp.new(
              data: ::Turboscan::Proto::PullRequestIntroducedAlertsResponse.new(
                alerts: [
                  ::Turboscan::Proto::AlertInPullRequest.new(
                    alert_number: existing_alert.alert_number,
                    analysis_id: existing_alert.analysis_id,
                    autofix_accepted: true,
                    created_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-07-23").to_i),
                    has_autofix: existing_alert.has_autofix,
                    ref_name_bytes: existing_alert.ref,
                    resolution: :NO_RESOLUTION,
                    fixed: true,
                    fixed_at: Google::Protobuf::Timestamp.new(seconds: Time.parse("2024-08-06").to_i),
                    rule_sarif_identifier: existing_alert.rule_sarif_identifier,
                    severity: :CRITICAL,
                    tool: existing_alert.tool,
                    updated_at: Google::Protobuf::Timestamp.new(seconds: 1.day.from_now.to_i)
                  ),
                ],
                total_count: 1
              )
            ))
          CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: Fanout::Types::Action::Reconcile.serialize)
          refute existing_alert.alert_resolved
          assert existing_alert.reload.autofix_accepted

          assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert_ingestion.deviation", tags: ["deviation:autofix_accepted"]
        end
      end
    end

    context "input validations" do
      test "stops if pull request not found" do
        CodeScanningPullRequestAlertsIngestionJob.any_instance.expects(:perform).never

        CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: 9999999, source_event: "woof")

        assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert_ingestion.stopped", tags: ["reason:pull_request_not_found"]
        refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert_ingestion.processed"
      end

      test "stops if repository deleted" do
        CodeScanningPullRequestAlertsIngestionJob.any_instance.expects(:perform).never
        @pull.repository.active = false
        @pull.repository.save!

        CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: "woof")

        assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert_ingestion.stopped", tags: ["reason:repository_not_found"]
        refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert_ingestion.processed"
      end

      test "validates repository's tenant scope" do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

        CodeScanningPullRequestAlertsIngestionJob.any_instance.expects(:perform).never

        CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: "woof")

        assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert_ingestion.stopped", tags: ["reason:ineligible_repo_owner"]
        refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert_ingestion.processed"
      end

      test "code scanning is required" do
        ::Repository.any_instance.stubs(:code_scanning_usable?).returns(false)

        CodeScanningPullRequestAlertsIngestionJob.any_instance.expects(:perform).never

        CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: "woof")

        assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert_ingestion.stopped", tags: ["reason:code_scanning_unavailable"]
        refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert_ingestion.processed"
      end

      test "code scanning enablement is required" do
        ::Repository.any_instance.stubs(:turboscan_considers_code_scanning_enabled?).returns(false)

        CodeScanningPullRequestAlertsIngestionJob.any_instance.expects(:perform).never

        CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: "woof")

        assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert_ingestion.stopped", tags: ["reason:code_scanning_disabled"]
        refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert_ingestion.processed"
      end

      test "pull request is required to based from default branch" do
        CodeScanningPullRequestAlertsIngestionJob.any_instance.expects(:perform).never

        CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull_non_default_branch.id, source_event: "woof")

        assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert_ingestion.stopped", tags: ["reason:not_default_branch_based"]
        refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert_ingestion.processed"
      end

      test "workspace pull request is not allowed" do
        CodeScanningPullRequestAlertsIngestionJob.any_instance.expects(:perform).never

        CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @workspace_pull.id, source_event: "woof")

        assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert_ingestion.stopped", tags: ["reason:advisory_workspace_pull_request"]
        refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert_ingestion.processed"
      end

      test "pull request is required to be merged" do
        CodeScanningPullRequestAlertsIngestionJob.any_instance.expects(:perform).never

        CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull_not_merged.id, source_event: "woof")

        assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert_ingestion.stopped", tags: ["reason:pull_request_not_merged"]
        refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert_ingestion.processed"
      end
    end

    context "resiliency" do
      test "it retries on standard conditions" do
        assert_retry_conditions(
          job: CodeScanningPullRequestAlertsIngestionJob,
          args: [pull_request_id: @pull.id, source_event: "woof"],
          using_kwargs: true
        )
      end

      test "it retries on pull_request_introduced_alerts API errors" do
        ::Turboscan::ResultsClient.any_instance.expects(:pull_request_introduced_alerts)
          .returns(Twirp::ClientResp.new(
            error: Twirp::Error.new(
              :invalid_argument,
              "let it fail!"
            )
          ))

        assert_enqueued_with(
          job: CodeScanningPullRequestAlertsIngestionJob,
          args: [pull_request_id: @pull.id, source_event: "woof"]
        ) do
          CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @pull.id, source_event: "woof")
        end
      end
    end

    context "hash lock" do
      test "does not allow concurrent jobs for the same pull request" do
        assert_enqueued_jobs 1, only: CodeScanningPullRequestAlertsIngestionJob do
          CodeScanningPullRequestAlertsIngestionJob.perform_later(pull_request_id: @pull.id, source_event: "woof")
          CodeScanningPullRequestAlertsIngestionJob.perform_later(pull_request_id: @pull.id, source_event: "wow")
        end
      end
    end

    context "on multi tenant enterprise" do
      test "sets the tenant context to the correct business" do
        on_multi_tenant_enterprise do
          ::Repositories::Public.expects(:resolve_tenant).with(id: @mt_repo.id).returns(@mt_business).once
          CodeScanningPullRequestAlertsIngestionJob.perform_now(pull_request_id: @mt_pull.id, source_event: "woof")
        end
      end
    end
  end
end
