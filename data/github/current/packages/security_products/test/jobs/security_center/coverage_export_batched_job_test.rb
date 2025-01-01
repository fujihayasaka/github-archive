# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityCenter
  class CoverageExportBatchedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper
    include SecurityCenter::TestFixtures

    fixtures do
      create_business_level_fixtures

      @user_session = create(:user_session, user: @orgs_owner)

      @repo = create(:private_repository, owner: @org)
      @repo_config = create(:repository_security_center_config, repository: @repo).tap do
        RepositorySecurityCenterStatus.all_feature_types.map(&:to_sym).each do |feature_type|
          create(:repository_security_center_status,
            repository: @repo,
            feature_type:,
            scanning_status: feature_type == :code_scanning_auto_codeql ? "not_eligible" : "not_enrolled"
          )
        end
      end
      create(:soa_repository, repository: @repo).tap do |repository_metadata|
        create(:soa_feature_status, repository_metadata:, advanced_security_status: "ENABLED")
      end

      @team = create(:team, organization: @org)
      @repo.send(:grant, @team, :admin)

      @org2_repo = create(:private_repository, owner: @org2)
      team = create(:team, organization: @org2)
      @org2_repo.send(:grant, team, :admin)
      @org2_repo_config = create(:repository_security_center_config, repository: @org2_repo)
      create(:soa_repository, repository: @org2_repo).tap do |repository_metadata|
        create(:soa_feature_status, repository_metadata:)
      end

      definition = create :custom_property_definition, :single_select, source: @org, property_name: "single-select", allowed_values: %w[value another nomatch]
      create :custom_property_value, target: @repo, definition: definition, value: "value"

      definition2 = create :custom_property_definition, :single_select, source: @org2, property_name: "single-select-2", allowed_values: %w[value2 another2 nomatch2]
      create :custom_property_value, target: @org2_repo, definition: definition2, value: "value2"

      topic = create(:topic, name: "repo-topic")
      topic.repository_topics.create!(repository: @repo, state: :created, user: @orgs_owner)
      topic.repository_topics.create!(repository: @org2_repo, state: :created, user: @orgs_owner)

      @now = Time.now.freeze
    end

    setup do
      # Clear jobs and email cache
      reset_jobs
      ActionMailer::Base.deliveries.clear
      ::SecurityCenter::FeatureFlagHelper.stubs(:enterprise_coverage_csv_export?).returns(false)
    end

    context "organization", skip_enterprise: true do
      context "batch job" do
        test "it validates required parameters" do
          kwargs = {
            scope: @org,
            user: @orgs_owner,
            user_session: @orgs_owner_user_session,
            export_id: "foo",
          }

          assert_raises(ArgumentError) { CoverageExportBatchedJob.perform_later(**kwargs, scope: nil) }
          assert_raises(ArgumentError) { CoverageExportBatchedJob.perform_later(**kwargs, user: nil) }
          assert_raises(ArgumentError) { CoverageExportBatchedJob.perform_later(**kwargs, user_session: nil) }
          assert_raises(ArgumentError) { CoverageExportBatchedJob.perform_later(**kwargs, export_id: nil) }
        end

        test "queues subsequent jobs for batching" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(3)

          repo2 = create(:repository, owner: @org)
          create(:repository_security_center_config, repository: repo2)
          create(:soa_repository, repository: repo2).tap do |repository_metadata|
            create(:soa_feature_status, repository_metadata:)
          end

          repo3 = create(:internal_repository, owner: @org)
          create(:repository_security_center_config, repository: repo3)
          create(:soa_repository, repository: repo3).tap do |repository_metadata|
            create(:soa_feature_status, repository_metadata:)
          end

          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          CoverageExportBatchedJob.stub_const(:BATCH_SIZE, 1) do
            SecurityOverviewAnalytics::Coverage::ExportQuery.stub_const(:PAGE_SIZE, 1) do
              perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
                queue_job(export_id:)
              end
            end
          end
        end

        test "Content stored in Azure is correct" do
          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          if FeatureFlagHelper.coverage_export_include_repo_properties?(@org)
            SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once.with(
              export_id,
              "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Status,Dependabot Security Updates Status,Code Scanning Alerts Status,Code Scanning Pull Request Alerts Status,Code Scanning Default Setup Status,Secret Scanning Alerts Status,Secret Scanning Push Protection Status,Advanced Security Status,Topics,Teams (truncated at #{Coverage::ExportCsvGenerator::ELEMENT_COUNT_CAP} values),Custom Property: single-select\n" \
                "#{@org.display_login},#{@repo.name},false,#{@repo_config.last_push},private,not-enabled,not-enabled,not-enabled,not-enabled,ineligible,not-enabled,not-enabled,enabled,\"[\"\"repo-topic\"\"]\",\"[\"\"#{@team.name}\"\"]\",value\n",
              "coverage",
            )
          else
            SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once.with(
              export_id,
              "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Status,Dependabot Security Updates Status,Code Scanning Alerts Status,Code Scanning Pull Request Alerts Status,Code Scanning Default Setup Status,Secret Scanning Alerts Status,Secret Scanning Push Protection Status,Advanced Security Status,Topics,Teams (truncated at #{Coverage::ExportCsvGenerator::ELEMENT_COUNT_CAP} values)\n" \
                "#{@org.display_login},#{@repo.name},false,#{@repo_config.last_push},private,not-enabled,not-enabled,not-enabled,not-enabled,ineligible,not-enabled,not-enabled,enabled,\"[\"\"repo-topic\"\"]\",\"[\"\"#{@team.name}\"\"]\"\n",
              "coverage",
            )
          end

          perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
            queue_job(export_id:)
          end
        end

        test "Store CSV with new headers if enterprise feature flag is enabled" do
          ::SecurityCenter::FeatureFlagHelper.stubs(:enterprise_coverage_csv_export?).returns(true)

          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          if FeatureFlagHelper.coverage_export_include_repo_properties?(@org)
            SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once.with(
              export_id,
              "Owner,Repository,Owner type,Archived,Updated At,Visibility,Dependabot Alerts Status,Dependabot Security Updates Status,Code Scanning Alerts Status,Code Scanning Pull Request Alerts Status,Code Scanning Default Setup Status,Secret Scanning Alerts Status,Secret Scanning Push Protection Status,Advanced Security Status,Topics,Teams (truncated at #{Coverage::ExportCsvGenerator::ELEMENT_COUNT_CAP} values),Custom Property: single-select\n" \
                "#{@org.display_login},#{@repo.name},ORGANIZATION,false,#{@repo_config.last_push},private,not-enabled,not-enabled,not-enabled,not-enabled,ineligible,not-enabled,not-enabled,enabled,\"[\"\"repo-topic\"\"]\",\"[\"\"#{@team.name}\"\"]\",value\n",
              "coverage",
            )
          else
            SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once.with(
              export_id,
              "Owner,Repository,Owner type,Archived,Updated At,Visibility,Dependabot Alerts Status,Dependabot Security Updates Status,Code Scanning Alerts Status,Code Scanning Pull Request Alerts Status,Code Scanning Default Setup Status,Secret Scanning Alerts Status,Secret Scanning Push Protection Status,Advanced Security Status,Topics,Teams (truncated at #{Coverage::ExportCsvGenerator::ELEMENT_COUNT_CAP} values)\n" \
                "#{@org.display_login},#{@repo.name},ORGANIZATION,false,#{@repo_config.last_push},private,not-enabled,not-enabled,not-enabled,not-enabled,ineligible,not-enabled,not-enabled,enabled,\"[\"\"repo-topic\"\"]\",\"[\"\"#{@team.name}\"\"]\"\n",
              "coverage",
            )
          end

          perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
            queue_job(export_id:)
          end
        end

        test "Logs telemetry and raises error when status is not found" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).never
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).never

          perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
            assert_raises(StandardError) do
              queue_job(export_id: "foo")
            end
          end

          assert_dogstats_increment(1, "security_center.coverage_export_batched_job.job_status_not_found")
        end

        test "Emails users a link to their export results" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once

          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          assert_equal 0, ActionMailer::Base.deliveries.size

          assert_performed_jobs 1, only: CoverageExportBatchedJob do
            perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
              queue_job(export_id:)
            end
          end

          assert_equal 1, ActionMailer::Base.deliveries.size
          email = ActionMailer::Base.deliveries.first
          assert_includes email.to, @orgs_owner.email
          assert_includes email.subject, "[GitHub] Your coverage CSV is ready"
        end

        test "Emails user if an error is encountered during the job" do
          export_id = create_export_id(user: @orgs_owner, scope: @org)
          create_job_status(id: export_id, scope: @org)

          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once.raises(StandardError)

          assert_equal 0, ActionMailer::Base.deliveries.size

          perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
            assert_raises(StandardError) do
              queue_job(export_id:)
            end
          end

          assert_equal 1, ActionMailer::Base.deliveries.size
          email = ActionMailer::Base.deliveries.first
          assert_includes email.to, @orgs_owner.email
          assert_includes email.subject, "[GitHub] Sorry, your coverage CSV couldn't be generated"
        end
      end

      # cont?
    end

    context "business", skip_enterprise: true do
      context "batch job" do
        test "it validates required parameters" do
          features_to_process = [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS], [::SecurityCenter::SecurityFeatures::SECRET_SCANNING], ["codeql"]]
          kwargs = {
            scope: @business,
            user: @orgs_owner,
            user_session: nil,
            authorized_orgs: @business.organizations.to_a,
            export_id: "foo",
            offset_item_id: 1
          }

          assert_raises(ArgumentError) { CoverageExportBatchedJob.perform_later(**kwargs, scope: nil) }
          assert_raises(ArgumentError) { CoverageExportBatchedJob.perform_later(**kwargs, user: nil) }
          assert_raises(ArgumentError) { CoverageExportBatchedJob.perform_later(**kwargs, export_id: nil) }
          assert_raises(ArgumentError) { CoverageExportBatchedJob.perform_later(**kwargs, authorized_orgs: nil) }
          assert_raises(ArgumentError) { CoverageExportBatchedJob.perform_later(**kwargs, offset_item_id: 0) }
        end

        test "queues subsequent jobs for batching" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).times(4)

          repo2 = create(:repository, owner: @org)
          create(:repository_security_center_config, repository: repo2)
          create(:soa_repository, repository: repo2).tap do |repository_metadata|
            create(:soa_feature_status, repository_metadata:)
          end

          repo3 = create(:internal_repository, owner: @org)
          create(:repository_security_center_config, repository: repo3)
          create(:soa_repository, repository: repo3).tap do |repository_metadata|
            create(:soa_feature_status, repository_metadata:)
          end

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          CoverageExportBatchedJob.stub_const(:BATCH_SIZE, 1) do
            SecurityOverviewAnalytics::Coverage::ExportQuery.stub_const(:PAGE_SIZE, 1) do
              perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
                queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
              end
            end
          end
        end

        test "Filters to authorized orgs" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once

          org3 = create(:business_plus_organization, business: @business)
          org3.add_admin(@orgs_owner)

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          # check that we only try to store the CSV headers (we don't include the out-of-scope repo)
          csv_headers_only = "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Status,Dependabot Security Updates Status,Code Scanning Alerts Status,Code Scanning Pull Request Alerts Status,Code Scanning Default Setup Status,Secret Scanning Alerts Status,Secret Scanning Push Protection Status,Advanced Security Status,Topics,Teams (truncated at #{Coverage::ExportCsvGenerator::ELEMENT_COUNT_CAP} values)\n"
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store)
            .with(export_id, csv_headers_only, "coverage")
            .once # even though we run 3 jobs, we only upload to Azure once (the headers)

          assert_performed_jobs 1, only: CoverageExportBatchedJob do
            perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
              queue_job(export_id:, scope: @business, authorized_orgs: [org3])
            end
          end
        end

        test "Content stored in Azure is correct" do
          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once.with(
            export_id,
            "Organization,Name,Archived,Updated At,Visibility,Dependabot Alerts Status,Dependabot Security Updates Status,Code Scanning Alerts Status,Code Scanning Pull Request Alerts Status,Code Scanning Default Setup Status,Secret Scanning Alerts Status,Secret Scanning Push Protection Status,Advanced Security Status,Topics,Teams (truncated at #{Coverage::ExportCsvGenerator::ELEMENT_COUNT_CAP} values)\n" \
              "#{@org.display_login},#{@repo.name},false,#{@repo_config.last_push},private,not-enabled,not-enabled,not-enabled,not-enabled,ineligible,not-enabled,not-enabled,enabled,\"[\"\"repo-topic\"\"]\",\"[\"\"#{@team.name}\"\"]\"\n",
            "coverage",
          )

          perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
            queue_job(export_id:, scope: @business, authorized_orgs: [@org])
          end
        end

        test "Store CSV with new headers if enterprise feature flag is enabled" do
          ::SecurityCenter::FeatureFlagHelper.stubs(:enterprise_coverage_csv_export?).returns(true)

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once.with(
            export_id,
            "Owner,Repository,Owner type,Archived,Updated At,Visibility,Dependabot Alerts Status,Dependabot Security Updates Status,Code Scanning Alerts Status,Code Scanning Pull Request Alerts Status,Code Scanning Default Setup Status,Secret Scanning Alerts Status,Secret Scanning Push Protection Status,Advanced Security Status,Topics,Teams (truncated at #{Coverage::ExportCsvGenerator::ELEMENT_COUNT_CAP} values)\n" \
              "#{@org.display_login},#{@repo.name},ORGANIZATION,false,#{@repo_config.last_push},private,not-enabled,not-enabled,not-enabled,not-enabled,ineligible,not-enabled,not-enabled,enabled,\"[\"\"repo-topic\"\"]\",\"[\"\"#{@team.name}\"\"]\"\n",
            "coverage",
          )

          perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
            queue_job(export_id:, scope: @business, authorized_orgs: [@org])
          end
        end

        test "Logs telemetry and raises error when status is not found" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).never
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).never

          perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
            assert_raises(StandardError) do
              queue_job(export_id: "foo", scope: @business, authorized_orgs: @business.organizations.to_a)
            end
          end

          assert_dogstats_increment(1, "security_center.coverage_export_batched_job.job_status_not_found")
        end

        test "Emails users a link to their export results" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          assert_equal 0, ActionMailer::Base.deliveries.size

          assert_performed_jobs 1, only: CoverageExportBatchedJob do
            perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
              queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
            end
          end

          assert_equal 1, ActionMailer::Base.deliveries.size
          email = ActionMailer::Base.deliveries.first
          assert_includes email.to, @orgs_owner.email
          assert_includes email.subject, "[GitHub] Your coverage CSV is ready"
        end

        test "Emails user if an error is encountered during the job" do
          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once.raises(StandardError)

          assert_equal 0, ActionMailer::Base.deliveries.size

          perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
            assert_raises(StandardError) do
              queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
            end
          end

          assert_equal 1, ActionMailer::Base.deliveries.size
          email = ActionMailer::Base.deliveries.first
          assert_includes email.to, @orgs_owner.email
          assert_includes email.subject, "[GitHub] Sorry, your coverage CSV couldn't be generated"
        end
      end

      context "JobStatus" do
        test "Marked as success when final job finishes" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          assert Export::JobStatus.find(export_id)&.pending?

          assert_performed_jobs 1, only: CoverageExportBatchedJob do
            perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
              queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
            end
          end

          assert Export::JobStatus.find(export_id)&.finished?
          assert Export::JobStatus.find(export_id)&.success?
        end

        test "Update ttl after enqueue" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once

          Timecop.freeze do
            export_id = create_export_id(user: @orgs_owner, scope: @business)
            create_job_status(id: export_id, scope: @business)
            assert_equal 1.minute.to_i, ::SecurityCenter::Export::JobStatus.find(export_id)&.ttl

            assert Export::JobStatus.find(export_id)&.pending?

            assert_performed_jobs 1, only: CoverageExportBatchedJob do
              perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
                queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
              end
            end

            assert_equal 10.minutes, ::SecurityCenter::Export::JobStatus.find(export_id)&.ttl
          end
        end

        test "Swallow and report mailing errors, and still mark job as success" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).once
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once
          SecurityCenterMailer.any_instance.expects(:csv_export_ready).raises(StandardError)

          export_id = create_export_id(user: @orgs_owner, scope: @business)
          create_job_status(id: export_id, scope: @business)

          assert Export::JobStatus.find(export_id)&.pending?

          perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
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

          perform_enqueued_jobs(only: [CoverageExportBatchedJob]) do
            assert_raises(StandardError) do
              queue_job(export_id:, scope: @business, authorized_orgs: @business.organizations.to_a)
            end
          end

          assert Export::JobStatus.find(export_id)&.finished?
          assert Export::JobStatus.find(export_id)&.error?

          assert_equal 1, ActionMailer::Base.deliveries.size
          email = ActionMailer::Base.deliveries.first
          assert_includes email.to, @orgs_owner.email
          assert_includes email.subject, "[GitHub] Sorry, your coverage CSV couldn't be generated"
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
      ).returns(CoverageExportBatchedJob)
    end
    def queue_job(
      scope: @org,
      user: @orgs_owner,
      features_to_process: [[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS], [::SecurityCenter::SecurityFeatures::SECRET_SCANNING], ["codeql"]],
      export_id: nil,
      authorized_orgs: nil
    )
      CoverageExportBatchedJob.perform_later(
        scope:,
        user:,
        export_id:,
        user_session: @user_session,
        authorized_orgs:,
      ).tap do |job|
        fail "Expected job to be enqueued" unless job
      end
    end

    sig { params(user: User, scope: T.any(Organization, Business), query: String, requested_at: Time).returns(String) }
    def create_export_id(user:, scope:, query: "", requested_at: @now)
      Export::TokenGenerator.create_token(user:, scope:, query:, feature_type: "coverage", requested_at:)
    end

    sig { params(id: String, scope: T.any(Business, Organization), query: String, requester: User, requested_at: Time).returns(Export::JobStatus) }
    def create_job_status(
      id:,
      scope:,
      query: "",
      requester: @orgs_owner,
      requested_at: @now
    )
      Export::JobStatus.create(id:, query:, scope:, requester:, requested_at:)
    end
  end
end
