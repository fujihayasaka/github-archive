# typed: true
# frozen_string_literal: true

require "test_helper"

module TradeCompliance::TradeScreening
  class ScreeningStatusSlaCheckJobTest < GitHub::TestCase
    include DogstatsTestHelpers

    setup do
      skip unless GitHub.billing_enabled?
      enable_feature_flag(:live_sdn_screening)

      # test should continue as if the profile was still hit in review
      set_rescreen_response_status("hit_in_review")
    end

    def set_rescreen_response_status(status)
      response = LiveResponse.new(external_uuid: "", eid: "", status: status, status_reason: "")
      ApiService.stubs(:make_live_request).returns(response)
    end

    test "enqueues ScreeningStatusSlaCheckJob with correct arguments" do
      upp = create(:account_screening_profile)
      Timecop.freeze(Time.now) do
        assert_enqueued_with(job: ScreeningStatusSlaCheckJob, args: [upp.id], at: 3.days.from_now.utc) do
          upp.hit_in_review!
        end
      end
    end

    test "enqueues ScreeningStatusSlaCheckJob for every user with hit_in_review" do
      create(:account_screening_profile, msft_trade_screening_status: "hit_in_review")
      create(:account_screening_profile, msft_trade_screening_status: "hit_in_review")

      assert_enqueued_jobs(2, only: ScreeningStatusSlaCheckJob)
    end

    test "count of SLA breach is not incremented when job is executed and user is in hit_in_review for 1 day" do
      upp = create(:account_screening_profile, :hit_in_review, last_trade_screen_date: 1.day.ago)
      assert_enqueued_jobs(1, only: ScreeningStatusSlaCheckJob)

      perform_enqueued_jobs(only: ScreeningStatusSlaCheckJob)

      assert_dogstats_increment(0, "sdn.status.sla_breached", tags: ["status:hit_in_review"])
    end

    test "sends SLA breach email to the trade help team when user has been in hit_in_review for 3 days" do
      Timecop.freeze(Time.new(2020, 4, 1, 0, 0, 0).utc) do
        upp = create(:account_screening_profile, :hit_in_review, last_trade_screen_date: 3.days.ago - 1.second)
        assert_enqueued_jobs(1, only: ScreeningStatusSlaCheckJob)

        assert_difference "ActionMailer::Base.deliveries.count", 1 do
          assert_performed_email(mailer: "TradeScreeningMailer", action: "trade_screening_48_hour_sla_breach", args: [upp.external_uuid]) do
            perform_enqueued_jobs(only: ScreeningStatusSlaCheckJob)
          end
        end

        assert_enqueued_jobs(0, only: ScreeningStatusSlaCheckJob)
        assert_dogstats_increment(1, "sdn.status.sla_breached", tags: ["status:hit_in_review"])
      end
    end

    test "count of SLA breach is incremented when job is executed at end of month and user is in hit_in_review for 3 days" do
      upp = create(:account_screening_profile, msft_trade_screening_status: "not_screened")
      Timecop.freeze(Time.local(2020, 12, 31)) do
        upp.hit_in_review!
      end

      assert_enqueued_jobs(1, only: ScreeningStatusSlaCheckJob)

      assert_difference "ActionMailer::Base.deliveries.count", 1 do
        assert_performed_email(mailer: "TradeScreeningMailer", action: "trade_screening_48_hour_sla_breach", args: [upp.external_uuid]) do
          perform_enqueued_jobs(only: ScreeningStatusSlaCheckJob)
        end
      end

      assert_enqueued_jobs(0, only: ScreeningStatusSlaCheckJob)
      assert_dogstats_increment(1, "sdn.status.sla_breached", tags: ["status:hit_in_review"])
    end

    test "does not send SLA breach email if user is rescreened and resolves to not no_hit" do
      upp = create(:account_screening_profile, :hit_in_review, last_trade_screen_date: 3.days.ago)
      assert_enqueued_jobs(1, only: ScreeningStatusSlaCheckJob)
      set_rescreen_response_status("no_hit")

      assert_no_difference "ActionMailer::Base.deliveries.count" do
        perform_enqueued_jobs(only: ScreeningStatusSlaCheckJob)
      end

      assert_dogstats_increment(0, "sdn.status.sla_breached", tags: ["status:hit_in_review"])
    end

    test "does not rescreen or send SLA breach email if user is no longer in hit_in_review status" do
      upp = create(:account_screening_profile, :hit_in_review, last_trade_screen_date: 4.days.ago)
      upp.no_hit!

      assert_enqueued_jobs(1, only: ScreeningStatusSlaCheckJob)
      ApiService.expects(:make_live_request).never

      assert_no_difference "ActionMailer::Base.deliveries.count" do
        perform_enqueued_jobs(only: ScreeningStatusSlaCheckJob)
      end

      assert_dogstats_increment(0, "sdn.status.sla_breached", tags: ["status:hit_in_review"])
      assert_enqueued_jobs(0, only: ScreeningStatusSlaCheckJob)
    end
  end
end
