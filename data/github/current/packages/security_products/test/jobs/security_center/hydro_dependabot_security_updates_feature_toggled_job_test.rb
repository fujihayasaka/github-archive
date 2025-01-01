# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroDependabotSecurityUpdatesFeatureToggledJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      @org = create(:organization)
    end

    setup do
      # referencing the job class forces it to load, so it can be looked up by queue name
      @queue = SecurityCenter::HydroDependabotSecurityUpdatesFeatureToggledJob.queue_name
      @schema_enabled = "github.v1.RepositoryDependencyUpdatesVulnerabilitiesEnabled"
      @schema_disabled = "github.v1.RepositoryDependencyUpdatesVulnerabilitiesDisabled"

      SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
    end

    [
      "github.v1.RepositoryDependencyUpdatesVulnerabilitiesEnabled",
      "github.v1.RepositoryDependencyUpdatesVulnerabilitiesDisabled",
      # In production these include the `hydro.` prefix, while in tests/dev they do not. Assert both.
      "hydro.schemas.github.v1.RepositoryDependencyUpdatesVulnerabilitiesEnabled",
      "hydro.schemas.github.v1.RepositoryDependencyUpdatesVulnerabilitiesDisabled",
    ].each do |schema|
      context "when schema is #{schema}" do
        test "it updates feature data" do
          repo = create(:repository, owner: @org)

          Repository.any_instance.expects(:security_updates_security_center_status)
            .returns(Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled"))
            .once

          message = {
            repository: {
              id: repo.id
            }
          }

          perform_hydro_message_job(message, schema: schema, queue: @queue)

          refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "dependabot_alerts")
          db_status = RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "dependabot_security_updates")
          assert db_status
          assert_equal "enrolled", db_status&.scanning_status
        end

        context "when repository is soft-deleted" do
          test "it does not update" do
            repo = create(:repository, :soft_deleted, owner: create(:user))
            Repository.any_instance.expects(:security_center_notify).never

            message = {
              repository: {
                id: repo.id
              }
            }

            perform_hydro_message_job(message, schema: schema, queue: @queue)

            refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "dependabot_security_updates")
            assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:repo_deleted"])
          end
        end

        context "when repository is user-owned" do
          test "it does not update" do
            repo = create(:repository, owner: create(:user))
            Repository.any_instance.expects(:security_center_notify).never

            message = {
              repository: {
                id: repo.id
              }
            }

            perform_hydro_message_job(message, schema: schema, queue: @queue)

            refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "dependabot_alerts")
            refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "dependabot_security_updates")
            assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:owner_not_org"])
          end
        end

        context "when feature is not available for owner" do
          test "it does not update" do
            repo = create(:repository, owner: @org)
            Repository.any_instance.expects(:security_center_notify).never
            SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(false)

            message = {
              repository: {
                id: repo.id
              }
            }

            perform_hydro_message_job(message, schema: schema, queue: @queue)

            refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "dependabot_alerts")
            refute RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "dependabot_security_updates")
            assert_dogstats_increment("security_center.repository_update.abort", tags: ["cause:feature_not_available"])
          end
        end

        context "lifecycle telemetry" do
          test "reports telemetry when job completes successfully" do
            repo = create(:repository, owner: @org)

            message = {
              repository: {
                id: repo.id
              }
            }

            perform_hydro_message_job(message, schema: schema, queue: @queue)

            assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: ["source_event:#{schema}"])
          end

          test "does not report telemetry when job fails" do
            repo = create(:repository, owner: @org)

            message = {
              repository: {
                id: repo.id
              }
            }

            assert_raises(StandardError) do
              Repository.any_instance.stubs(:security_center_notify).raises(StandardError.new).once
              perform_hydro_message_job(message, schema: schema, queue: @queue)
            end

            refute_dogstats_distribution("security_center.repository_updated.dist")
          end
        end

        context "resiliency" do
          test "it retries on recoverable errors" do
            repo = create(:repository, owner: create(:organization))

            message = {
              repository: {
                id: repo.id
              }
            }

            Resiliency::Response::UnavailableExceptions.each do |exception|
              Repository.any_instance.expects(:security_center_notify).raises(exception, "boom")
              HydroDependabotSecurityUpdatesFeatureToggledJob.any_instance.expects(:retry).once
              perform_hydro_message_job(message, schema: schema, queue: @queue)
            end
          end

          test "it retries on throttler errors" do
            repo = create(:repository, owner: create(:organization))

            message = {
              repository: {
                id: repo.id
              }
            }

            [Freno::Throttler::Error, Freno::Throttler::WaitedTooLong].each do |exception|
              Repository.any_instance.expects(:security_center_notify).raises(exception)
              HydroDependabotSecurityUpdatesFeatureToggledJob.any_instance.expects(:retry).once
              perform_hydro_message_job(message, schema: schema, queue: @queue)
            end
          end

          test "it retries when repo not found" do
            ::Repositories::Public.expects(:get_active_or_deleted!).raises(ActiveRecord::RecordNotFound)
            HydroDependabotSecurityUpdatesFeatureToggledJob.any_instance.expects(:retry).once
            repo_id = (::Repository.maximum(:id) || 100).next

            message = {
              repository: {
                id: repo_id
              }
            }

            perform_hydro_message_job(message, schema: schema, queue: @queue)
          end
        end
      end
    end
  end
end
