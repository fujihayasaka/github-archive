# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityCenter
  class OverviewDashboardExportBatchedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper

    fixtures do
      @user = create(:user)
      @org = create(:organization, admin: @user)
      @user_session = create(:user_session, user: @user)

      @repo = create(:private_repository, owner: @org)
      team = create(:team, organization: @org)
      @repo.send(:grant, team, :admin)

      definition = create :custom_property_definition, :single_select, source: @org, property_name: "single-select", allowed_values: %w[value another nomatch]
      create :custom_property_value, target: @repo, definition: definition, value: "value"

      topic = create(:topic, name: "repo-topic")
      topic.repository_topics.create!(repository: @repo, state: :created, user: @user)

      query = Search::Queries::SecurityCenter::QueryParser.new("")
      repos_filterer = ::SecurityOverviewAnalytics::Dashboards::OrgReposFilterer.new(
        allowed_repo_ids_by_feature: nil,
        organization: @org,
        query:,
        user: @user,
        user_session: create(:user_session, user: @user)
      )

      @now = Time.now.freeze

      @metadata = create(:soa_repository, repository: @repo)
      @soa_date = create(:soa_date, date_value: @now)
      create(:soa_feature_status_revision, dependabot_alerts_enabled: true, secret_scanning_enabled: true, code_scanning_enabled: true, repository_metadata: metadata, date: @soa_date)
      create(:soa_dependabot_alert_revision, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)
      create(:soa_code_scanning_alert_revision, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 3)
      create(:soa_secret_scanning_alert_revision, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 2, alert_type: "ddd3b186-0925-4c5b-bf1a-1f0ca57ed867", alert_type_provider: "86f85cc1-8424-46bf-b196-46e7ffa7eb47")
    end

    setup do
      # Clear jobs and email cache
      reset_jobs
      ActionMailer::Base.deliveries.clear
    end

    context "batch job" do
      test "queues subsequent jobs for batching" do
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

        create(:soa_dependabot_alert_revision, alert_number: 2, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)
        create(:soa_dependabot_alert_revision, alert_number: 3, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day)

        requested_at = @now
        export_id = create_export_id(user: @user, org: @org, requested_at:)
        Export::JobStatus.create(id: export_id, query: "", requested_at:)

        OverviewDashboardExportBatchedJob.stub_const(:DEFAULT_BATCH_SIZE, 1) do
          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            queue_job(requested_at:, features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]])
          end
        end
      end

      test "enqueues a followup BatchedJob when multiple features" do
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

        requested_at = @now
        export_id = create_export_id(user: @user, org: @org, requested_at:)
        Export::JobStatus.create(id: export_id, query: "", requested_at:)

        assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            queue_job(requested_at:)
          end
        end
      end

      test "adjusts batch size if FF is enabled" do
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once

        GitHub.flipper[:security_center_overview_dashboard_export_batch_size_scale_factor].enable(@org)
        GitHub.flipper[:security_center_overview_dashboard_export_batch_size_scale_factor].enable_percentage_of_actors(2)

        requested_at = @now
        export_id = create_export_id(user: @user, org: @org, requested_at:)
        Export::JobStatus.create(id: export_id, query: "", requested_at:)

        perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
          job = queue_job(requested_at:, features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]])
          assert_equal 200, job.batch_size
        end
      end

      test "Logs telemetry when status is not found" do
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).never
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).never

        perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
          assert_raises(RuntimeError) do
            queue_job
          end
        end

        assert_dogstats_increment(1, "security_center.overview_dashboard_export_batched_job.job_status_not_found")
      end

      test "Emails users a link to their export results" do
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

        requested_at = @now
        export_id = create_export_id(user: @user, org: @org, requested_at:)
        Export::JobStatus.create(id: export_id, query: "", requested_at:)

        assert_equal 0, ActionMailer::Base.deliveries.size

        assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            queue_job(requested_at:)
          end
        end

        assert_equal 1, ActionMailer::Base.deliveries.size
        email = ActionMailer::Base.deliveries.first
        assert_includes email.to, @user.email
        assert_includes email.subject, "[GitHub] Your security overview CSV is ready"
      end

      test "Emails user if an error is encountered during the job" do
        requested_at = @now
        export_id = create_export_id(user: @user, org: @org, requested_at:)
        Export::JobStatus.create(id: export_id, query: "", requested_at:)

        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once.raises(StandardError)

        assert_equal 0, ActionMailer::Base.deliveries.size

        perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
          assert_raises(StandardError) do
            queue_job(requested_at:)
          end
        end

        assert_equal 1, ActionMailer::Base.deliveries.size
        email = ActionMailer::Base.deliveries.first
        assert_includes email.to, @user.email
        assert_includes email.subject, "[GitHub] Sorry, your security overview CSV couldn't be generated"
      end
    end

    context "JobStatus" do
      test "Marked as success when final job finishes" do
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

        requested_at = @now
        export_id = create_export_id(user: @user, org: @org, requested_at:)
        Export::JobStatus.create(id: export_id, query: "", requested_at:)

        assert Export::JobStatus.find(export_id)&.pending?

        assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            queue_job(requested_at:)
          end
        end

        assert Export::JobStatus.find(export_id)&.finished?
        assert Export::JobStatus.find(export_id)&.success?
      end

      test "Swallow and report mailing errors, and still mark job as success" do
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)
        SecurityCenterMailer.any_instance.expects(:csv_export_ready).raises(StandardError)

        requested_at = @now
        export_id = create_export_id(user: @user, org: @org, requested_at:)
        Export::JobStatus.create(id: export_id, query: "", requested_at:)

        assert Export::JobStatus.find(export_id)&.pending?

        perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
          assert_nothing_raised do
            queue_job(requested_at:)
          end
        end

        assert Export::JobStatus.find(export_id)&.finished?
        assert Export::JobStatus.find(export_id)&.success?

        assert_dogstats_increment(1, "security_center.export.error")
      end

      test "Marked as failed when job raises an error" do
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).never
        SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).never

        requested_at = @now
        export_id = create_export_id(user: @user, org: @org, requested_at:)
        Export::JobStatus.create(id: export_id, query: "", requested_at:)

        Export::BlobStorageService.expects(:get).raises(StandardError.new("Something went wrong"))

        assert Export::JobStatus.find(export_id)&.pending?

        perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
          assert_raises(StandardError) do
            queue_job(requested_at:)
          end
        end

        assert Export::JobStatus.find(export_id)&.finished?
        assert Export::JobStatus.find(export_id)&.error?
        assert_equal "We couldn't generate your report. Please try again later. If the problem persists, please contact support.", Export::JobStatus.find(export_id)&.error_message

        assert_equal 1, ActionMailer::Base.deliveries.size
        email = ActionMailer::Base.deliveries.first
        assert_includes email.to, @user.email
        assert_includes email.subject, "[GitHub] Sorry, your security overview CSV couldn't be generated"
      end
    end

    private

    sig do
      params(
        scope: Organization,
        user: User,
        query_string: String,
        requested_at: Time,
        features_to_process: T::Array[T::Array[String]],
        start_date: Date,
        end_date: Date,
        allowed_repo_ids_by_feature: T.nilable(T::Hash[String, T::Array[Integer]]),
      ).returns(OverviewDashboardExportBatchedJob)
    end
    def queue_job(
      scope: @org,
      user: @user,
      query_string: "",
      requested_at: @now,
      features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS], [::SecurityCenter::SecurityFeatures::SECRET_SCANNING], [::SecurityCenter::SecurityFeatures::CODE_SCANNING]],
      start_date: (@now - 7.days).to_date,
      end_date: @now.to_date,
      allowed_repo_ids_by_feature: nil
    )
      OverviewDashboardExportBatchedJob.perform_later(
        scope:,
        user:,
        query_string:,
        start_date:,
        end_date:,
        allowed_repo_ids_by_feature:,
        security_feature: features_to_process.pop,
        features_to_process: features_to_process,
        requested_at:,
        user_session: @user_session,
        is_first_feature: true,
        offset_item_id: 0
      ).tap do |job|
        fail "Expected job to be enqueued" unless job
      end
    end

    sig { params(user: User, org: Organization, query: String, requested_at: Time).returns(String) }
    def create_export_id(user:, org:, query: "", requested_at: @now)
      Export::TokenGenerator.create_token(user:, scope: org, query:, feature_type: "overview_dashboard", requested_at:, start_date: (@now - 7.days).to_date, end_date: @now.to_date)
    end
  end
end
