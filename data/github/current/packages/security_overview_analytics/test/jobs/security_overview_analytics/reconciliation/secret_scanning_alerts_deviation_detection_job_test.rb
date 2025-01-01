# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "secret_scanning_proto"

module SecurityOverviewAnalytics
  module Reconciliation
    class SecretScanningAlertsDeviationDetectionJobTest < GitHub::TestCase
      include DogstatsTestHelpers
      include JobTestHelper

      SecretScanningAlert = ::GitHub::Proto::SecretScanning::Metrics::V1::Alert
      SecretScanningBackfillResponse = ::GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequestResponse

      fixtures do
        @biz = create(:business)
        @org = create(:organization, business: @biz)
        @repo = create(:repository, owner: @org, name: "foo")
        @user = create(:user, business: @biz)
        @user_repo = create(:repository, force_user_owned: true)
        @soa_repo = create(:security_overview_analytics_repository, repository: @repo)
        @soa_user_repo = create(:security_overview_analytics_repository, repository: @user_repo)
      end

      setup do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::SecretScanningAlert).returns(true)
        # Stub session to imitate a locked session, otherwise tests would bail the after_perform block because
        # session_started_at and last_session_started_at are both nil.
        Session.any_instance.stubs(:session_started_at).returns(Time.now.utc)
        @stats_tags = ["metric_type:secret_scanning_alerts"].compact

        if GitHub.enterprise?
          SecurityCenter::SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(true)
        end
      end

      context "#perform" do
        context "owner is an organiztion" do
          context "when last_session_started_at not provided" do
            test "upsert alert revision if it is missing" do
              a_week_ago = 1.week.ago.to_time
              now = Time.now

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: a_week_ago,
                      updated_at: a_week_ago
                    }),
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == now.utc }
                .once
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == a_week_ago.utc }
                .once

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                    )
                  end
                end
              end

              assert_dogstats_increment 2, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_revision"]
              assert_dogstats_count 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_repository"]
            end

            test "updates alert revision if deviation found" do
              a_week_ago = 1.week.ago.to_time
              now = Time.now
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                alert_type: "alert_type",
                alert_type_provider: "alert_type_provider",
                alert_type_slug: "alert_type_slug",
                alert_resolved: false,
                alert_created_at: a_week_ago,
                alert_updated_at: now,
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      token_type: "alert_type",
                      token_type_provider: "alert_type_provider",
                      slug: "alert_type_slug",
                      resolved: true,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == now.utc && kwargs[:force_rewrite] == true }
                .once

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                    )
                  end
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:alert_resolved"]
            end

            test "skips fake initial revision if it has later revision exceeds retention limit" do
              updated_at = (Date::RETENTION_DURATION.ago - 1.day).to_time
              created_at = (updated_at - 1.day).to_time

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: created_at,
                      updated_at: created_at
                    }),
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: created_at,
                      updated_at: updated_at
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == created_at.utc }
                .never
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == updated_at.utc }
                .once

              perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                assert_nothing_raised do
                  SecretScanningAlertsDeviationDetectionJob.perform_later(
                    organization_id: @org.id,
                    repository_id: @repo.id,
                  )
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.alert_skipped", tags: @stats_tags + ["reason:exceeds_retention_limit"]
              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_revision"]
              assert_dogstats_count 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_repository"]
            end

            test "skips alert if analytics revision has later updated_at timestamp" do
              a_week_ago = 1.week.ago.to_time
              now = Time.now
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                alert_type: "alert_type",
                alert_type_provider: "alert_type_provider",
                alert_type_slug: "alert_type_slug",
                alert_resolved: false,
                alert_created_at: a_week_ago,
                alert_updated_at: now + 1.hour, # later timestamp in Analytics
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      token_type: "alert_type",
                      token_type_provider: "alert_type_provider",
                      slug: "alert_type_slug",
                      resolved: true,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                    )
                  end
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.alert_skipped", tags: @stats_tags + ["reason:old_source_alert_timestamp"]
              refute_dogstats_increment "security_overview_analytics.reconciliation.deviation"
            end

            test "skips alert in analytics revision if it is fake initial revision" do
              a_week_ago = 1.week.ago.to_time
              now = Time.now
              now_date_id = ::SecurityOverviewAnalytics::Date.id_from_time(now.utc)
              initial_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                alert_type: "alert_type",
                alert_type_provider: "alert_type_provider",
                alert_type_slug: "alert_type_slug",
                alert_resolved: true,
                alert_resolution: 2,
                alert_validity: 0,
                alert_resolved_at: a_week_ago,
                alert_created_at: a_week_ago,
                alert_updated_at: a_week_ago,
                date: create(:security_overview_analytics_date, date_value: a_week_ago),
                next_revision_date_id: now_date_id
              )
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                alert_type: "alert_type",
                alert_type_provider: "alert_type_provider",
                alert_type_slug: "alert_type_slug",
                alert_resolved: false,
                alert_resolution: 5,
                alert_validity: 0,
                alert_created_at: a_week_ago,
                alert_updated_at: now,
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      token_type: "alert_type",
                      token_type_provider: "alert_type_provider",
                      slug: "alert_type_slug",
                      resolved: false,
                      created_at: a_week_ago,
                      updated_at: a_week_ago
                    }),
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      token_type: "alert_type",
                      token_type_provider: "alert_type_provider",
                      slug: "alert_type_slug",
                      resolved: false,
                      resolution: :REOPENED,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                    )
                  end
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.alert_skipped", tags: @stats_tags + ["reason:ignore_fake_initial_revision"]
            end

            test "removes alert if it is a low confidence one" do
              a_week_ago = 1.week.ago.to_time
              now = Time.now
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      low_confidence: true,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertsDeletionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:repository_id] == @repo.id && kwargs[:alert_numbers] == [1] }
                .once

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                    )
                  end
                end
              end

              assert_dogstats_count 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:low_confidence_alerts"]
            end

            test "removes orphaned alert if API returns no alerts" do
              now = Time.now
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: []
                })
              ))
              SecretScanningAlertsDeletionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:repository_id] == @repo.id && kwargs[:alert_numbers] == [1] }
                .once

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                    )
                  end
                end
              end

              assert_dogstats_count 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:orphaned_alerts"]
            end

            test "removes orphaned alert on subsequential batch" do
              now = Time.now
              date = create(:security_overview_analytics_date, date_value: now)
              create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                date:
              )
              create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 2,
                date:
              )

              GitHub::TokenScanning::Service::Client.any_instance
                .expects(:get_alerts_for_insights_backfill)
                .with(
                  GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                    repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                    include_low_confidence: true,
                    updated_after: nil,
                    next_cursor: nil
                  }).to_h
                )
                .returns(Twirp::ClientResp.new(
                  error: nil,
                  data: SecretScanningBackfillResponse.new({
                    next_cursor: "theres_more",
                    Alerts: [SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: now,
                      updated_at: now
                    })]
                  })
                ))
              GitHub::TokenScanning::Service::Client.any_instance
                .expects(:get_alerts_for_insights_backfill)
                .with(
                  GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                    repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                    include_low_confidence: true,
                    updated_after: nil,
                    next_cursor: "theres_more"
                  }).to_h
                )
                .returns(Twirp::ClientResp.new(
                  error: nil,
                  data: SecretScanningBackfillResponse.new({
                    Alerts: [SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 3,
                      created_at: now,
                      updated_at: now
                    })]
                  })
                ))
              SecretScanningAlertsDeletionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:repository_id] == @repo.id && kwargs[:alert_numbers] == [2] }
                .once

              assert_performed_jobs 2, only: SecretScanningAlertsDeviationDetectionJob do
                assert_nothing_raised do
                  SecretScanningAlertsDeviationDetectionJob.perform_later(
                    organization_id: @repo.owner.id,
                    repository_id: @repo.id,
                  )
                end
              end

              assert_dogstats_count 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:orphaned_alerts"]
            end
          end

          context "when last_session_started_at provided" do
            test "upsert alert revision if it is missing" do
              a_week_ago = 1.week.ago.to_time
              now = Time.now

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: Google::Protobuf::Timestamp.new(seconds: (now).to_i),
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: a_week_ago,
                      updated_at: a_week_ago
                    }),
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == now.utc }
                .once
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == a_week_ago.utc }
                .once

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                      last_session_started_at: now,
                    )
                  end
                end
              end

              assert_dogstats_increment 2, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_revision"]
              refute_dogstats_increment "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_repository"]
            end

            test "updates alert revision if deviation found" do
              a_week_ago = 1.week.ago.to_time
              now = Time.now
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                alert_type: "alert_type",
                alert_type_provider: "alert_type_provider",
                alert_type_slug: "alert_type_slug",
                alert_resolved: false,
                alert_created_at: a_week_ago,
                alert_updated_at: now,
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: Google::Protobuf::Timestamp.new(seconds: (now).to_i),
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      token_type: "alert_type",
                      token_type_provider: "alert_type_provider",
                      slug: "alert_type_slug",
                      resolved: true,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == now.utc && kwargs[:force_rewrite] == true }
                .once

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                      last_session_started_at: now,
                    )
                  end
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:alert_resolved"]
            end

            test "skips fake initial revision if it has later revision exceeds retention limit" do
              updated_at = (Date::RETENTION_DURATION.ago - 1.day).to_time
              created_at = (updated_at - 1.day).to_time

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: Google::Protobuf::Timestamp.new(seconds: (created_at).to_i),
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: created_at,
                      updated_at: created_at
                    }),
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: created_at,
                      updated_at: updated_at
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == created_at.utc }
                .never
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @repo.id && kwargs[:alert].updated_at.to_time.utc == updated_at.utc }
                .once

              perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                assert_nothing_raised do
                  SecretScanningAlertsDeviationDetectionJob.perform_later(
                    organization_id: @org.id,
                    repository_id: @repo.id,
                    last_session_started_at: created_at,
                  )
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.alert_skipped", tags: @stats_tags + ["reason:exceeds_retention_limit"]
              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_revision"]
              refute_dogstats_increment "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_repository"]
            end

            test "skips alert if analytics revision has later updated_at timestamp" do
              a_week_ago = 1.week.ago.to_time
              now = Time.now
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                alert_created_at: a_week_ago,
                alert_updated_at: now + 1.hour, # later timestamp in Analytics
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: Google::Protobuf::Timestamp.new(seconds: (now).to_i),
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                      last_session_started_at: now,
                    )
                  end
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.alert_skipped", tags: @stats_tags + ["reason:old_source_alert_timestamp"]
              refute_dogstats_increment "security_overview_analytics.reconciliation.deviation"
            end

            test "skips alert in analytics revision if it is fake initial revision" do
              a_week_ago = 1.week.ago.to_time
              now = Time.now
              now_date_id = ::SecurityOverviewAnalytics::Date.id_from_time(now.utc)
              initial_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                alert_type: "alert_type",
                alert_type_provider: "alert_type_provider",
                alert_type_slug: "alert_type_slug",
                alert_resolved: true,
                alert_resolution: 2,
                alert_validity: 0,
                alert_resolved_at: a_week_ago,
                alert_created_at: a_week_ago,
                alert_updated_at: a_week_ago,
                date: create(:security_overview_analytics_date, date_value: a_week_ago),
                next_revision_date_id: now_date_id
              )
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                alert_type: "alert_type",
                alert_type_provider: "alert_type_provider",
                alert_type_slug: "alert_type_slug",
                alert_resolved: false,
                alert_resolution: 5,
                alert_validity: 0,
                alert_created_at: a_week_ago,
                alert_updated_at: now,
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: Google::Protobuf::Timestamp.new(seconds: (a_week_ago).to_i),
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      token_type: "alert_type",
                      token_type_provider: "alert_type_provider",
                      slug: "alert_type_slug",
                      resolved: false,
                      created_at: a_week_ago,
                      updated_at: a_week_ago
                    }),
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      token_type: "alert_type",
                      token_type_provider: "alert_type_provider",
                      slug: "alert_type_slug",
                      resolved: false,
                      resolution: :REOPENED,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                      last_session_started_at: a_week_ago,
                    )
                  end
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.alert_skipped", tags: @stats_tags + ["reason:ignore_fake_initial_revision"]
            end

            test "removes alert if it is a low confidence one" do
              a_week_ago = 1.week.ago.to_time
              now = Time.now
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: Google::Protobuf::Timestamp.new(seconds: (now).to_i),
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @repo.id,
                      number: 1,
                      low_confidence: true,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertsDeletionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:repository_id] == @repo.id && kwargs[:alert_numbers] == [1] }
                .once

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                      last_session_started_at: now,
                    )
                  end
                end
              end

              assert_dogstats_count 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:low_confidence_alerts"]
            end

            test "does not attempt to remove orphaned alert if API returns no alerts" do
              now = Time.now
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @repo.id,
                alert_number: 1,
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: Google::Protobuf::Timestamp.new(seconds: (now).to_i),
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: []
                })
              ))
              SecretScanningAlertsDeletionJob.expects(:perform_later).never

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                      last_session_started_at: now,
                    )
                  end
                end
              end

              refute_dogstats_increment "security_overview_analytics.reconciliation.deviation"
            end

            test "queues PostReconciliationRepoDeviationCountsJob", skip_enterprise: true do
              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                  include_low_confidence: true,
                  updated_after: Google::Protobuf::Timestamp.new(seconds: (Time.now).to_i),
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({ Alerts: [] })
              ))

              Timecop.freeze do
                assert_enqueued_with(
                  job: PostReconciliationRepoDeviationCountsJob,
                  at: 1.hour.from_now,
                ) do
                  assert_performed_jobs 1, only: SecretScanningAlertsDeviationDetectionJob do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @org.id,
                      repository_id: @repo.id,
                      last_session_started_at: Time.now,
                    )
                  end
                end
              end
            end

            test "does not queue PostReconciliationRepoDeviationCountsJob in GHES", enterprise_only: true do
              Timecop.freeze do
                assert_no_performed_jobs only: PostReconciliationRepoDeviationCountsJob do
                  SecretScanningAlertsDeviationDetectionJob.perform_later(
                    organization_id: @org.id,
                    repository_id: @repo.id,
                    last_session_started_at: Time.now,
                  )
                end
              end
            end
          end
        end

        context "owner is an EMU" do
          context "when last_session_started_at not provided" do
            test "upsert alert revision if it is missing" do
              return unless TestEnv.test_with_all_emus? || GitHub.enterprise?

              a_week_ago = 1.week.ago.to_time
              now = Time.now

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @user_repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 1,
                      created_at: a_week_ago,
                      updated_at: a_week_ago
                    }),
                    SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 1,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @user_repo.id && kwargs[:alert].updated_at.to_time.utc == now.utc }
                .once
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @user_repo.id && kwargs[:alert].updated_at.to_time.utc == a_week_ago.utc }
                .once

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      owner_id: @user.id,
                      repository_id: @user_repo.id,
                    )
                  end
                end
              end

              assert_dogstats_increment 2, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_revision"]
              assert_dogstats_count 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_repository"]
            end

            test "updates alert revision if deviation found" do
              return unless TestEnv.test_with_all_emus? || GitHub.enterprise?

              a_week_ago = 1.week.ago.to_time
              now = Time.now
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @user_repo.id,
                alert_number: 1,
                alert_type: "alert_type",
                alert_type_provider: "alert_type_provider",
                alert_type_slug: "alert_type_slug",
                alert_resolved: false,
                alert_created_at: a_week_ago,
                alert_updated_at: now,
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @user_repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 1,
                      token_type: "alert_type",
                      token_type_provider: "alert_type_provider",
                      slug: "alert_type_slug",
                      resolved: true,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @user_repo.id && kwargs[:alert].updated_at.to_time.utc == now.utc && kwargs[:force_rewrite] == true }
                .once

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @user.id,
                      repository_id: @user_repo.id,
                    )
                  end
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:alert_resolved"]
            end

            test "skips fake initial revision if it has later revision exceeds retention limit" do
              return unless TestEnv.test_with_all_emus? || GitHub.enterprise?

              updated_at = (Date::RETENTION_DURATION.ago - 1.day).to_time
              created_at = (updated_at - 1.day).to_time

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @user_repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 1,
                      created_at: created_at,
                      updated_at: created_at
                    }),
                    SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 1,
                      created_at: created_at,
                      updated_at: updated_at
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @user_repo.id && kwargs[:alert].updated_at.to_time.utc == created_at.utc }
                .never
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:alert].number == 1 && kwargs[:alert].repository_id == @user_repo.id && kwargs[:alert].updated_at.to_time.utc == updated_at.utc }
                .once

              perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                assert_nothing_raised do
                  SecretScanningAlertsDeviationDetectionJob.perform_later(
                    organization_id: @user.id,
                    repository_id: @user_repo.id,
                  )
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.alert_skipped", tags: @stats_tags + ["reason:exceeds_retention_limit"]
              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_revision"]
              assert_dogstats_count 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:missing_repository"]
            end

            test "skips alert if analytics revision has later updated_at timestamp" do
              return unless TestEnv.test_with_all_emus? || GitHub.enterprise?

              a_week_ago = 1.week.ago.to_time
              now = Time.now
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @user_repo.id,
                alert_number: 1,
                alert_type: "alert_type",
                alert_type_provider: "alert_type_provider",
                alert_type_slug: "alert_type_slug",
                alert_resolved: false,
                alert_created_at: a_week_ago,
                alert_updated_at: now + 1.hour, # later timestamp in Analytics
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @user_repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 1,
                      token_type: "alert_type",
                      token_type_provider: "alert_type_provider",
                      slug: "alert_type_slug",
                      resolved: true,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @user.id,
                      repository_id: @user_repo.id,
                    )
                  end
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.alert_skipped", tags: @stats_tags + ["reason:old_source_alert_timestamp"]
              refute_dogstats_increment "security_overview_analytics.reconciliation.deviation"
            end

            test "skips alert in analytics revision if it is fake initial revision" do
              return unless TestEnv.test_with_all_emus? || GitHub.enterprise?

              a_week_ago = 1.week.ago.to_time
              now = Time.now
              now_date_id = ::SecurityOverviewAnalytics::Date.id_from_time(now.utc)
              initial_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @user_repo.id,
                alert_number: 1,
                alert_type: "alert_type",
                alert_type_provider: "alert_type_provider",
                alert_type_slug: "alert_type_slug",
                alert_resolved: true,
                alert_resolution: 2,
                alert_validity: 0,
                alert_resolved_at: a_week_ago,
                alert_created_at: a_week_ago,
                alert_updated_at: a_week_ago,
                date: create(:security_overview_analytics_date, date_value: a_week_ago),
                next_revision_date_id: now_date_id
              )
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @user_repo.id,
                alert_number: 1,
                alert_type: "alert_type",
                alert_type_provider: "alert_type_provider",
                alert_type_slug: "alert_type_slug",
                alert_resolved: false,
                alert_resolution: 5,
                alert_validity: 0,
                alert_created_at: a_week_ago,
                alert_updated_at: now,
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @user_repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 1,
                      token_type: "alert_type",
                      token_type_provider: "alert_type_provider",
                      slug: "alert_type_slug",
                      resolved: false,
                      created_at: a_week_ago,
                      updated_at: a_week_ago
                    }),
                    SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 1,
                      token_type: "alert_type",
                      token_type_provider: "alert_type_provider",
                      slug: "alert_type_slug",
                      resolved: false,
                      resolution: :REOPENED,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertRevisionIngestionJob.expects(:perform_later).never

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @user.id,
                      repository_id: @user_repo.id,
                    )
                  end
                end
              end

              assert_dogstats_increment 1, "security_overview_analytics.reconciliation.alert_skipped", tags: @stats_tags + ["reason:ignore_fake_initial_revision"]
            end

            test "removes alert if it is a low confidence one" do
              return unless TestEnv.test_with_all_emus? || GitHub.enterprise?

              a_week_ago = 1.week.ago.to_time
              now = Time.now
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @user_repo.id,
                alert_number: 1,
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @user_repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: [
                    SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 1,
                      low_confidence: true,
                      created_at: a_week_ago,
                      updated_at: now
                    })
                  ]
                })
              ))
              SecretScanningAlertsDeletionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:repository_id] == @user_repo.id && kwargs[:alert_numbers] == [1] }
                .once

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @user.id,
                      repository_id: @user_repo.id,
                    )
                  end
                end
              end

              assert_dogstats_count 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:low_confidence_alerts"]
            end

            test "removes orphaned alert if API returns no alerts" do
              return unless TestEnv.test_with_all_emus? || GitHub.enterprise?

              now = Time.now
              current_revision = create(
                :soa_secret_scanning_alert_revision,
                repository_id: @user_repo.id,
                alert_number: 1,
                date: create(:security_overview_analytics_date, date_value: now)
              )

              GitHub::TokenScanning::Service::Client.any_instance.expects(:get_alerts_for_insights_backfill).with(
                GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                  repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @user_repo.id),
                  include_low_confidence: true,
                  updated_after: nil,
                  next_cursor: nil
                }).to_h
              ).returns(Twirp::ClientResp.new(
                error: nil,
                data: SecretScanningBackfillResponse.new({
                  Alerts: []
                })
              ))
              SecretScanningAlertsDeletionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:repository_id] == @user_repo.id && kwargs[:alert_numbers] == [1] }
                .once

              Timecop.freeze(now) do
                perform_enqueued_jobs only: SecretScanningAlertsDeviationDetectionJob do
                  assert_nothing_raised do
                    SecretScanningAlertsDeviationDetectionJob.perform_later(
                      organization_id: @user.id,
                      repository_id: @user_repo.id,
                    )
                  end
                end
              end

              assert_dogstats_count 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:orphaned_alerts"]
            end

            test "removes orphaned alert on subsequential batch" do
              return unless TestEnv.test_with_all_emus? || GitHub.enterprise?

              now = Time.now
              date = create(:security_overview_analytics_date, date_value: now)
              create(
                :soa_secret_scanning_alert_revision,
                repository_id: @user_repo.id,
                alert_number: 1,
                date:
              )
              create(
                :soa_secret_scanning_alert_revision,
                repository_id: @user_repo.id,
                alert_number: 2,
                date:
              )

              GitHub::TokenScanning::Service::Client.any_instance
                .expects(:get_alerts_for_insights_backfill)
                .with(
                  GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                    repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @user_repo.id),
                    include_low_confidence: true,
                    updated_after: nil,
                    next_cursor: nil
                  }).to_h
                )
                .returns(Twirp::ClientResp.new(
                  error: nil,
                  data: SecretScanningBackfillResponse.new({
                    next_cursor: "theres_more",
                    Alerts: [SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 1,
                      created_at: now,
                      updated_at: now
                    })]
                  })
                ))
              GitHub::TokenScanning::Service::Client.any_instance
                .expects(:get_alerts_for_insights_backfill)
                .with(
                  GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                    repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @user_repo.id),
                    include_low_confidence: true,
                    updated_after: nil,
                    next_cursor: "theres_more"
                  }).to_h
                )
                .returns(Twirp::ClientResp.new(
                  error: nil,
                  data: SecretScanningBackfillResponse.new({
                    Alerts: [SecretScanningAlert.new({
                      repository_id: @user_repo.id,
                      number: 3,
                      created_at: now,
                      updated_at: now
                    })]
                  })
                ))
              SecretScanningAlertsDeletionJob.expects(:perform_later)
                .with { |kwargs| kwargs[:repository_id] == @user_repo.id && kwargs[:alert_numbers] == [2] }
                .once

              assert_performed_jobs 2, only: SecretScanningAlertsDeviationDetectionJob do
                assert_nothing_raised do
                  SecretScanningAlertsDeviationDetectionJob.perform_later(
                    organization_id: @user_repo.owner.id,
                    repository_id: @user_repo.id,
                  )
                end
              end

              assert_dogstats_count 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags + ["deviation:orphaned_alerts"]
            end
          end
        end
      end

      context "#around_enqueue" do
        test "raises ArgumentError if missing repository_id" do
          assert_enqueued_jobs 0, only: SecretScanningAlertsDeviationDetectionJob do
            assert_raises ArgumentError do
              SecretScanningAlertsDeviationDetectionJob.perform_later(organization_id: 1)
            end
          end
        end
      end

      context "#around_perform" do
        test "skips the perform by subsequent batch if feature is not configured on GHES", enterprise_only: true do
          SecurityCenter::SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(false)
          SecretScanningAlertsDeviationDetectionJob.any_instance.expects(:next_batch).never
          SecretScanningAlertsDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          assert_performed_jobs 1, only: SecretScanningAlertsDeviationDetectionJob do
            SecretScanningAlertsDeviationDetectionJob.perform_later(organization_id: @org.id, repository_id: @repo.id, offset_item_id: "next_cursor")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:feature_unavailable"]
        end

        test "skips the perform by subsequent batch if repo is soft-deleted" do
          SecretScanningAlertsDeviationDetectionJob.any_instance.expects(:next_batch).never
          SecretScanningAlertsDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          repo = create(:deleted_repository, owner: @org)
          assert_performed_jobs 1, only: SecretScanningAlertsDeviationDetectionJob do
            SecretScanningAlertsDeviationDetectionJob.perform_later(organization_id: repo.owner.id, repository_id: repo.id, offset_item_id: "next_cursor")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:repository_deleted"]
        end

        test "skips the perform by subsequent batch if tenant out of scope" do
          SecretScanningAlertsDeviationDetectionJob.any_instance.expects(:next_batch).never
          SecretScanningAlertsDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
          assert_performed_jobs 1, only: SecretScanningAlertsDeviationDetectionJob do
            SecretScanningAlertsDeviationDetectionJob.perform_later(organization_id: @repo.owner.id, repository_id: @repo.id, offset_item_id: "next_cursor")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:tenant_not_in_scope"]
        end

        test "skips the perform by subsequent batch if target feature no longer marked as initialized" do
          SecretScanningAlertsDeviationDetectionJob.any_instance.expects(:next_batch).never
          SecretScanningAlertsDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::SecretScanningAlert).returns(false)
          assert_performed_jobs 1, only: SecretScanningAlertsDeviationDetectionJob do
            SecretScanningAlertsDeviationDetectionJob.perform_later(organization_id: @repo.owner.id, repository_id: @repo.id, offset_item_id: "next_cursor")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:tenant_not_initialized"]
        end
      end

      context "batched job" do
        test "queues subsequent jobs" do
          now = Time.now
          GitHub::TokenScanning::Service::Client.any_instance
            .expects(:get_alerts_for_insights_backfill)
            .with(
              GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                include_low_confidence: true,
                updated_after: Google::Protobuf::Timestamp.new(seconds: now.to_i),
                next_cursor: nil
              }).to_h
            )
            .returns(Twirp::ClientResp.new(
              error: nil,
              data: SecretScanningBackfillResponse.new({
                next_cursor: "theres_more",
                Alerts: [SecretScanningAlert.new({
                  repository_id: @repo.id,
                  number: 1,
                  created_at: now,
                  updated_at: now
                })]
              })
            ))
          GitHub::TokenScanning::Service::Client.any_instance
            .expects(:get_alerts_for_insights_backfill)
            .with(
              GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequest.new({
                repo_selector: GitHub::Proto::SecretScanning::Metrics::V1::RepoSelector.new(repository_id: @repo.id),
                include_low_confidence: true,
                updated_after: Google::Protobuf::Timestamp.new(seconds: now.to_i),
                next_cursor: "theres_more"
              }).to_h
            )
            .returns(Twirp::ClientResp.new(
              error: nil,
              data: SecretScanningBackfillResponse.new({
                Alerts: [SecretScanningAlert.new({
                  repository_id: @repo.id,
                  number: 2,
                  created_at: now,
                  updated_at: now
                })]
              })
            ))

          assert_performed_jobs 2, only: SecretScanningAlertsDeviationDetectionJob do
            assert_nothing_raised do
              SecretScanningAlertsDeviationDetectionJob.perform_later(
                organization_id: @repo.owner.id,
                repository_id: @repo.id,
                last_session_started_at: now
              )
            end
          end

          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end
      end

      context "resiliency" do
        test "retries on standard conditions" do
          assert_retry_conditions(
            job: SecretScanningAlertsDeviationDetectionJob,
            args: [{ organization_id: @repo.owner.id, repository_id: @repo.id }],
            using_kwargs: true
          )
        end

        test "retries on token scanning API error" do
          GitHub::TokenScanning::Service::Client.any_instance
            .expects(:get_alerts_for_insights_backfill)
            .returns(Twirp::ClientResp.new(
              error: Twirp::Error.new(
                :invalid_argument,
                "something is wrong"
              ),
              data: nil
            ))
          assert_enqueued_with(job: SecretScanningAlertsDeviationDetectionJob, args: [{ organization_id: @repo.owner.id, repository_id: @repo.id }]) do
            SecretScanningAlertsDeviationDetectionJob.perform_now(organization_id: @repo.owner.id, repository_id: @repo.id)
          end
          assert_dogstats_increment 1,
            "security_overview_analytics.reconciliation.error",
            tags: @stats_tags + ["reason:#{SecretScanningAlertsDeviationDetectionJob::TokenScanningServiceMetricsApiError.name&.underscore}}"]
        end

        test "does not allow concurrent jobs for the same input" do
          assert_enqueued_jobs 2, only: SecretScanningAlertsDeviationDetectionJob do
            SecretScanningAlertsDeviationDetectionJob.perform_later(organization_id: @repo.owner.id, repository_id: @repo.id)
            SecretScanningAlertsDeviationDetectionJob.perform_later(organization_id: @repo.owner.id, repository_id: @repo.id)
            SecretScanningAlertsDeviationDetectionJob.perform_later(organization_id: @repo.owner.id, repository_id: @repo.id, last_session_started_at: Time.now)
          end
        end
      end
    end
  end
end
