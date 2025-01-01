# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::CodeReviewBetaOnboardJobTest < GitHub::TestCase
  include JobTestHelper
  include CopilotPublicUserCacheable

  fixtures do
    @site_admin = create :staff_admin_user
    @user = create(:user, :verified, login: "waitlisted")

    @already_enrolled_user = create(:user, :verified, login: "alreadyenrolled")
    @non_waitlisted_user = create(:user, :verified, login: "nonwaitlisted")

    @existing_membership = create(:early_access_membership,
      member: @already_enrolled_user,
      actor: @already_enrolled_user,
      feature_slug: "copilot_code_review_public_preview",
      feature_enabled: true
    )

    @membership = create(:early_access_membership,
      member: @user,
      actor: @user,
      feature_slug: "copilot_code_review_public_preview",
      feature_enabled: false
    )
  end

  setup do
    # Mimicks adding early_access_enabled group to the copilot_code_review_public_preview feature flag
    enable_feature_group(:copilot_code_review_public_preview, "early_access_enabled")
    disable_feature_flag(:copilot_code_review_public_preview, @user)
    enable_feature_flag(:copilot_code_review_public_preview, @already_enrolled_user)
    disable_feature_flag(:copilot_code_review_public_preview_skip_organization_onboarding_email)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "flips the feature flag for eligible users and creates memberships for non-waitlisted users" do
    refute GitHub.flipper[:copilot_code_review_public_preview].enabled?(@user)
    assert GitHub.flipper[:copilot_code_review_public_preview].enabled?(@already_enrolled_user)
    assert @existing_membership.feature_enabled?

    GlobalInstrumenter.expects(:instrument).once.with(
      "user.beta_feature.enroll",
      equals(actor: @user,
        member: @user,
        action: "enroll",
        feature: "copilot_code_review_public_preview",
      )
    )

    GlobalInstrumenter.expects(:instrument).once.with(
      "user.beta_feature.enroll",
      equals(actor: @site_admin,
        member: @non_waitlisted_user,
        action: "enroll",
        feature: "copilot_code_review_public_preview",
      )
    )

    Copilot::Public::User.any_instance.stubs(:has_ci_access?).returns(true)

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Copilot::CodeReviewBetaOnboardJob.perform_now([
        @user.login, @already_enrolled_user.login, @non_waitlisted_user.login
      ], actor: @site_admin)
    end

    assert @membership.reload.feature_enabled?
    assert @existing_membership.reload.feature_enabled?
    refute_nil EarlyAccessMembership.find_by(member: @non_waitlisted_user, feature_slug: "copilot_code_review_public_preview", feature_enabled: true)
    assert GitHub.flipper[:copilot_code_review_public_preview].enabled?(@user)

    assert_equal(ActionMailer::Base.deliveries.length, 2)
    mail = ActionMailer::Base.deliveries[0]
    assert_match(/You’ve been granted access/, mail.subject)
    assert_includes(mail.to, @non_waitlisted_user.email)

    mail = ActionMailer::Base.deliveries[1]
    assert_match(/You’ve been granted access/, mail.subject)
    assert_includes(mail.to, @user.email)

    assert_equal 2, GitHub.dogstats.increments("copilot.code_review_beta.onboard").length
  end

  test "flips the feature flag for eligible orgs and their eligible members" do
    assert @existing_membership.feature_enabled?

    admin = create(:user, :verified, login: "admin-#{SecureRandom.hex(4)}")
    eligible_org = create(:organization, admin: admin)
    Copilot::Organization.new(eligible_org).enable_copilot!
    seat_assignment = create(:copilot_seat_assignment, organization: eligible_org, assignable: admin, assigning_user: admin)
    seat_assignment.convert_to_seats

    ineligible_member = create(:user, :verified, login: "ineligible-#{SecureRandom.hex(4)}")

    refute GitHub.flipper[:copilot_code_review_public_preview].enabled?(admin)
    refute GitHub.flipper[:copilot_code_review_public_preview].enabled?(ineligible_member)

    eligible_org.add_member(ineligible_member)
    ineligible_org = create(:organization, admin: admin, name: "ineligible-org-#{SecureRandom.hex(4)}")

    eligible_org_membership = T.let(nil, T.nilable(EarlyAccessMembership))
    ineligible_org_membership = T.let(nil, T.nilable(EarlyAccessMembership))

    perform_enqueued_jobs(only: [InheritOrgEarlyAccessJob]) do
      eligible_org_membership = create(:early_access_membership,
        member: eligible_org,
        actor: admin,
        feature_slug: "copilot_code_review_public_preview",
        feature_enabled: false
      )

      ineligible_org_membership = create(:early_access_membership,
        member: ineligible_org,
        actor: admin,
        feature_slug: "copilot_code_review_public_preview",
        feature_enabled: false
      )
    end

    GlobalInstrumenter.expects(:instrument).once.with(
      "user.beta_feature.enroll",
      equals(actor: admin,
        member: eligible_org,
        action: "enroll",
        feature: "copilot_code_review_public_preview",
      )
    )

    GlobalInstrumenter.expects(:instrument).once.with(
      "user.beta_feature.enroll",
      equals(actor: admin,
        member: admin,
        action: "enroll",
        feature: "copilot_code_review_public_preview",
      )
    )

    Copilot.stubs(:copilot_communication_opt_out?).returns(false)

    perform_enqueued_jobs(only: [ApplicationDeliveryJob, InheritOrgEarlyAccessJob]) do
      Copilot::CodeReviewBetaOnboardJob.perform_now([
        eligible_org.login, ineligible_org.login
      ], actor: @site_admin)
    end

    assert eligible_org_membership&.reload.feature_enabled?
    refute ineligible_org_membership&.reload.feature_enabled?
    assert GitHub.flipper[:copilot_code_review_public_preview].enabled?(admin)
    refute GitHub.flipper[:copilot_code_review_public_preview].enabled?(ineligible_member)

    assert_equal(ActionMailer::Base.deliveries.length, 1)
    mail = ActionMailer::Base.deliveries[0]
    assert_match(/Your organization has been granted access/, mail.subject)
    assert_includes(mail.to, admin.email)

    assert_equal 2, GitHub.dogstats.increments("copilot.code_review_beta.onboard").length
  end

  test "flips the feature flag for eligible non-waitlisted orgs and their eligible members" do
    assert @existing_membership.feature_enabled?

    admin = create(:user, :verified, login: "admin-#{SecureRandom.hex(4)}")
    eligible_org = create(:organization, admin: admin)
    Copilot::Organization.new(eligible_org).enable_copilot!
    seat_assignment = create(:copilot_seat_assignment, organization: eligible_org, assignable: admin, assigning_user: admin)
    seat_assignment.convert_to_seats
    ineligible_member = create(:user, :verified, login: "ineligible-#{SecureRandom.hex(4)}")

    refute GitHub.flipper[:copilot_code_review_public_preview].enabled?(admin)
    refute GitHub.flipper[:copilot_code_review_public_preview].enabled?(ineligible_member)

    eligible_org.add_member(ineligible_member)
    ineligible_org = create(:organization, admin: admin, name: "ineligible-org-#{SecureRandom.hex(4)}")
    ineligible_org_membership = T.let(nil, T.nilable(EarlyAccessMembership))

    perform_enqueued_jobs(only: [InheritOrgEarlyAccessJob]) do
      ineligible_org_membership = create(:early_access_membership,
        member: ineligible_org,
        actor: admin,
        feature_slug: "copilot_code_review_public_preview",
        feature_enabled: false
      )
    end

    GlobalInstrumenter.expects(:instrument).once.with(
      "user.beta_feature.enroll",
      equals(actor: @site_admin,
        member: eligible_org,
        action: "enroll",
        feature: "copilot_code_review_public_preview",
      )
    )

    GlobalInstrumenter.expects(:instrument).once.with(
      "user.beta_feature.enroll",
      equals(actor: admin,
        member: admin,
        action: "enroll",
        feature: "copilot_code_review_public_preview",
      )
    )

    Copilot.stubs(:copilot_communication_opt_out?).returns(false)

    perform_enqueued_jobs(only: [ApplicationDeliveryJob, InheritOrgEarlyAccessJob]) do
      Copilot::CodeReviewBetaOnboardJob.perform_now([
        eligible_org.login, ineligible_org.login
      ], actor: @site_admin)
    end

    refute_nil EarlyAccessMembership.find_by(member: eligible_org, feature_slug: "copilot_code_review_public_preview", feature_enabled: true)
    refute ineligible_org_membership&.reload.feature_enabled?
    assert GitHub.flipper[:copilot_code_review_public_preview].enabled?(admin)
    refute GitHub.flipper[:copilot_code_review_public_preview].enabled?(ineligible_member)

    assert_equal(ActionMailer::Base.deliveries.length, 1)
    mail = ActionMailer::Base.deliveries[0]
    assert_match(/Your organization has been granted access/, mail.subject)
    assert_includes(mail.to, admin.email)

    assert_equal 2, GitHub.dogstats.increments("copilot.code_review_beta.onboard").length
  end

  test "skip ineligible users" do
    refute GitHub.flipper[:copilot_code_review_public_preview].enabled?(@user)

    Copilot::Public::User.any_instance.stubs(:has_ci_access?).returns(false)

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Copilot::CodeReviewBetaOnboardJob.perform_now([
        @user.login
      ], actor: @site_admin)
    end

    refute @membership.reload.feature_enabled?
    assert @existing_membership.reload.feature_enabled?
    refute GitHub.flipper[:copilot_code_review_public_preview].enabled?(@user)
  end

  test "marks feature_enabled true for a batch of users if batch_size is set" do
    10.times do
      user = create(:user, :verified)
      create(:early_access_membership,
        member: user,
        actor: user,
        feature_slug: "copilot_code_review_public_preview",
        feature_enabled: false
      )
    end

    Copilot::Public::User.any_instance.stubs(:has_ci_access?).returns(true)

    assert_equal EarlyAccessMembership.copilot_code_review_waitlist.where(feature_enabled: true).count, 1 # the one from fixtures

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Copilot::CodeReviewBetaOnboardJob.perform_now([], batch_size: 2)
    end

    assert_equal EarlyAccessMembership.copilot_code_review_waitlist.where(feature_enabled: true).count, 3
    assert_equal(2, ActionMailer::Base.deliveries.length)
    assert_equal 2, GitHub.dogstats.increments("copilot.code_review_beta.onboard").length

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Copilot::CodeReviewBetaOnboardJob.perform_now([], batch_size: 2)
    end

    assert_equal EarlyAccessMembership.copilot_code_review_waitlist.where(feature_enabled: true).count, 5
    assert_equal(ActionMailer::Base.deliveries.length, 4)
    assert_equal 4, GitHub.dogstats.increments("copilot.code_review_beta.onboard").length

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      Copilot::CodeReviewBetaOnboardJob.perform_now([], batch_size: 1000)
    end

    assert_equal 12, EarlyAccessMembership.copilot_code_review_waitlist.where(feature_enabled: true).count
    assert_equal 11, GitHub.dogstats.increments("copilot.code_review_beta.onboard").length
    assert_equal(ActionMailer::Base.deliveries.length, 11)

  end

  test "marks feature_enabled true for a batch of orgs if batch_size is set" do
    perform_enqueued_jobs(only: [InheritOrgEarlyAccessJob]) do
      2.times do
        admin = create(:user, :verified, login: "admin-#{SecureRandom.hex(4)}")
        org = create(:organization, admin: admin)
        create(:early_access_membership,
          member: org,
          actor: admin,
          feature_slug: "copilot_code_review_public_preview",
          feature_enabled: false
        )
      end
    end

    Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(true)
    Copilot::Organization.any_instance.stubs(:copilot_enabled?).returns(true)
    Copilot.stubs(:copilot_communication_opt_out?).returns(false)

    assert_equal EarlyAccessMembership.copilot_code_review_waitlist.where(feature_enabled: true).count, 1 # the one from fixtures

    perform_enqueued_jobs(only: [ApplicationDeliveryJob, InheritOrgEarlyAccessJob]) do
      Copilot::CodeReviewBetaOnboardJob.perform_now([], batch_size: 3)
    end


    assert_equal 5, EarlyAccessMembership.copilot_code_review_waitlist.where(feature_enabled: true).count
    assert_equal(2, ActionMailer::Base.deliveries.length)
    assert_equal 4, GitHub.dogstats.increments("copilot.code_review_beta.onboard").length
  end

  test "flips the feature flag for eligible org but do not send welcome emails to admins if FF is enabled" do
    admin = create(:user, :verified, login: "admin-#{SecureRandom.hex(4)}")
    eligible_org = create(:organization, admin: admin)
    enable_feature_flag(:copilot_code_review_public_preview_skip_organization_onboarding_email, eligible_org)

    Copilot::Organization.new(eligible_org).enable_copilot!
    seat_assignment = create(:copilot_seat_assignment, organization: eligible_org, assignable: admin, assigning_user: admin)
    seat_assignment.convert_to_seats

    eligible_org_membership = T.let(nil, T.nilable(EarlyAccessMembership))
    perform_enqueued_jobs(only: [InheritOrgEarlyAccessJob]) do
      eligible_org_membership = create(:early_access_membership,
        member: eligible_org,
        actor: admin,
        feature_slug: "copilot_code_review_public_preview",
        feature_enabled: false
      )
    end

    GlobalInstrumenter.expects(:instrument).once.with(
      "user.beta_feature.enroll",
      equals(actor: admin,
        member: eligible_org,
        action: "enroll",
        feature: "copilot_code_review_public_preview",
      )
    )

    GlobalInstrumenter.expects(:instrument).once.with(
      "user.beta_feature.enroll",
      equals(actor: admin,
        member: admin,
        action: "enroll",
        feature: "copilot_code_review_public_preview",
      )
    )

    Copilot.stubs(:copilot_communication_opt_out?).returns(false)

    perform_enqueued_jobs(only: [ApplicationDeliveryJob, InheritOrgEarlyAccessJob]) do
      Copilot::CodeReviewBetaOnboardJob.perform_now([
        eligible_org.login
      ])
    end

    assert eligible_org_membership&.reload.feature_enabled?
    assert GitHub.flipper[:copilot_code_review_public_preview].enabled?(admin)
    assert_equal(ActionMailer::Base.deliveries.length, 0)
    assert_equal 2, GitHub.dogstats.increments("copilot.code_review_beta.onboard").length
  end

  test "do not send emails if preview features are disabled on business level" do
    business = create(:business, name: "test-test")
    organization = create(:organization, login: "test-test", business: business)
    Copilot::Business.any_instance.stubs(:copilot_for_dotcom_disabled?).returns(false)
    Copilot::Business.any_instance.stubs(:beta_features_github_chat_enabled_in_config?).returns(false)
    Copilot::Business.any_instance.stubs(:beta_features_github_chat_no_policy_in_config?).returns(false)
    refute Copilot::CodeReviewBetaOnboardJob.new.send(:send_email_to_org_admin?, organization)
  end

  test "do not send emails if copilot for dotcom is disabled on business level" do
    business = create(:business, name: "test-test")
    organization = create(:organization, login: "test-test", business: business)
    Copilot::Business.any_instance.stubs(:copilot_for_dotcom_disabled?).returns(true)
    Copilot::Business.any_instance.stubs(:beta_features_github_chat_enabled_in_config?).returns(true)
    Copilot::Business.any_instance.stubs(:beta_features_github_chat_no_policy_in_config?).returns(false)
    refute Copilot::CodeReviewBetaOnboardJob.new.send(:send_email_to_org_admin?, organization)
  end

  test "send emails if preview features are no policy on business level" do
    business = create(:business, name: "test-test")
    organization = create(:organization, login: "test-test", business: business)
    Copilot::Business.any_instance.stubs(:copilot_for_dotcom_disabled?).returns(false)
    Copilot::Business.any_instance.stubs(:beta_features_github_chat_enabled_in_config?).returns(false)
    Copilot::Business.any_instance.stubs(:beta_features_github_chat_no_policy_in_config?).returns(true)
    assert Copilot::CodeReviewBetaOnboardJob.new.send(:send_email_to_org_admin?, organization)
  end

  test "send emails if preview features are enabled on business level" do
    business = create(:business, name: "test-test")
    organization = create(:organization, login: "test-test", business: business)
    Copilot::Business.any_instance.stubs(:copilot_for_dotcom_disabled?).returns(false)
    Copilot::Business.any_instance.stubs(:beta_features_github_chat_enabled_in_config?).returns(true)
    Copilot::Business.any_instance.stubs(:beta_features_github_chat_no_policy_in_config?).returns(false)
    assert Copilot::CodeReviewBetaOnboardJob.new.send(:send_email_to_org_admin?, organization)
  end

end if GitHub.copilot_enabled?
