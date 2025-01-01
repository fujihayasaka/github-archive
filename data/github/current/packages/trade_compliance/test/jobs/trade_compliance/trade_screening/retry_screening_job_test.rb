# typed: true
# frozen_string_literal: true

require "test_helper"

module TradeCompliance::TradeScreening
  class RetryScreeningJobTest < GitHub::TestCase
    include HydroTestHelpers
    include TradeScreeningTestHelpers

    setup do
      skip unless GitHub.billing_enabled?
      enable_feature_flag(:live_sdn_screening)
    end

    test "enqueued into trade_screening queue with retry status" do
      upp = create(:account_screening_profile, :with_retry_status)
      assert_enqueued_jobs(1, only: RetryScreeningJob, queue: :trade_screening) do
        RetryScreeningJob.perform_later(upp)
      end
    end

    test "enqueued into trade_screening queue with error status" do
      upp = create(:account_screening_profile, :with_error_status)
      assert_enqueued_jobs(1, only: RetryScreeningJob, queue: :trade_screening) do
        RetryScreeningJob.perform_later(upp)
      end
    end

    test "reports to dogstats if job fails" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      ApiService.stubs(:request_trade_screening).raises(ApiServiceError)

      upp = create(:account_screening_profile, :with_retry_status)
      RetryScreeningJob.perform_now(upp)

      assert_equal 1, stats.increments("sdn_api_service.screened.retry.failed").count
    end

    test "saves new status and reports to dogstats if job succeeds" do
      upp = create(:account_screening_profile, :with_retry_status)
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      live_response = LiveResponse.new(external_uuid: upp.external_uuid, eid: SecureRandom.uuid, status: "no_hit", status_reason: "")
      ApiService.stubs(:request_trade_screening).returns(live_response)

      RetryScreeningJob.perform_now(upp)

      expected_tags = [
        "status:no_hit",
      ]
      assert_equal 1, stats.increments("sdn_trade_screening_retry_job.success", tags: expected_tags).count

      upp.reload
      assert_equal "no_hit", upp.msft_trade_screening_status
    end

    test "it publishes hydro event on successful request" do
      ts_record = create(:account_screening_profile)
      eid = "d60756eb-bd19-4013-GTHB-1SSINDTST201"

      live_response = LiveResponse.new(external_uuid: ts_record.external_uuid, eid: eid, status: "hit_in_review", status_reason: "")
      ApiService.stubs(:request_trade_screening).returns(live_response)
      RetryScreeningJob.perform_now(ts_record)


      assert_hydro_published({
        country: ts_record.country_code,
        external_user_id: ts_record.external_uuid,
        request_id: eid,
        request_type: "LIVE",
        status: "hit_in_review",
        actor_type: "USER"
      }, schema: "github.trade_screening.v0.TradeScreeningResult")
    end

    test "saves status reason when provided" do
      upp = create(:account_screening_profile, :with_retry_status)

      live_response = LiveResponse.new(external_uuid: upp.external_uuid, eid: SecureRandom.uuid, status: "ingestion_error", status_reason: "bad data")
      ApiService.stubs(:request_trade_screening).returns(live_response)

      RetryScreeningJob.perform_now(upp)

      upp.reload
      assert_equal "ingestion_error", upp.msft_trade_screening_status
      assert_equal upp.screening_status_reason, "ingestion_error: bad data"
    end

    test "updates last_trade_screen_date if job succeeds" do
      upp = create(:account_screening_profile, :with_retry_status)
      assert_nil upp.last_trade_screen_date

      current_time = Time.new(2020, 11, 25, 1, 0, 0).utc
      Timecop.freeze(current_time) do
        screening_request = build_screening_request(screening_profile: upp)
        request_body = screening_request.to_hash
        live_response = LiveResponse.parse(response: {
          ScrRespEnv: {
            EId: request_body[:ScrReqsEnv][:EId],
            DT: request_body[:ScrReqsEnv][:DT],
            SummResult: "Hit in Review",
            ScrResps: {
              ScrResp: [
                {
                  ReqID: "IndName_IndAddr",
                  ExternalRefID: request_body[:ScrReqsEnv][:ExternalRefID],
                  Result: "Hit in Review",
                  ResultDesc: "",
                  Type: "Address",
                  Errs: {
                    Err: [
                      {
                        ErrCode: "",
                        ErrDesc: ""
                      }
                    ]
                  }
                }
              ]
            }
          }
        })

        ApiService.stubs(:request_trade_screening).returns(live_response)
        RetryScreeningJob.perform_now(upp)
      end

      upp.reload
      assert_equal upp.last_trade_screen_date, current_time
    end

    test "saves new status for CToS org, business and reports to dogstats if job succeeds" do
      asp = create(:account_screening_profile, :with_corporate_org, :with_retry_status)
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      live_response = LiveResponse.new(external_uuid: asp.external_uuid, eid: SecureRandom.uuid, status: "no_hit", status_reason: "")
      ApiService.stubs(:request_trade_screening).returns(live_response)

      RetryScreeningJob.perform_now(asp)

      expected_tags = [
        "status:no_hit",
      ]
      assert_equal 1, stats.increments("sdn_trade_screening_retry_job.success", tags: expected_tags).count

      asp.reload
      assert_equal "no_hit", asp.msft_trade_screening_status
    end

    test "reports to dogstats if new status returned is not valid" do
      upp = create(:account_screening_profile, :with_retry_status)
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      live_response = LiveResponse.new(external_uuid: upp.external_uuid, eid: SecureRandom.uuid, status: "some_random_status", status_reason: nil)
      ApiService.stubs(:request_trade_screening).returns(live_response)

      RetryScreeningJob.perform_now(upp)

      expected_tags = [
        "reason:'some_random_status' is not a valid msft_trade_screening_status",
      ]
      assert_equal 1, stats.increments("sdn_api_service.screened.retry.failed", tags: expected_tags).count
    end
  end
end
