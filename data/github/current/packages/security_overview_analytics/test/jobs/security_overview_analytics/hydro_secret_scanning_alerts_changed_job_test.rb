# typed: true
# frozen_string_literal: true

require "test_helper"
require "secret_scanning_proto"

module SecurityOverviewAnalytics
  class HydroSecretScanningAlertsChangedJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers
    include DogstatsTestHelpers

    fixtures do
      @queue = HydroSecretScanningAlertsChangedJob.queue_name
      @schema = "github.security_center.v0.InsightsEntityBatch"
      @org1 = create(:business_plus_organization)
      @repo1 = create(:repository, owner: @org1)
      @org2 = create(:organization)
      @repo2 = create(:repository, owner: @org2)

      @user = create(:user)
      @user_repo1 = create(:repository, owner: @user, force_user_owned: true)
      @user_repo2 = create(:repository, owner: @user, force_user_owned: true)
    end

    setup do
      AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:feature_available?).returns(true)
      Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::SecretScanningAlert).returns(true)
      @now = Time.current
    end

    context "#perform" do
      context "organization owned repo" do
        test "calls ingestion job for legit alert payload" do
          TenantValidationHelper.expects(:should_handle_secret_scanning_alert_events?).returns(true).twice
          SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert].number == 111 && kwargs[:alert].repository_id == @repo1.id && kwargs[:alert].updated_at.to_time.utc == @now.utc }
            .once
          SecretScanningAlertsDeletionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert_numbers] == [222] && kwargs[:repository_id] == @repo2.id }
            .once

          Timecop.freeze(@now) do
            assert_query_counts(2) do
              perform_hydro_message_job({
                entity: Initialization::Type::SecretScanningAlert.serialize,
                entities_updated: [{
                  data: alert_updated_payload(repository_id: @repo1.id.to_s, alert_number: "111")
                }],
                entities_deleted: [{
                  data: alert_deleted_payload(repository_id: @repo2.id.to_s, alert_number: "222")
                }]
              }, schema: @schema, queue: @queue)
            end
          end

          refute_dogstats_increment "security_overview_analytics.event.security_feature_alerts_changed.skipped"
        end

        test "skips event if it has different feature type" do
          TenantValidationHelper.expects(:should_handle_secret_scanning_alert_events?).never
          SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never
          SecretScanningAlertsDeletionJob.expects(:perform_later).never

          perform_hydro_message_job({
            entity: "dependabot_alert",
            entities_updated: [{
              data: alert_updated_payload(repository_id: @repo1.id.to_s, alert_number: "111")
            }],
          }, schema: @schema, queue: @queue)

          assert_dogstats_increment 1, "security_overview_analytics.event.security_feature_alerts_changed.skipped", tags: ["reason:unexpected_entity_type"]
        end

        # Skipped for Enterprise since all owners are valid
        test "skips entity payload if repository owner validation fails", skip_with_all_emus: true, skip_enterprise: true do
          user_repo = create(:repository)

          SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert].number == 111 && kwargs[:alert].repository_id == @repo1.id && kwargs[:alert].updated_at.to_time.utc == @now.utc }
            .once
          SecretScanningAlertsDeletionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert_numbers] == [222] && kwargs[:repository_id] == @repo2.id }
            .never

          Timecop.freeze(@now) do
            assert_query_counts(3) do
              perform_hydro_message_job({
                entity: Initialization::Type::SecretScanningAlert.serialize,
                entities_updated: [{
                  data: alert_updated_payload(repository_id: @repo1.id.to_s, alert_number: "111")
                }],
                entities_deleted: [{
                  data: alert_deleted_payload(repository_id: user_repo.id.to_s, alert_number: "222")
                }]
              }, schema: @schema, queue: @queue)
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.event.security_feature_alerts_changed.skipped", tags: ["reason:tenant_not_in_scope"]
        end

        test "skips entity payload if it is missing required data" do
          SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert].number == 111 && kwargs[:alert].repository_id == @repo1.id && kwargs[:alert].updated_at.to_time.utc == @now.utc && kwargs[:deleted] == false }
            .never
          SecretScanningAlertsDeletionJob.expects(:perform_later).never

          query_count = TestEnv.test_with_all_emus? ? 4 : 3
          Timecop.freeze(@now) do
            assert_query_counts(query_count) do
              perform_hydro_message_job({
                entity: Initialization::Type::SecretScanningAlert.serialize,
                entities_updated: [{
                  data: {
                    "repository_id" => @repo1.id.to_s,
                    "number" => "111"
                  }
                }]
              }, schema: @schema, queue: @queue)
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.secret_scanning_alert_revision_ingestion.skipped"
        end
      end

      context "user owned repo" do
        test "skips entity if not EMU or Enterprise user", skip_with_all_emus: true, skip_enterprise: true do
          SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert].number == 111 && kwargs[:alert].repository_id == @user_repo1.id && kwargs[:alert].updated_at.to_time.utc == @now.utc }
            .never

          SecretScanningAlertsDeletionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert_numbers] == [222] && kwargs[:repository_id] == @user_repo2.id }
            .never

          Timecop.freeze(@now) do
            assert_query_counts(2) do
              perform_hydro_message_job({
                entity: Initialization::Type::SecretScanningAlert.serialize,
                entities_updated: [{
                  data: alert_updated_payload(repository_id: @user_repo1.id.to_s, alert_number: "111")
                }],
                entities_deleted: [{
                  data: alert_deleted_payload(repository_id: @user_repo2.id.to_s, alert_number: "222")
                }]
              }, schema: @schema, queue: @queue)
            end
          end

          assert_dogstats_increment 2, "security_overview_analytics.event.security_feature_alerts_changed.skipped"
        end

        test "calls ingestion job for legit alert payload" do
          if TestEnv.test_with_all_emus? || GitHub.enterprise?
            SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
              .with { |kwargs| kwargs[:alert].number == 111 && kwargs[:alert].repository_id == @user_repo1.id && kwargs[:alert].updated_at.to_time.utc == @now.utc }
              .once

            SecretScanningAlertsDeletionJob.expects(:perform_later)
              .with { |kwargs| kwargs[:alert_numbers] == [222] && kwargs[:repository_id] == @user_repo2.id }
              .once

            Timecop.freeze(@now) do
              assert_query_counts(4) do
                perform_hydro_message_job({
                  entity: Initialization::Type::SecretScanningAlert.serialize,
                  entities_updated: [{
                    data: alert_updated_payload(repository_id: @user_repo1.id.to_s, alert_number: "111")
                  }],
                  entities_deleted: [{
                    data: alert_deleted_payload(repository_id: @user_repo2.id.to_s, alert_number: "222")
                  }]
                }, schema: @schema, queue: @queue)
              end
            end

            refute_dogstats_increment "security_overview_analytics.event.security_feature_alerts_changed.skipped"
          end
        end
      end
    end

    private

    def alert_updated_payload(repository_id:, alert_number:, **kwargs)
      {
        "repository_id" => repository_id,
        "number" => alert_number,
        "created_at" => @now.rfc3339(9),
        "updated_at" => @now.rfc3339(9),
        "token_type" => "woof",
        "token_type_provider" => "any_provider",
        "slug" => "woof",
        "resolved" => "false",
        "resolution" => "1",
        "resolved_at" => @now.rfc3339(9),
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
