# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityCenter
  class OverviewDashboardExportBatchedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper
    include SecurityCenter::TestFixtures

    fixtures do
      create_business_level_fixtures

      @user_session = create(:user_session, user: @orgs_owner)

      @repo = create(:private_repository, owner: @org)
      @team = create(:team, organization: @org)
      @repo.send(:grant, @team, :admin)

      @org2_repo = create(:private_repository, owner: @org2)
      team = create(:team, organization: @org2)
      @org2_repo.send(:grant, team, :admin)

      definition = create :custom_property_definition, :single_select, source: @org, property_name: "single-select", allowed_values: %w[value another nomatch]
      create :custom_property_value, target: @repo, definition: definition, value: "value"

      definition2 = create :custom_property_definition, :single_select, source: @org2, property_name: "single-select-2", allowed_values: %w[value2 another2 nomatch2]
      create :custom_property_value, target: @org2_repo, definition: definition2, value: "value2"

      topic = create(:topic, name: "repo-topic")
      topic.repository_topics.create!(repository: @repo, state: :created, user: @orgs_owner)
      topic.repository_topics.create!(repository: @org2_repo, state: :created, user: @orgs_owner)

      @now = Time.now.freeze

      @metadata = create(:soa_repository, repository: @repo)
      @soa_date = create(:soa_date, date_value: @now)
      create(:soa_feature_status_revision, dependabot_alerts_enabled: true, secret_scanning_enabled: true, code_scanning_enabled: true, repository_metadata: @metadata, date: @soa_date)
      create(:soa_dependabot_alert_revision, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)
      create(:soa_code_scanning_alert_revision, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 3)
      create(:soa_secret_scanning_alert_revision, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 2, alert_type: "ddd3b186-0925-4c5b-bf1a-1f0ca57ed867", alert_type_provider: "86f85cc1-8424-46bf-b196-46e7ffa7eb47")

      @metadata2 = create(:soa_repository, repository: @org2_repo)
      create(:soa_feature_status_revision, dependabot_alerts_enabled: true, secret_scanning_enabled: true, code_scanning_enabled: true, repository_metadata: @metadata2, date: @soa_date)
      create(:soa_dependabot_alert_revision, repository_metadata: @metadata2, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)
      create(:soa_code_scanning_alert_revision, repository_metadata: @metadata2, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 3)
      create(:soa_secret_scanning_alert_revision, repository_metadata: @metadata2, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 2, alert_type: "ddd3b186-0925-4c5b-bf1a-1f0ca57ed868", alert_type_provider: "86f85cc1-8424-46bf-b196-46e7ffa7eb48")
    end

    setup do
      # Clear jobs and email cache
      reset_jobs
      ActionMailer::Base.deliveries.clear
    end

    context "organization" do
      context "batch job" do
        test "it validates required parameters" do
          features_to_process = [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS], [::SecurityCenter::SecurityFeatures::SECRET_SCANNING], ["codeql"]]
          kwargs = {
            scope: @org,
            user: @orgs_owner,
            user_session: @orgs_owner_user_session,
            security_feature: features_to_process.pop,
            features_to_process: features_to_process,
            export_id: "foo"
          }

          assert_raises(ArgumentError) { OverviewDashboardExportBatchedJob.perform_later(**kwargs, scope: nil) }
          assert_raises(ArgumentError) { OverviewDashboardExportBatchedJob.perform_later(**kwargs, user: nil) }
          assert_raises(ArgumentError) { OverviewDashboardExportBatchedJob.perform_later(**kwargs, user_session: nil) }
          assert_raises(ArgumentError) { OverviewDashboardExportBatchedJob.perform_later(**kwargs, security_feature: nil) }
          assert_raises(ArgumentError) { OverviewDashboardExportBatchedJob.perform_later(**kwargs, features_to_process: nil) }
          assert_raises(ArgumentError) { OverviewDashboardExportBatchedJob.perform_later(**kwargs, export_id: nil) }
        end

        test "queues subsequent jobs for batching" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

          create(:soa_dependabot_alert_revision, alert_number: 2, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)
          create(:soa_dependabot_alert_revision, alert_number: 3, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day)

          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          OverviewDashboardExportBatchedJob.stub_const(:DEFAULT_BATCH_SIZE, 1) do
            perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
              queue_job(export_id:, features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]])
            end
          end
        end

        test "enqueues a followup BatchedJob when multiple features" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
            perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
              queue_job(export_id:)
            end
          end
        end

        test "adjusts batch size if FF is enabled" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once

          GitHub.flipper[:security_center_overview_dashboard_export_batch_size_scale_factor].enable(@org)
          GitHub.flipper[:security_center_overview_dashboard_export_batch_size_scale_factor].enable_percentage_of_actors(2)

          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            job = queue_job(export_id:, features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]])
            assert_equal 200, job.batch_size
          end
        end

        test "Content stored in Azure is correct" do
          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          alert_created_at = @now - 2.days
          alert_updated_at = @now - 1.day
          alert_resolved_at = @now

          create(:soa_dependabot_alert_revision, alert_number: 2, repository_metadata: @metadata, date: @soa_date, alert_created_at:, alert_updated_at:, alert_resolved_at:, alert_resolution: 37)
          create(:soa_dependabot_alert_revision, alert_number: 3, repository_metadata: @metadata, date: @soa_date, alert_created_at:, alert_updated_at:)

          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once.with(
            export_id,
            "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 20 values),Repository Visibility,Repository Topics,Repository Archived,Custom Property: single-select\n" \
              "#{@org.display_login}/#{@repo.name},#{@repo.id},dependabot,1,low,#{alert_created_at},#{alert_updated_at},#{alert_resolved_at},,auto_dismissed,,,,,GHSA-1234-5678-90AB,npm,react,RUNTIME,,,\"[\"\"#{@team.name}\"\"]\",private,\"[\"\"repo-topic\"\"]\",false,value\n" \
              "#{@org.display_login}/#{@repo.name},#{@repo.id},dependabot,2,low,#{alert_created_at},#{alert_updated_at},#{alert_resolved_at},,auto_dismissed,,,,,GHSA-1234-5678-90AB,npm,react,RUNTIME,,,\"[\"\"#{@team.name}\"\"]\",private,\"[\"\"repo-topic\"\"]\",false,value\n" \
              "#{@org.display_login}/#{@repo.name},#{@repo.id},dependabot,3,low,#{alert_created_at},#{alert_updated_at},,,,,,,,GHSA-1234-5678-90AB,npm,react,RUNTIME,,,\"[\"\"#{@team.name}\"\"]\",private,\"[\"\"repo-topic\"\"]\",false,value\n",
            "overview_dashboard",
          )

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            queue_job(export_id:, features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]])
          end
        end

        test "Logs telemetry and raises error when status is not found" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).never
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).never

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            assert_raises(StandardError) do
              queue_job(export_id: "foo")
            end
          end

          assert_dogstats_increment(1, "security_center.overview_dashboard_export_batched_job.job_status_not_found")
        end

        test "Emails users a link to their export results" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          assert_equal 0, ActionMailer::Base.deliveries.size

          assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
            perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
              queue_job(export_id:)
            end
          end

          assert_equal 1, ActionMailer::Base.deliveries.size
          email = ActionMailer::Base.deliveries.first
          assert_includes email.to, @orgs_owner.email
          assert_includes email.subject, "[GitHub] Your security overview CSV is ready"
        end

        test "Emails user if an error is encountered during the job" do
          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once.raises(StandardError)

          assert_equal 0, ActionMailer::Base.deliveries.size

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            assert_raises(StandardError) do
              queue_job(export_id:)
            end
          end

          assert_equal 1, ActionMailer::Base.deliveries.size
          email = ActionMailer::Base.deliveries.first
          assert_includes email.to, @orgs_owner.email
          assert_includes email.subject, "[GitHub] Sorry, your security overview CSV couldn't be generated"
        end

        test "it applies tenant filtering" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once

          org1 = create(:organization)
          org1.add_admin(@orgs_owner)
          org2 = create(:organization)
          org2.add_admin(@orgs_owner)

          # Create the repository under org2
          repository = create(:private_repository, owner: org2)

          # Create our version of repository with org1 - we're out of date
          repository_metadata = create(:soa_repository, repository:, organization: org1)

          create(:soa_feature_status_revision, dependabot_alerts_enabled: true, secret_scanning_enabled: true, code_scanning_enabled: true, repository_metadata:, date: @soa_date)
          create(:soa_dependabot_alert_revision, repository_metadata:, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)
          create(:soa_code_scanning_alert_revision, repository_metadata:, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 3)
          create(:soa_secret_scanning_alert_revision, repository_metadata:, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 2, alert_type: "ddd3b186-0925-4c5b-bf1a-1f0ca57ed867", alert_type_provider: "86f85cc1-8424-46bf-b196-46e7ffa7eb47")

          export_id = create_export_id(user: @orgs_owner, scope: org1)
          create_job_status(id: export_id, scope: org1)

          # check that we only try to store the CSV headers (we don't include the out-of-scope repo)
          csv_headers_only = "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 20 values),Repository Visibility,Repository Topics,Repository Archived\n"
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store)
            .with(export_id, csv_headers_only, "overview_dashboard")
            .once # even though we run 3 jobs, we only upload to Azure once (the headers)

          assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
            perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
              queue_job(export_id:, scope: org1)
            end
          end

          assert_dogstats_increment(3, "security_center.access_violation", tags: [
            "feature:overview-dashboard-export",
            "scope:organization",
            "violation:repository_out_of_scope"
          ])
        end

        test "it forces next batch if tenant filtering removes all records in the batch" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once

          org1 = create(:organization)
          org1.add_admin(@orgs_owner)
          org2 = create(:organization)
          org2.add_admin(@orgs_owner)

          # Create the repository under org2
          repository = create(:private_repository, owner: org2)

          # Create our version of repository with org1 - we're out of date
          repository_metadata = create(:soa_repository, repository:, organization: org1)

          create(:soa_feature_status_revision, dependabot_alerts_enabled: true, secret_scanning_enabled: true, code_scanning_enabled: true, repository_metadata:, date: @soa_date)
          create(:soa_dependabot_alert_revision, repository_metadata:, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)

          export_id = create_export_id(user: @orgs_owner, scope: org1)
          create_job_status(id: export_id, scope: org1)

          # check that we only try to store the CSV headers (we don't include the out-of-scope repo)
          csv_headers_only = "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 20 values),Repository Visibility,Repository Topics,Repository Archived\n"
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store)
            .with(export_id, csv_headers_only, "overview_dashboard")
            .once # even though we run 2 jobs, we only upload to Azure once (the headers)

          OverviewDashboardExportBatchedJob.stub_const(:DEFAULT_BATCH_SIZE, 1) do
            assert_performed_jobs 2, only: OverviewDashboardExportBatchedJob do
              perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
                queue_job(export_id:, scope: org1, features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]])
              end
            end
          end

          assert_dogstats_increment(1, "security_center.access_violation", tags: [
            "feature:overview-dashboard-export",
            "scope:organization",
            "violation:repository_out_of_scope"
          ])
        end
      end

      context "JobStatus" do
        test "Marked as success when final job finishes" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          assert Export::JobStatus.find(export_id)&.pending?

          assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
            perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
              queue_job(export_id:)
            end
          end

          assert Export::JobStatus.find(export_id)&.finished?
          assert Export::JobStatus.find(export_id)&.success?
        end

        test "Update ttl after enqueue" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

          Timecop.freeze do
            export_id = create_export_id(user: @orgs_owner, scope: @org)
            create_job_status(id: export_id, scope: @org)
            assert_equal 1.minute.to_i, ::SecurityCenter::Export::JobStatus.find(export_id)&.ttl

            assert Export::JobStatus.find(export_id)&.pending?

            assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
              perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
                queue_job(export_id:)
              end
            end

            assert_equal 10.minutes, ::SecurityCenter::Export::JobStatus.find(export_id)&.ttl
          end
        end

        test "Swallow and report mailing errors, and still mark job as success" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)
          SecurityCenterMailer.any_instance.expects(:csv_export_ready).raises(StandardError)

          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          assert Export::JobStatus.find(export_id)&.pending?

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            assert_nothing_raised do
              queue_job(export_id:)
            end
          end

          assert Export::JobStatus.find(export_id)&.finished?
          assert Export::JobStatus.find(export_id)&.success?

          assert_dogstats_increment(1, "security_center.export.error")
        end

        test "Marked as failed when job raises an error" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).never
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).never

          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          Export::BlobStorageService.expects(:get).raises(StandardError.new("Something went wrong"))

          assert Export::JobStatus.find(export_id)&.pending?

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            assert_raises(StandardError) do
              queue_job(export_id:)
            end
          end

          assert Export::JobStatus.find(export_id)&.finished?
          assert Export::JobStatus.find(export_id)&.error?

          assert_equal 1, ActionMailer::Base.deliveries.size
          email = ActionMailer::Base.deliveries.first
          assert_includes email.to, @orgs_owner.email
          assert_includes email.subject, "[GitHub] Sorry, your security overview CSV couldn't be generated"
        end
      end

      context "Query validity" do
        test "specifies table names when querying by item_offset_id" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once

          create(:soa_secret_scanning_alert_revision, alert_number: 2, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)
          create(:soa_secret_scanning_alert_revision, alert_number: 3, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day)

          query = "secret-scanning.validity:active"
          export_id = create_export_id(user: @orgs_owner, scope: @org, query:)
          create_job_status(id: export_id, scope: @org, query:)

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            queue_job(export_id:, features_to_process: [[::SecurityCenter::SecurityFeatures::SECRET_SCANNING]])
          end
        end
      end
    end

    context "business" do
      context "batch job" do
        test "it validates required parameters" do
          features_to_process = [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS], [::SecurityCenter::SecurityFeatures::SECRET_SCANNING], ["codeql"]]
          kwargs = {
            scope: @business,
            user: @orgs_owner,
            user_session: nil, # optional
            authorized_orgs: [:code_scanning, :dependabot_alerts, :secret_scanning].product([[@business.organizations.to_a]]).to_h,
            authorized_orgs_by_action: [:read_code_scanning, :view_dependabot_alerts, :view_secret_scanning_alerts].product([[@business.organizations.to_a]]).to_h,
            security_feature: features_to_process.pop,
            features_to_process: features_to_process,
            export_id: "foo"
          }

          assert_raises(ArgumentError) { OverviewDashboardExportBatchedJob.perform_later(**kwargs, scope: nil) }
          assert_raises(ArgumentError) { OverviewDashboardExportBatchedJob.perform_later(**kwargs, user: nil) }
          assert_raises(ArgumentError) { OverviewDashboardExportBatchedJob.perform_later(**kwargs, security_feature: nil) }
          assert_raises(ArgumentError) { OverviewDashboardExportBatchedJob.perform_later(**kwargs, features_to_process: nil) }
          assert_raises(ArgumentError) { OverviewDashboardExportBatchedJob.perform_later(**kwargs, export_id: nil) }
          assert_raises(ArgumentError) { OverviewDashboardExportBatchedJob.perform_later(**kwargs, authorized_orgs: nil, authorized_orgs_by_action: nil) }
        end

        test "queues subsequent jobs for batching" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(4)

          create(:soa_dependabot_alert_revision, alert_number: 2, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)
          create(:soa_dependabot_alert_revision, alert_number: 3, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day)

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          OverviewDashboardExportBatchedJob.stub_const(:DEFAULT_BATCH_SIZE, 1) do
            perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
              queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a, features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]])
            end
          end
        end

        test "enqueues a followup BatchedJob when multiple features" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
            perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
              queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
            end
          end
        end

        test "Works when user-owned repos" do
          on_multi_tenant_enterprise

          SecurityProduct::Permissions::BusinessAuthz.any_instance.stubs(:can_view_user_owned_repository_alerts?).returns(true)
          ::AdvancedSecurity::Features::Business::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

          emu = create :emu, :owner
          emu_business = emu.enterprise_managed_business
          emu_org = create :organization, business: emu_business, admin: emu

          emu_org_repo = create(:private_repository, owner: emu_org)
          team = create(:team, organization: emu_org)
          emu_org_repo.send(:grant, team, :admin)

          org_repo = create(:repository, owner: emu_org)
          org_page = create(:page, repository: org_repo)

          emu_repo = create(:repository, owner: emu, force_user_owned: true)

          metadata = create(:soa_repository, repository: emu_repo)
          create(:soa_feature_status_revision, dependabot_alerts_enabled: true, secret_scanning_enabled: true, code_scanning_enabled: true, repository_metadata: metadata, date: @soa_date)
          create(:soa_dependabot_alert_revision, alert_number: 1, repository_metadata: metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)
          metadata = create(:soa_repository, repository: emu_org_repo)
          create(:soa_feature_status_revision, dependabot_alerts_enabled: true, secret_scanning_enabled: true, code_scanning_enabled: true, repository_metadata: metadata, date: @soa_date)
          create(:soa_dependabot_alert_revision, alert_number: 1, repository_metadata: metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day)

          export_id = create_export_id(user: emu, scope: emu_business)
          create_job_status(id: export_id, scope: emu_business)

          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once

          csv = "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 20 values),Repository Visibility,Repository Topics,Repository Archived\n" \
                "#{emu_repo.name_with_display_owner},#{emu_repo.id},dependabot,1,low,#{@now - 2.days},#{@now - 1.day},#{@now},,auto_dismissed,,,,,GHSA-1234-5678-90AB,npm,react,RUNTIME,,,,public,,false\n" \
                "#{emu_org_repo.name_with_display_owner},#{emu_org_repo.id},dependabot,1,low,#{@now - 2.days},#{@now - 1.day},,,,,,,,GHSA-1234-5678-90AB,npm,react,RUNTIME,,,\"[\"\"#{team.name}\"\"]\",private,,false\n"
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once.with(export_id, csv, "overview_dashboard")

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            queue_job(export_id:, user: emu, scope: emu_business, authorized_orgs: emu_business.organizations.to_a, features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]])
          end
        end

        test "Filters to authorized orgs" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once

          org3 = create(:business_plus_organization, business: @business)
          org3.add_admin(@orgs_owner)

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          # check that we only try to store the CSV headers (we don't include the out-of-scope repo)
          csv_headers_only = "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 20 values),Repository Visibility,Repository Topics,Repository Archived\n"
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store)
            .with(export_id, csv_headers_only, "overview_dashboard")
            .once # even though we run 3 jobs, we only upload to Azure once (the headers)

          assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
            perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
              queue_job(export_id:, scope: @business, authorized_orgs: [org3])
            end
          end
        end

        test "Content stored in Azure is correct" do
          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once

          alert_created_at = @now - 2.days
          alert_updated_at = @now - 1.day
          alert_resolved_at = @now
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once.with(
            export_id,
            "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 20 values),Repository Visibility,Repository Topics,Repository Archived\n" \
              "#{@org.display_login}/#{@repo.name},#{@repo.id},dependabot,1,low,#{alert_created_at},#{alert_updated_at},#{alert_resolved_at},,auto_dismissed,,,,,GHSA-1234-5678-90AB,npm,react,RUNTIME,,,\"[\"\"#{@team.name}\"\"]\",private,\"[\"\"repo-topic\"\"]\",false\n",
            "overview_dashboard",
          )

          authorized_orgs = {
            code_scanning: [],
            dependabot_alerts: [@org],
            secret_scanning: [],
          }

          authorized_orgs_by_action = {
            read_code_scanning: [],
            view_dependabot_alerts: [@org],
            view_secret_scanning_alerts: [],
          }

          features_to_process = [[::SecurityCenter::SecurityFeatures::SECRET_SCANNING], ["codeql"], [::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]]
          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            OverviewDashboardExportBatchedJob.perform_later(
              scope: @business,
              user: @orgs_owner,
              export_id:,
              security_feature: features_to_process.pop,
              features_to_process:,
              is_first_feature: true,
              user_session: @user_session,
              authorized_orgs:,
              authorized_orgs_by_action:,
              offset_item_id: 0,
            )
          end
        end

        test "adjusts batch size if FF is enabled" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once

          GitHub.flipper[:security_center_overview_dashboard_export_batch_size_scale_factor].enable(@business)
          GitHub.flipper[:security_center_overview_dashboard_export_batch_size_scale_factor].enable_percentage_of_actors(2)

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            job = queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a, features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]])
            assert_equal 200, job.batch_size
          end
        end

        test "Logs telemetry and raises error when status is not found" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).never
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).never

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            assert_raises(StandardError) do
              queue_job(export_id: "foo", scope: @business, authorized_orgs: @business.organizations.to_a)
            end
          end

          assert_dogstats_increment(1, "security_center.overview_dashboard_export_batched_job.job_status_not_found")
        end

        test "Emails users a link to their export results" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          assert_equal 0, ActionMailer::Base.deliveries.size

          assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
            perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
              queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
            end
          end

          assert_equal 1, ActionMailer::Base.deliveries.size
          email = ActionMailer::Base.deliveries.first
          assert_includes email.to, @orgs_owner.email
          assert_includes email.subject, "[GitHub] Your security overview CSV is ready"
        end

        test "Emails user if an error is encountered during the job" do
          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once.raises(StandardError)

          assert_equal 0, ActionMailer::Base.deliveries.size

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            assert_raises(StandardError) do
              queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
            end
          end

          assert_equal 1, ActionMailer::Base.deliveries.size
          email = ActionMailer::Base.deliveries.first
          assert_includes email.to, @orgs_owner.email
          assert_includes email.subject, "[GitHub] Sorry, your security overview CSV couldn't be generated"
        end

        test "it applies tenant filtering", skip_enterprise: true do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once

          user = create(:user)
          biz1 = create(:global_business)
          biz1.add_owner(user, actor: nil)
          org1 = create(:business_plus_organization, business: biz1)
          org1.add_admin(@orgs_owner)
          biz2 = create(:business)
          biz2.add_owner(user, actor: nil)
          org2 = create(:business_plus_organization, business: biz2)
          org2.add_admin(@orgs_owner)

          # Create the repository under biz2/org2
          repository = create(:private_repository, owner: org2)

          # Create our version of repository with biz1/org1 - we're out of date
          repository_metadata = create(:soa_repository, repository:, owner_id: org1.id, business_id: biz1.id)

          create(:soa_feature_status_revision, dependabot_alerts_enabled: true, secret_scanning_enabled: true, code_scanning_enabled: true, repository_metadata:, date: @soa_date)
          create(:soa_dependabot_alert_revision, repository_metadata:, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)
          create(:soa_code_scanning_alert_revision, repository_metadata:, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 3)
          create(:soa_secret_scanning_alert_revision, repository_metadata:, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 2, alert_type: "ddd3b186-0925-4c5b-bf1a-1f0ca57ed867", alert_type_provider: "86f85cc1-8424-46bf-b196-46e7ffa7eb47")

          export_id = create_export_id(user: @orgs_owner, scope: biz1)
          create_job_status(id: export_id, scope: biz1)

          # check that we only try to store the CSV headers (we don't include the out-of-scope repo)
          csv_headers_only = "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 20 values),Repository Visibility,Repository Topics,Repository Archived\n"
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store)
            .with(export_id, csv_headers_only, "overview_dashboard")
            .once # even though we run 3 jobs, we only upload to Azure once (the headers)

          assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
            perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
              queue_job(export_id:, scope: biz1, authorized_orgs: [org1])
            end
          end

          assert_dogstats_increment(3, "security_center.access_violation", tags: [
            "feature:overview-dashboard-export",
            "scope:business",
            "violation:repository_out_of_scope"
          ])
        end

        test "it forces next batch if tenant filtering removes all records in the batch", skip_enterprise: true do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once

          user = create(:user)
          biz1 = create(:global_business)
          biz1.add_owner(user, actor: nil)
          org1 = create(:business_plus_organization, business: biz1)
          org1.add_admin(@orgs_owner)
          biz2 = create(:business)
          biz2.add_owner(user, actor: nil)
          org2 = create(:business_plus_organization, business: biz2)
          org2.add_admin(@orgs_owner)

          # Create the repository under biz2/org2
          repository = create(:private_repository, owner: org2)

          # Create our version of repository with biz1/org1 - we're out of date
          repository_metadata = create(:soa_repository, repository:, owner_id: org1.id, business_id: biz1.id)

          create(:soa_feature_status_revision, dependabot_alerts_enabled: true, secret_scanning_enabled: true, code_scanning_enabled: true, repository_metadata:, date: @soa_date)
          create(:soa_dependabot_alert_revision, repository_metadata:, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)

          export_id = create_export_id(user: @orgs_owner, scope: biz1)
          create_job_status(id: export_id, scope: biz1)

          # check that we only try to store the CSV headers (we don't include the out-of-scope repo)
          csv_headers_only = "Repository,Repository ID,Tool,Alert Number,Severity,Created At,Updated At,Resolved At,Reopened At,Resolved Reason,Secret Bypassed,Secret Type,Secret Provider,Secret Validity,GHSA ID,Ecosystem,Package,Dependency Scope,CodeQL Rule,Third Party Tool Rule,Teams (truncated at 20 values),Repository Visibility,Repository Topics,Repository Archived\n"
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store)
            .with(export_id, csv_headers_only, "overview_dashboard")
            .once # even though we run 2 jobs, we only upload to Azure once (the headers)

          OverviewDashboardExportBatchedJob.stub_const(:DEFAULT_BATCH_SIZE, 1) do
            assert_performed_jobs 2, only: OverviewDashboardExportBatchedJob do
              perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
                queue_job(export_id:, scope: biz1, authorized_orgs: [org1], features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]])
              end
            end
          end

          assert_dogstats_increment(1, "security_center.access_violation", tags: [
            "feature:overview-dashboard-export",
            "scope:business",
            "violation:repository_out_of_scope"
          ])
        end
      end

      context "JobStatus" do
        test "Marked as success when final job finishes" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          assert Export::JobStatus.find(export_id)&.pending?

          assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
            perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
              queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
            end
          end

          assert Export::JobStatus.find(export_id)&.finished?
          assert Export::JobStatus.find(export_id)&.success?
        end

        test "Update ttl after enqueue" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

          Timecop.freeze do
            export_id = create_export_id(user: @orgs_owner, scope: @business)
            create_job_status(id: export_id, scope: @business)
            assert_equal 1.minute.to_i, ::SecurityCenter::Export::JobStatus.find(export_id)&.ttl

            assert Export::JobStatus.find(export_id)&.pending?

            assert_performed_jobs 3, only: OverviewDashboardExportBatchedJob do
              perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
                queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
              end
            end

            assert_equal 10.minutes, ::SecurityCenter::Export::JobStatus.find(export_id)&.ttl
          end
        end

        test "Swallow and report mailing errors, and still mark job as success" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)
          SecurityCenterMailer.any_instance.expects(:csv_export_ready).raises(StandardError)

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          assert Export::JobStatus.find(export_id)&.pending?

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            assert_nothing_raised do
              queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
            end
          end

          assert Export::JobStatus.find(export_id)&.finished?
          assert Export::JobStatus.find(export_id)&.success?

          assert_dogstats_increment(1, "security_center.export.error")
        end

        test "Marked as failed when job raises an error" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).never
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).never

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          Export::BlobStorageService.expects(:get).raises(StandardError.new("Something went wrong"))

          assert Export::JobStatus.find(export_id)&.pending?

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            assert_raises(StandardError) do
              queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
            end
          end

          assert Export::JobStatus.find(export_id)&.finished?
          assert Export::JobStatus.find(export_id)&.error?

          assert_equal 1, ActionMailer::Base.deliveries.size
          email = ActionMailer::Base.deliveries.first
          assert_includes email.to, @orgs_owner.email
          assert_includes email.subject, "[GitHub] Sorry, your security overview CSV couldn't be generated"
        end
      end

      context "Query validity" do
        test "specifies table names when querying by item_offset_id" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once

          create(:soa_secret_scanning_alert_revision, alert_number: 2, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day, alert_resolved_at: @now, alert_resolution: 37)
          create(:soa_secret_scanning_alert_revision, alert_number: 3, repository_metadata: @metadata, date: @soa_date, alert_created_at: @now - 2.days, alert_updated_at: @now - 1.day)

          query = "secret-scanning.validity:active"
          export_id = create_export_id(user: @orgs_owner, scope: @business, query:)
          create_job_status(id: export_id, scope: @business, query:)

          perform_enqueued_jobs(only: [OverviewDashboardExportBatchedJob]) do
            queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a, features_to_process: [[::SecurityCenter::SecurityFeatures::SECRET_SCANNING]])
          end
        end
      end
    end

    private

    sig do
      params(
        scope: T.any(Organization, Business),
        user: User,
        features_to_process: T::Array[T::Array[String]],
        export_id: T.nilable(String),
        authorized_orgs: T.nilable(T::Array[Organization])
      ).returns(OverviewDashboardExportBatchedJob)
    end
    def queue_job(
      scope: @org,
      user: @orgs_owner,
      features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS], [::SecurityCenter::SecurityFeatures::SECRET_SCANNING], ["codeql"]],
      export_id: nil,
      authorized_orgs: nil
    )
      authorized_orgs = [:code_scanning, :dependabot_alerts, :secret_scanning].product([authorized_orgs]).to_h unless authorized_orgs.nil?
      authorized_orgs_by_action = [:read_code_scanning, :view_dependabot_alerts, :view_secret_scanning_alerts].product([authorized_orgs]).to_h unless authorized_orgs.nil?

      OverviewDashboardExportBatchedJob.perform_later(
        scope:,
        user:,
        export_id:,
        security_feature: features_to_process.pop,
        features_to_process: features_to_process,
        user_session: @user_session,
        is_first_feature: true,
        authorized_orgs:,
        authorized_orgs_by_action:,
        offset_item_id: 0
      ).tap do |job|
        fail "Expected job to be enqueued" unless job
      end
    end

    sig { params(user: User, scope: T.any(Organization, Business), query: String, requested_at: Time).returns(String) }
    def create_export_id(user:, scope:, query: "", requested_at: @now)
      Export::TokenGenerator.create_token(user:, scope:, query:, feature_type: "overview_dashboard", requested_at:, start_date: (@now - 7.days).to_date, end_date: @now.to_date)
    end

    sig { params(id: String, scope: T.any(Business, Organization), query: String, requester: User, requested_at: Time, start_date: Time, end_date: Time).returns(::SecurityCenter::Export::JobStatus) }
    def create_job_status(
      id:,
      scope:,
      query: "",
      requester: @orgs_owner,
      requested_at: @now,
      start_date: (@now - 7.days).dup.utc.to_date,
      end_date: @now.dup.utc.to_date
    )
      ::SecurityCenter::Export::JobStatus.create(id:, query:, scope:, requester:, requested_at:, start_date:, end_date:)
    end
  end
end
