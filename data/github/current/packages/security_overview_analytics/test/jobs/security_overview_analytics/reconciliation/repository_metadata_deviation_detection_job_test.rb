# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  module Reconciliation
    class RepositoryMetadataDeviationDetectionJobTest < GitHub::TestCase
      include DogstatsTestHelpers
      include JobTestHelper

      fixtures do
        # Business
        if GitHub.enterprise?
          @biz = create(:global_business)
          @user = create(:user, business: @biz)
          @user2 = create(:user, business: @biz)
        else
          @biz = create(:business, :enterprise_managed)
          @user = create(:emu, business: @biz)
          @user2 = create(:emu, business: @biz)
        end
      end

      setup do
        @stats_tags = ["metric_type:repository_metadata"]
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(true)
        # Stub info logging, otherwise we'll have to separately assert "Session locked" in every test.
        GitHub.logger.stubs(:info).returns(true)
      end

      context "#perform with organization_id" do
        test "reports and queues remediation if deviation found in metadata record" do
          metadata = create(:security_overview_analytics_repository, name: "oops")

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:name]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: metadata.organization_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if metadata record is missing" do
          org = create(:business_plus_organization)
          repo = create(:repository, owner: org)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:missing_owner_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: repo.id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: org.id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if metadata record exists but has wrong organization_id" do
          wrong_org = create(:business_plus_organization)
          metadata = create(:security_overview_analytics_repository, organization: wrong_org, owner_id: wrong_org.id)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:missing_owner_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: metadata.repository.owner_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if metadata record exists with missing owner_id" do
          metadata = create(:security_overview_analytics_repository, owner_id: 0)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:owner_id]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: metadata.repository.owner_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if any orphaned metadata record exists within batch range" do
          metadata1 = create(:security_overview_analytics_repository)
          metadata2 = create(:security_overview_analytics_repository)
          metadata1.update(organization_id: metadata2.organization_id)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:orphaned_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata1.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: metadata1.organization_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if any orphaned metadata record exists beyond last batch" do
          metadata1 = create(:security_overview_analytics_repository)
          metadata2 = create(:security_overview_analytics_repository)
          metadata2.update(organization_id: metadata1.organization_id)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:orphaned_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata2.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: metadata1.organization_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if any orphaned metadata record exists when org has no repository" do
          org = create(:business_plus_organization)
          metadata = create(:security_overview_analytics_repository)
          metadata.update(organization_id: org.id)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:orphaned_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: org.id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "does not report deviation if metadata record up to date" do
          metadata = create(:security_overview_analytics_repository)

          GitHub.logger.expects(:info).with("Deviation found.", anything).never
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).never

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: metadata.organization_id, session_id: "hohoho")
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.deviation"
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end
      end

      context "#perform with org owner_id" do
        test "reports and queues remediation if deviation found in metadata record" do
          metadata = create(:security_overview_analytics_repository, name: "oops")

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:name]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: metadata.organization_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if metadata record is missing" do
          org = create(:business_plus_organization)
          repo = create(:repository, owner: org)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:missing_owner_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: repo.id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: org.id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if metadata record exists but has wrong organization_id and owner_id" do
          org = create(:business_plus_organization)
          # TODO: for orgs we are still querying by organization_id - remove organization_id when removing that querying
          metadata = create(:security_overview_analytics_repository, organization_id: org.id, owner_id: org.id)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:missing_owner_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: metadata.repository.owner_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if any orphaned metadata record exists within batch range" do
          metadata1 = create(:security_overview_analytics_repository)
          metadata2 = create(:security_overview_analytics_repository)
          # TODO: for orgs we are still querying by organization_id - remove organization_id when removing that querying
          metadata1.update(owner_id: metadata2.owner_id, organization_id: metadata2.owner_id)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:orphaned_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata1.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: metadata1.owner_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if any orphaned metadata record exists beyond last batch" do
          metadata1 = create(:security_overview_analytics_repository)
          metadata2 = create(:security_overview_analytics_repository)
          # TODO: for orgs we are still querying by organization_id - remove organization_id when removing that querying
          metadata2.update(owner_id: metadata1.owner_id, organization_id: metadata1.owner_id)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:orphaned_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata2.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: metadata1.owner_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if any orphaned metadata record exists when org has no repository" do
          org = create(:business_plus_organization)
          metadata = create(:security_overview_analytics_repository)
          # TODO: for orgs we are still querying by organization_id - remove organization_id when removing that querying
          metadata.update(owner_id: org.id, organization_id: org.id)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:orphaned_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: org.id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "does not report deviation if metadata record up to date" do
          metadata = create(:security_overview_analytics_repository)

          GitHub.logger.expects(:info).with("Deviation found.", anything).never
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).never

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: metadata.organization_id, session_id: "hohoho")
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.deviation"
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end
      end

      context "#perform with user owner_id" do
        test "reports and queues remediation if deviation found in metadata record" do
          repo = create(:repository, owner: @user)
          metadata = create(:security_overview_analytics_repository, name: "oops", repository: repo)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:name]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: metadata.owner_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if metadata record is missing" do
          repo = create(:repository, owner: @user)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:missing_owner_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: repo.id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: @user.id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if metadata record exists but has wrong user owner_id" do
          org = create(:business_plus_organization)
          repo = create(:repository, owner: @user)
          metadata = create(:security_overview_analytics_repository, repository: repo, owner_id: org.id)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:missing_owner_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: metadata.repository.owner_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if any orphaned metadata record exists within batch range" do
          repo = create(:repository, owner: @user)
          repo2 = create(:repository, owner: @user2)
          metadata1 = create(:security_overview_analytics_repository, repository: repo)
          metadata2 = create(:security_overview_analytics_repository, repository: repo2)
          metadata1.update(owner_id: metadata2.owner_id)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:orphaned_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata1.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: metadata1.owner_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if any orphaned metadata record exists beyond last batch" do
          repo = create(:repository, owner: @user)
          repo2 = create(:repository, owner: @user2)
          metadata1 = create(:security_overview_analytics_repository, repository: repo)
          metadata2 = create(:security_overview_analytics_repository, repository: repo2)
          metadata2.update(owner_id: metadata1.owner_id)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:orphaned_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata2.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: metadata1.owner_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if any orphaned metadata record exists when user has no repository" do
          repo = create(:repository, owner: @user)
          metadata = create(:security_overview_analytics_repository, repository: repo)
          metadata.update(owner_id: @user2.id)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:orphaned_repo_metadata]
            })
          ).once
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).once

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: @user2.id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "does not report deviation if metadata record up to date" do
          repo = create(:repository, owner: @user)
          metadata = create(:security_overview_analytics_repository, repository: repo)

          GitHub.logger.expects(:info).with("Deviation found.", anything).never
          RepositoryMetadataDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: metadata.repository_id)).never

          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: nil, owner_id: metadata.owner_id, session_id: "hohoho")
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.deviation"
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end
      end

      context "#around_enqueue" do
        test "raises ArgumentError if missing organization_id and owner_id" do
          assert_enqueued_jobs 0, only: RepositoryMetadataDeviationDetectionJob do
            assert_raises ArgumentError do
              RepositoryMetadataDeviationDetectionJob.perform_later(session_id: "woof")
            end
          end
        end
      end

      context "#around_perform with organization_id" do
        test "stops the perform if tenant out of scope" do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

          RepositoryMetadataDeviationDetectionJob.any_instance.expects(:next_batch).never
          RepositoryMetadataDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: org.id, session_id: "hohoho")
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:owner_not_in_scope"]
        end

        test "stops the perform if tenant not initialized" do
          Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(false)

          RepositoryMetadataDeviationDetectionJob.any_instance.expects(:next_batch).never
          RepositoryMetadataDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: org.id, session_id: "hohoho")
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:tenant_not_initialized"]
        end

        test "stops the perform if session has been reset" do
          org = create(:organization)
          session = Session.new(owner_id: org.id, type: "code_scanning_alert")
          session.lock!

          Timecop.travel(10.days.from_now) do
            timestamps = session.lock!
            session.reset!(last_session_started_at: timestamps[:last_session_started_at])

            assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
              RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: org.id, session_started_at: Time.now.utc)
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:session_reset"]
        end
      end

      context "#around_perform with owner_id" do
        test "stops the perform if tenant out of scope" do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

          RepositoryMetadataDeviationDetectionJob.any_instance.expects(:next_batch).never
          RepositoryMetadataDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(owner_id: org.id, session_id: "hohoho")
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:owner_not_in_scope"]
        end

        test "stops the perform if tenant not initialized" do
          Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::RepositoryMetadata).returns(false)

          RepositoryMetadataDeviationDetectionJob.any_instance.expects(:next_batch).never
          RepositoryMetadataDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
            RepositoryMetadataDeviationDetectionJob.perform_later(owner_id: org.id, session_id: "hohoho")
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:tenant_not_initialized"]
        end

        test "stops the perform if session has been reset" do
          org = create(:organization)
          session = Session.new(owner_id: org.id, type: "code_scanning_alert")
          session.lock!

          Timecop.travel(10.days.from_now) do
            timestamps = session.lock!
            session.reset!(last_session_started_at: timestamps[:last_session_started_at])

            assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
              RepositoryMetadataDeviationDetectionJob.perform_later(owner_id: org.id, session_started_at: Time.now.utc)
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:session_reset"]
        end
      end

      context "batched job" do
        test "queues subsequent jobs for batching" do
          org = create(:organization).tap do |o|
            9.times do
              create(:repository, owner: o)
            end
          end

          RepositoryMetadataDeviationDetectionJob.stub_const(:BATCH_SIZE, 5) do
            assert_performed_jobs 2, only: RepositoryMetadataDeviationDetectionJob do
              perform_enqueued_jobs only: RepositoryMetadataDeviationDetectionJob do
                RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: org.id, session_id: "hohoho")
              end
            end
          end

          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end
      end

      context "resiliency" do
        test "retries on standard conditions" do
          org = create(:organization)
          Session.any_instance.stubs(:locked?).returns(true)
          assert_retry_conditions(job: RepositoryMetadataDeviationDetectionJob, args: [{ organization_id: org.id, session_started_at: Time.now.utc }])
        end
      end

      context "session lock" do
        test "does not allow consecutive jobs if session is still locked" do
          org = create(:organization)
          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "repository_metadata"
            })
          ).once
          Session.any_instance.expects(:reset!).never

          Timecop.freeze do
            assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
              perform_enqueued_jobs only: RepositoryMetadataDeviationDetectionJob do
                RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: org.id)
              end
            end

            assert Session.new(owner_id: org.id, type: "repository_metadata").locked?
          end

          Timecop.travel(1.day.from_now) do
            assert_enqueued_jobs 0, only: RepositoryMetadataDeviationDetectionJob do
              RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: org.id)
            end

            assert Session.new(owner_id: org.id, type: "repository_metadata").locked?
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:session_locked"]
        end

        test "reset session lock if job fails tenant validation" do
          org = create(:organization)
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "repository_metadata"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "repository_metadata"
            })
          ).once

          Timecop.freeze do
            assert_performed_jobs 1, only: RepositoryMetadataDeviationDetectionJob do
              perform_enqueued_jobs only: RepositoryMetadataDeviationDetectionJob do
                RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: org.id)
              end
            end

            refute Session.new(owner_id: org.id, type: "repository_metadata").locked?
          end
        end

        test "reset session lock when retry attempts are exhausted" do
          org = create(:organization)
          RepositoryMetadataDeviationDetectionJob.any_instance.stubs(:perform).raises(ActiveRecord::ConnectionFailed)

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "repository_metadata"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "repository_metadata"
            })
          ).once

          assert_performed_jobs(5, only: [RepositoryMetadataDeviationDetectionJob]) do
            perform_enqueued_jobs only: RepositoryMetadataDeviationDetectionJob do
              RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: org.id)
            end
          end

          refute Session.new(owner_id: org.id, type: "repository_metadata").locked?
        end

        test "reset session lock on non-retryable exceptions" do
          org = create(:organization)
          RepositoryMetadataDeviationDetectionJob.any_instance.stubs(:perform).raises(ArgumentError.new("some error"))

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "repository_metadata"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "repository_metadata"
            })
          ).once

          perform_enqueued_jobs only: RepositoryMetadataDeviationDetectionJob do
            assert_raises ArgumentError do
              RepositoryMetadataDeviationDetectionJob.perform_later(organization_id: org.id)
            end
          end

          refute Session.new(owner_id: org.id, type: "repository_metadata").locked?
        end
      end
    end
  end
end
