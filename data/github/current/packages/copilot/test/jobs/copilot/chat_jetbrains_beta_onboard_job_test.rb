# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::ChatJetbrainsBetaOnboardJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    # Mimicks adding early_access_enabled group to the copilot_chat_jetbrains feature flag
    GitHub.flipper[:copilot_chat_jetbrains].enable_group("early_access_enabled")
    GitHub.flipper[:copilot_communication_opt_out].disable
    @user = create(:user, :verified)
    @membership = create(:early_access_membership,
      member: @user,
      actor: @user,
      feature_slug: "copilot_chat_jetbrains",
      feature_enabled: false
    )
    @other_user = create(:user, :verified)

    GitHub.flipper[:copilot_chat_jetbrains].disable(@user)
    GitHub.flipper[:copilot_chat_jetbrains].disable(@other_user)

    @already_enrolled_user = create(:user, :verified)
    @existing_membership = create(:early_access_membership,
      member: @already_enrolled_user,
      actor: @already_enrolled_user,
      feature_slug: "copilot_chat_jetbrains",
      feature_enabled: true
    )
    GitHub.flipper[:copilot_chat_jetbrains].enable(@already_enrolled_user)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "flips the feature flag for eligible users" do
    refute GitHub.flipper[:copilot_chat_jetbrains].enabled?(@user)
    refute GitHub.flipper[:copilot_chat_jetbrains].enabled?(@other_user)
    assert GitHub.flipper[:copilot_chat_jetbrains].enabled?(@already_enrolled_user)
    assert @existing_membership.feature_enabled?

    GlobalInstrumenter.expects(:instrument).once.with(
      "user.beta_feature.enroll",
      equals(actor: @user,
        action: "enroll",
        feature: "copilot_chat_jetbrains",
      )
    )

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Copilot::ChatJetbrainsBetaOnboardJob.perform_now([
        @user.login, @other_user.login, @already_enrolled_user.login
      ])
    end

    assert @membership.reload.feature_enabled?
    assert @existing_membership.reload.feature_enabled?
    assert GitHub.flipper[:copilot_chat_jetbrains].enabled?(@user)

    # does not have corresponding EarlyAccessMembership record
    refute GitHub.flipper[:copilot_chat_jetbrains].enabled?(@other_user)

    assert_equal(ActionMailer::Base.deliveries.length, 1)
    mail = ActionMailer::Base.deliveries[0]
    assert_match(/You have been granted access/, mail.subject)
    assert_includes(mail.to, @user.email)

    assert_equal 1, GitHub.dogstats.increments("copilot.chat_jetbrains_beta.onboard").length
  end

  test "marks feature_enabled true for a batch of users if batch_size is set" do
    10.times do
      user = create(:user, :verified)
      create(:early_access_membership,
        member: user,
        actor: user,
        feature_slug: "copilot_chat_jetbrains",
        feature_enabled: false
      )
    end

    Copilot::Authorizer.any_instance.stubs(:access_allowed?).returns(true)
    Copilot::User.any_instance.stubs(:has_cfb_access?).returns(false)

    assert_equal EarlyAccessMembership.copilot_chat_jetbrains_waitlist.where(feature_enabled: true).count, 1 # the one from fixtures

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Copilot::ChatJetbrainsBetaOnboardJob.perform_now([], batch_size: 2)
    end

    assert_equal EarlyAccessMembership.copilot_chat_jetbrains_waitlist.where(feature_enabled: true).count, 3
    assert_equal(ActionMailer::Base.deliveries.length, 2)
    assert_equal 2, GitHub.dogstats.increments("copilot.chat_jetbrains_beta.onboard").length

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Copilot::ChatJetbrainsBetaOnboardJob.perform_now([], batch_size: 2)
    end

    assert_equal EarlyAccessMembership.copilot_chat_jetbrains_waitlist.where(feature_enabled: true).count, 5
    assert_equal(ActionMailer::Base.deliveries.length, 4)
    assert_equal 4, GitHub.dogstats.increments("copilot.chat_jetbrains_beta.onboard").length

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Copilot::ChatJetbrainsBetaOnboardJob.perform_now([], batch_size: 1000)
    end

    assert_equal EarlyAccessMembership.copilot_chat_jetbrains_waitlist.where(feature_enabled: true).count, 12
    assert_equal 11, GitHub.dogstats.increments("copilot.chat_jetbrains_beta.onboard").length
    assert_equal(ActionMailer::Base.deliveries.length, 11)

  end

  test "if batch_size is set, ignores CfB users" do
    2.times do
      user = create(:user, :verified)
      create(:early_access_membership,
        member: user,
        actor: user,
        feature_slug: "copilot_chat_jetbrains",
        feature_enabled: false
      )
    end

    Copilot::Authorizer.any_instance.stubs(:access_allowed?).returns(true)
    Copilot::User.any_instance.stubs(:has_cfb_access?).returns(true)

    assert_equal EarlyAccessMembership.copilot_chat_jetbrains_waitlist.where(feature_enabled: true).count, 1 # the one from fixtures

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Copilot::ChatJetbrainsBetaOnboardJob.perform_now([], batch_size: 2)
    end

    assert_operator GitHub.dogstats.increments("copilot.chat_jetbrains_beta.onboard_blocked").length, :>=, 2

    assert_equal EarlyAccessMembership.copilot_chat_jetbrains_waitlist.where(feature_enabled: true).count, 1
    assert_equal(ActionMailer::Base.deliveries.length, 0)
  end
end if GitHub.copilot_enabled?
