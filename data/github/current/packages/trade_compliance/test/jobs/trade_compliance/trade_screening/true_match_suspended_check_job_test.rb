# typed: true
# frozen_string_literal: true

require "test_helper"

module TradeCompliance::TradeScreening
  class TrueMatchSuspendedCheckJobTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      skip unless GitHub.billing_enabled?
      # this job no longer makes sense/should be run with the new true match experience
      disable_feature_flag(:improved_controls_for_true_match)
    end

    test "enqueues TrueMatchSuspendedCheckJob with correct arguments" do
      upp = create(:account_screening_profile)
      Timecop.freeze(Time.now) do
        assert_enqueued_with(job: TrueMatchSuspendedCheckJob, args: [upp.id], at: 7.days.from_now.utc) do
          upp.true_match!
        end
      end
    end

    test "enqueues TrueMatchSuspendedCheckJob for every user with true_match" do
      create(:account_screening_profile, :true_match)
      create(:account_screening_profile, :true_match)
      create(:account_screening_profile, :hit_in_review)
      create(:account_screening_profile, :no_hit)

      assert_enqueued_jobs(2, only: TrueMatchSuspendedCheckJob)
    end

    test "enqueues TrueMatchSuspendedCheckJob for business owned profiles" do
      upp = create(:account_screening_profile, :with_business, :true_match)

      assert_enqueued_jobs(1, only: TrueMatchSuspendedCheckJob)
    end

    test "count of not suspended is not incremented when job is executed and user is not in true match" do
      upp = create(:account_screening_profile, :no_hit, last_trade_screen_date: 8.days.ago)

      TrueMatchSuspendedCheckJob.perform_now(upp.id)
      assert_dogstats_increment(0, "sdn.status.not_suspended", tags: ["status:true_match"])
    end

    test "count of not suspended is not incremented when job is executed and user is already sdn suspended" do
      user = create(:suspended_user)
      upp = create(:account_screening_profile, :true_match, owner: user)

      TrueMatchSuspendedCheckJob.perform_now(upp.id)
      assert_dogstats_increment(0, "sdn.status.not_suspended", tags: ["status:true_match"])
    end

    test "count of not suspended is not incremented when job is executed and user is in true_match for 1 day" do
      upp = create(:account_screening_profile, :true_match, last_trade_screen_date: 1.day.ago)

      TrueMatchSuspendedCheckJob.perform_now(upp.id)
      assert_dogstats_increment(0, "sdn.status.not_suspended", tags: ["status:true_match"])
    end

    test "count of not suspended is incremented when job is executed and user is in true_match for over 7 days" do
      upp = create(:account_screening_profile, :true_match, last_trade_screen_date: 8.days.ago)

      TrueMatchSuspendedCheckJob.perform_now(upp.id)
      assert_dogstats_increment(1, "sdn.status.not_suspended", tags: ["status:true_match"])
    end

    test "count of not suspended is incremented when job is executed and profile owner is stos org" do
      org = create(:organization)
      org.terms_of_service.update(type: "Standard", actor: org.admins.first)
      upp = create(:account_screening_profile, :true_match, owner: org, last_trade_screen_date: 8.days.ago)

      TrueMatchSuspendedCheckJob.perform_now(upp.id)
      assert_dogstats_increment(1, "sdn.status.not_suspended", tags: ["status:true_match"])
    end

    test "count of not suspended is incremented when job is executed and profile owner is ctos org" do
      org = create(:organization)
      org.terms_of_service.update(type: "Corprate", actor: org.admins.first)
      upp = create(:account_screening_profile, :true_match, owner: org, last_trade_screen_date: 8.days.ago)

      TrueMatchSuspendedCheckJob.perform_now(upp.id)
      assert_dogstats_increment(1, "sdn.status.not_suspended", tags: ["status:true_match"])
    end
  end
end
