# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroCodeScanningFeatureToggledJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    QUEUE = HydroCodeScanningFeatureToggledJob.queue_name
    SCHEMAS = [
      "code_scanning.v0.CodeScanningFeatureToggled",
      "github.code_security.v1.CodeSecurityFeatureToggled"
    ]

    setup do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(true)
    end

    SCHEMAS.each do |schema|
      context "schema #{schema}" do
        test "it updates feature data using schema" do
          repo = create(:repository, owner: create(:organization))

          Repository.any_instance.expects(:code_scanning_security_center_status)
            .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))
          Repository.any_instance.expects(:code_scanning_review_security_center_status)
            .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))
          Repository.any_instance.expects(:code_scanning_auto_codeql_security_center_status)
            .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))

          message = {
            repository_id: repo.id,
            feature_enabled: true,
          }

          perform_hydro_message_job(message, schema: schema, queue: QUEUE)

          db_status = RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "code_scanning")
          assert db_status
          assert_equal "enrolled", db_status&.scanning_status
        end

        context "when repository is soft-deleted" do
          test "it does not update" do
            repo = create(:repository, :soft_deleted, owner: create(:user))
            Repository.any_instance.expects(:security_center_notify).never

            message = {
              repository_id: repo.id,
              feature_enabled: true,
            }

            perform_hydro_message_job(message, schema: schema, queue: QUEUE)

            refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "code_scanning")
            assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:repo_deleted"])
          end
        end

        context "when repository is user-owned" do
          test "it does not update" do
            repo = create(:repository, owner: create(:user))
            Repository.any_instance.expects(:security_center_notify).never

            message = {
              repository_id: repo.id,
              feature_enabled: true,
            }

            perform_hydro_message_job(message, schema: schema, queue: QUEUE)

            refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "code_scanning")
            assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_org"])
          end
        end

        context "when feature is not available for owner" do
          test "it does not update" do
            repo = create(:repository, owner: create(:organization))
            Repository.any_instance.expects(:security_center_notify).never
            SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(false)

            message = {
              repository_id: repo.id,
              feature_enabled: true,
            }

            perform_hydro_message_job(message, schema: schema, queue: QUEUE)

            refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "code_scanning")
            assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:feature_not_available"])
          end
        end

        context "lifecycle telemetry" do
          test "reports telemetry when job completes successfully" do
            repo = create(:repository, owner: create(:organization))
            Repository.any_instance.expects(:security_center_notify).once

            message = {
              repository_id: repo.id,
              feature_enabled: true,
            }

            perform_hydro_message_job(message, schema: schema, queue: QUEUE)

            assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: ["source_event:#{schema}#enable"])
          end

          test "does not report telemetry when job fails" do
            repo = create(:repository, owner: create(:organization))

            message = {
              repository_id: repo.id,
              feature_enabled: true,
            }

            assert_raises(StandardError) do
              Repository.any_instance.stubs(:security_center_notify).raises(StandardError.new).once
              perform_hydro_message_job(message, schema: schema, queue: QUEUE)
            end

            refute_dogstats_distribution("security_center.repository_updated.dist")
          end
        end

        context "resiliency" do
          test "it retries on recoverable errors" do
            repo = create(:repository, owner: create(:organization))

            message = {
              repository_id: repo.id,
              feature_enabled: true,
            }

            Resiliency::Response::UnavailableExceptions.each do |exception|
              Repository.any_instance.expects(:security_center_notify).raises(exception, "boom")
              HydroCodeScanningFeatureToggledJob.any_instance.expects(:retry).once
              perform_hydro_message_job(message, schema: schema, queue: QUEUE)
            end
          end

          test "it retries on AutoCodeql errors" do
            Repository.any_instance.expects(:security_center_notify).raises(CodeScanning::AutoCodeqlError.new("boom"))
            HydroCodeScanningFeatureToggledJob.any_instance.expects(:retry).once

            repo = create(:repository, owner: create(:organization))

            message = {
              repository_id: repo.id,
              feature_enabled: true,
            }

            perform_hydro_message_job(message, schema: schema, queue: QUEUE)
          end

          test "it retries on throttler errors" do
            repo = create(:repository, owner: create(:organization))

            message = {
              repository_id: repo.id,
              feature_enabled: true,
            }

            [Freno::Throttler::Error, Freno::Throttler::WaitedTooLong].each do |exception|
              Repository.any_instance.expects(:security_center_notify).raises(exception)
              HydroCodeScanningFeatureToggledJob.any_instance.expects(:retry).once
              perform_hydro_message_job(message, schema: schema, queue: QUEUE)
            end
          end

          test "it retries when repo not found" do
            ::Repositories::Public.expects(:get_active_or_deleted!).raises(ActiveRecord::RecordNotFound)
            HydroCodeScanningFeatureToggledJob.any_instance.expects(:retry).once

            message = {
              repository_id: -1,
              feature_enabled: true,
            }

            perform_hydro_message_job(message, schema: schema, queue: QUEUE)
          end
        end
      end
    end
  end
end
