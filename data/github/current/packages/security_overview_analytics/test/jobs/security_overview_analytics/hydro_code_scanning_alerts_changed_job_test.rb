# typed: true
# frozen_string_literal: true

require "test_helper"
require "turboscan"

module SecurityOverviewAnalytics
  class HydroCodeScanningAlertsChangedJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers
    include DogstatsTestHelpers

    fixtures do
      @org1 = create(:organization)
      @repo1 = create(:repository, owner: @org1)
      @org2 = create(:organization)
      @repo2 = create(:repository, owner: @org2)
    end

    setup do
      @queue = HydroCodeScanningAlertsChangedJob.queue_name
      @schema = "github.security_center.v0.InsightsEntityBatch"
      @now = Time.current
      @date_id = ::SecurityOverviewAnalytics::Date.id_from_time(@now.utc)

      TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
      Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::CodeScanningAlert).returns(true)
    end

    context "#perform" do
      test "it enqueues ingestion job for each alert in payload" do
        TenantValidationHelper.expects(:should_handle_code_scanning_alert_events?).returns(true).twice
        CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
          .with { |kwargs| kwargs[:alert].id == 111 && kwargs[:alert].repository_id == @repo1.id && !kwargs[:alert].has_autofix }
          .once
        CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
          .with { |kwargs| kwargs[:alert].id == 112 && kwargs[:alert].repository_id == @repo1.id && kwargs[:alert].has_autofix && kwargs[:alert].autofix_accepted }
          .once
        CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
          .with { |kwargs| kwargs[:alert].id == 222 && kwargs[:alert].repository_id == @repo2.id }
          .once

        Timecop.freeze(@utc_now) do
          assert_query_counts(2) do
            perform_hydro_message_job({
              entity: Initialization::Type::CodeScanningAlert.serialize,
              entities_updated: [{
                data: alert_hash(
                  id: "111",
                  repository_id: @repo1.id.to_s,
                ),
              }, {
                data: alert_hash(
                  id: "112",
                  repository_id: @repo1.id.to_s,
                  has_autofix: "true",
                  autofix_accepted: "true",
                ),
              }],
              entities_deleted: [{
                data: alert_hash(
                  id: "222",
                  repository_id: @repo2.id.to_s,
                )
              }]
            }, schema: @schema, queue: @queue)
          end
        end

        refute_dogstats_increment "security_overview_analytics.event.security_feature_alerts_changed.skipped"
      end

      context "when payload is for unsupported entity type" do
        test "it skips execution" do
          TenantValidationHelper.expects(:should_handle_code_scanning_alert_events?).never
          CodeScanningAlertRevisionIngestionJob.expects(:perform_later).never

          perform_hydro_message_job({
            entity: "dependabot_alert",
            entities_updated: [{
              data: alert_hash(
                repository_id: @repo1.id.to_s
              )
            }]
          }, schema: @schema, queue: @queue)

          assert_dogstats_increment 1, "security_overview_analytics.event.security_feature_alerts_changed.skipped", tags: ["reason:unexpected_entity_type"]
        end
      end

      context "when tenant is not in scope" do
        test "it does not enqueue alert job" do
          user_repo = create(:repository)

          CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert].id == 111 && kwargs[:alert].repository_id == @repo1.id }
            .once
          CodeScanningAlertRevisionIngestionJob.expects(:perform_later)
            .with { |kwargs| kwargs[:alert].id == 222 && kwargs[:alert].repository_id == user_repo.id }
            .never

          Timecop.freeze(@utc_now) do
            assert_query_counts(2) do
              perform_hydro_message_job({
                entity: Initialization::Type::CodeScanningAlert.serialize,
                entities_updated: [{
                  data: alert_hash(
                    id: "111",
                    repository_id: @repo1.id.to_s,
                  )
                }],
                entities_deleted: [{
                  data: alert_hash(
                    id: "222",
                    repository_id: user_repo.id.to_s,
                  )
                }]
              }, schema: @schema, queue: @queue)
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.event.security_feature_alerts_changed.skipped", tags: ["reason:tenant_not_in_scope"]
        end
      end
    end

    private

    def alert_hash(**kwargs)
      {
        "id" => "0",
        "number" => "0",
        "repository_id" => "0",
        "created_at" => @now.rfc3339(9),
        "closed_at" => "",
        "updated_at" => @now.rfc3339(9),
        "closed" => "false",
        "resolution" => "0",
        "rule_name" => "Cross-Site Scripting",
        "rule_sarif_identifier" => "rb/xss",
        "tool_name" => "CodeQL",
        "severity" => "3",
        "present_on_default_ref" => "false",
        "source_time" => @now.rfc3339(9),
        "has_autofix" => "false",
        "autofix_accepted" => "false",
        **kwargs
      }.stringify_keys
    end
  end
end
