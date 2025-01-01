# typed: true
# frozen_string_literal: true

require "test_helper"

class LeadSignalSubscriberTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @copilot_seat = create(:copilot_seat)
  end

  setup do
    @copilot_user = Copilot::User.new(@user)
  end

  test "copilot_trial_conversion enqueues a lead ingestion purchase signal" do
    assert_enqueued_with(job: LeadIngestionSubmissionJob, args: [{
      email: @copilot_user.user_object.email,
      cDLProgramName: "CO-GHAI-Self-Service-Purchase-FY24-10Oct-30-CoPilot",
    }]) do
      GlobalInstrumenter.instrument("copilot.trial_subscription_converts", {
        copilot_user: @copilot_user,
        subscription_plan: "some-plan",
      })
    end
  end

  test "copilot_trial_conversion enqueues a lead ingestion trial end signal" do
    assert_enqueued_with(job: LeadIngestionSubmissionJob, args: [{
      email: @copilot_user.user_object.email,
      cDLProgramName: GitHub.copilot_trial_cancel_campaign_id,
      gitHubLastSFDCCampaignStatus: GitHub.copilot_trial_sf_status,
    }]) do
      GlobalInstrumenter.instrument("copilot.trial_subscription_converts", {
        copilot_user: @copilot_user,
        subscription_plan: "some-plan",
      })
    end
  end

  test "copilot_subscription_cancellation enqueues a lead ingestion trial end signal" do
    assert_enqueued_with(job: LeadIngestionSubmissionJob, args: [{
      email: @copilot_user.user_object.email,
      cDLProgramName: GitHub.copilot_trial_cancel_campaign_id,
      gitHubLastSFDCCampaignStatus: GitHub.copilot_trial_sf_status,
    }]) do
      GlobalInstrumenter.instrument("copilot.subscription_cancelled", {
        copilot_user: @copilot_user,
        subscription_plan: "some-plan",
        in_trial: true,
      })
    end
  end

  test "copilot_cfb_individual_seat_conversion enqueues a lead ingestion trial end signal" do
    assert_enqueued_with(job: LeadIngestionSubmissionJob, args: [{
      email: @copilot_seat.assigned_user.email,
      cDLProgramName: GitHub.copilot_trial_cancel_campaign_id,
      gitHubLastSFDCCampaignStatus: GitHub.copilot_trial_sf_status,
    }]) do
      GlobalInstrumenter.instrument("copilot.cfb_individual_seat_converted", {
        user: @copilot_seat.assigned_user,
        subscription_item_id: 1,
        subscription_item_duration: "2 weeks",
        seat: @copilot_seat,
        details: {},
      })
    end
  end
end
