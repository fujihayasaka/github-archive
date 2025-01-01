# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroSecretScanningAlertModifiedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      GitHub.global_business || create(:business)
      @queue = HydroSecretScanningAlertModifiedJob.queue_name
      @schema = "github.security_center.v0.InsightsEntityBatch"

      @org = create(:organization)
      @repo = create(:repository, owner: @org)
      @org2 = create(:organization)
      @repo2 = create(:repository, owner: @org2)
    end

    setup do
      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
      SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(true)
    end

    context "#perform" do
      test "calls ingestion job for alert changes" do
        Repository.any_instance.expects(:secret_scanning_security_center_status).returns(
          Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new(
            "enrolled",
            10
          )
        ).twice

        perform_hydro_message_job({
          entity: "secret_scanning_alert",
          entities_updated: [{
            data: alert_updated_payload(repository_id: @repo.id.to_s, alert_number: "111")
          }],
          entities_deleted: [{
            data: alert_deleted_payload(repository_id: @repo2.id.to_s, alert_number: "222")
          }]
        }, schema: @schema, queue: @queue)

        refute_dogstats_increment "security_center.insights_entity_batch.alert_skipped"
        refute_dogstats_increment "security_center.insights_entity_batch.skipped"
        assert_dogstats_distribution 1, "security_center.repository_updated.dist"

        db_status = RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "secret_scanning")
        assert db_status
        assert_equal "enrolled", db_status&.scanning_status
        assert_equal 10, db_status&.scanning_count
        assert_empty SecurityCenterAlertSeverity.where(repository_id: @repo.id, feature_type: "secret_scanning")

        db_status2 = RepositorySecurityCenterStatus.find_by(repository_id: @repo2.id, feature_type: "secret_scanning")
        assert db_status2
        assert_equal "enrolled", db_status2&.scanning_status
        assert_equal 10, db_status2&.scanning_count
        assert_empty SecurityCenterAlertSeverity.where(repository_id: @repo2.id, feature_type: "secret_scanning")
      end

      context "on GHES, when repository is user owned", enterprise_only: true do
        test "calls ingestion job for alert changes" do
          AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

          user = create(:user)
          repo = create(:repository, owner: user, force_user_owned: true)

          Repository.any_instance.expects(:secret_scanning_security_center_status).returns(
            Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new(
              "enrolled",
              10
            )
          ).once

          perform_hydro_message_job({
            entity: "secret_scanning_alert",
            entities_updated: [{
              data: alert_updated_payload(repository_id: repo.id.to_s, alert_number: "111")
            }],
            entities_deleted: []
          }, schema: @schema, queue: @queue)

          refute_dogstats_increment "security_center.insights_entity_batch.alert_skipped"
          refute_dogstats_increment "security_center.insights_entity_batch.skipped"
          assert_dogstats_distribution 1, "security_center.repository_updated.dist"

          db_status = RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning")
          assert db_status
          assert_equal "enrolled", db_status&.scanning_status
          assert_equal 10, db_status&.scanning_count
          assert_empty SecurityCenterAlertSeverity.where(repository_id: repo.id, feature_type: "secret_scanning")
        end

        test "does nothing when the feature flag is disabled" do
          AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(false)

          user = create(:user)
          repo = create(:private_repository, force_user_owned: true, owner: user)

          perform_hydro_message_job({
            entity: "secret_scanning_alert",
            entities_updated: [{
              data: alert_updated_payload(repository_id: repo.id.to_s, alert_number: "111")
            }],
          }, schema: @schema, queue: @queue)

          assert_dogstats_increment 1, "security_center.insights_entity_batch.alert_skipped", tags: ["reason:owner_not_eligible"]
          refute_dogstats_distribution "security_center.repository_updated.dist"
          assert_nil RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning")
        end
      end

      context "on non-GHES, when repository is user-owned", skip_enterprise: true do
        test "it does not update for non-EMU accounts" do
          user = create(:user)
          repo = create(:repository, owner: user, force_user_owned: true)

          perform_hydro_message_job({
            entity: "secret_scanning_alert",
            entities_updated: [{
              data: alert_updated_payload(repository_id: repo.id.to_s, alert_number: "111")
            }],
          }, schema: @schema, queue: @queue)

          assert_dogstats_increment 1, "security_center.insights_entity_batch.alert_skipped", tags: ["reason:owner_not_eligible"]
          refute_dogstats_distribution "security_center.repository_updated.dist"
          assert_nil RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning")
        end

        test "calls ingestion job for alert changes on an EMU repo" do
          emu = create(:emu)
          repo = create(:private_repository, force_user_owned: true, owner: emu)

          Repository.any_instance.expects(:secret_scanning_security_center_status).returns(
            Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new(
              "enrolled",
              10
            )
          ).once

          perform_hydro_message_job({
            entity: "secret_scanning_alert",
            entities_updated: [{
              data: alert_updated_payload(repository_id: repo.id.to_s, alert_number: "111")
            }],
            entities_deleted: []
          }, schema: @schema, queue: @queue)

          refute_dogstats_increment "security_center.insights_entity_batch.alert_skipped"
          refute_dogstats_increment "security_center.insights_entity_batch.skipped"
          assert_dogstats_distribution 1, "security_center.repository_updated.dist"

          db_status = RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning")
          assert db_status
          assert_equal "enrolled", db_status&.scanning_status
          assert_equal 10, db_status&.scanning_count
          assert_empty SecurityCenterAlertSeverity.where(repository_id: repo.id, feature_type: "secret_scanning")
        end
      end

      test "skips event if it has different feature type" do
        Repository.any_instance.expects(:secret_scanning_security_center_status).never

        perform_hydro_message_job({
          entity: "dependabot_alert",
          entities_updated: [{
            data: alert_updated_payload(repository_id: @repo.id.to_s, alert_number: "111")
          }],
        }, schema: @schema, queue: @queue)

        assert_dogstats_increment 1, "security_center.insights_entity_batch.skipped", tags: ["reason:unexpected_entity_type"]
        refute_dogstats_distribution "security_center.repository_updated.dist"
        assert_nil RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "secret_scanning")
      end

      test "skips event if repo soft deleted" do
        repo = create(:repository, :soft_deleted, owner: @org)
        Repository.any_instance.expects(:secret_scanning_security_center_status).never

        perform_hydro_message_job({
          entity: "secret_scanning_alert",
          entities_updated: [{
            data: alert_updated_payload(repository_id: repo.id.to_s, alert_number: "111")
          }],
        }, schema: @schema, queue: @queue)

        assert_dogstats_increment 1, "security_center.insights_entity_batch.alert_skipped", tags: ["reason:repo_not_found"]
        refute_dogstats_distribution "security_center.repository_updated.dist"
        assert_nil RepositorySecurityCenterStatus.find_by(repository_id: repo.id, feature_type: "secret_scanning")
      end

      test "skips event if security feature is not visible on target org" do
        Repository.any_instance.expects(:secret_scanning_security_center_status).never
        SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(false)

        perform_hydro_message_job({
          entity: "secret_scanning_alert",
          entities_updated: [{
            data: alert_updated_payload(repository_id: @repo.id.to_s, alert_number: "111")
          }],
        }, schema: @schema, queue: @queue)

        assert_dogstats_increment 1, "security_center.insights_entity_batch.alert_skipped", tags: ["reason:owner_not_in_scope"]
        refute_dogstats_distribution "security_center.repository_updated.dist"
        assert_nil RepositorySecurityCenterStatus.find_by(repository_id: @repo.id, feature_type: "secret_scanning")
      end
    end

    context "resiliency" do
      test "it retries on recoverable errors" do
        repo = create(:repository, owner: create(:organization))

        message = {
          entity: "secret_scanning_alert",
          entities_updated: [{
            data: alert_updated_payload(repository_id: @repo.id.to_s, alert_number: "111")
          }],
        }

        Resiliency::Response::UnavailableExceptions.each do |exception|
          Repository.any_instance.expects(:security_center_notify).raises(exception, "boom")
          HydroSecretScanningAlertModifiedJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end

      test "it retries on throttler errors" do
        repo = create(:repository, owner: create(:organization))

        message = {
          entity: "secret_scanning_alert",
          entities_updated: [{
            data: alert_updated_payload(repository_id: @repo.id.to_s, alert_number: "111")
          }],
        }

        [Freno::Throttler::Error, Freno::Throttler::WaitedTooLong].each do |exception|
          Repository.any_instance.expects(:security_center_notify).raises(exception)
          HydroSecretScanningAlertModifiedJob.any_instance.expects(:retry).once
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end
    end

    private

    def alert_updated_payload(repository_id:, alert_number:, **kwargs)
      now = Time.now.utc

      {
        "repository_id" => repository_id,
        "number" => alert_number,
        "created_at" => now.rfc3339(9),
        "updated_at" => now.rfc3339(9),
        "token_type" => "woof",
        "token_type_provider" => "any_provider",
        "slug" => "woof",
        "resolved" => "false",
        "resolution" => "1",
        "resolved_at" => now.rfc3339(9),
        "has_valid_locations" => "true",
        **kwargs
      }.stringify_keys
    end

    def alert_deleted_payload(repository_id:, alert_number:, **kwargs)
      {
        "repository_id" => repository_id,
        "number" => alert_number,
        **kwargs
      }.stringify_keys
    end
  end
end
