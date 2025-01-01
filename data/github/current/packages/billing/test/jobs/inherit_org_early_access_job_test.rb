# typed: true
# frozen_string_literal: true

require "test_helper"

class InheritOrgEarlyAccessJobTest < GitHub::TestCase
  include CopilotPublicUserCacheable

  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, admins: [@org_admin])
    @user1 = create(:user)
    @user2 = create(:user)
    @user3 = create(:user)
    @user_no_copilot = create(:user)

    Copilot::Organization.new(@org).enable_copilot!

    [@user1, @user2, @user3].each do |user|
      @org.add_member(user)
      create(:copilot_seat_assignment, organization: @org, assignable: user)
    end

    @org.add_member(@user_no_copilot)
  end

  setup do
    @copilot_code_review_beta = Copilot::CodeReviewBeta.new
    disable_feature_flag(:copilot_code_review_public_preview_skip_organization_onboarding_email)
    Copilot.stubs(:copilot_communication_opt_out?).returns(false)
  end

  test "creates early access membership for every eligible org member and offboards members" do
    Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)
    org_membership = EarlyAccessMembership.new(
      member: @org,
      actor: @org_admin,
      feature_slug: "copilot_code_review_public_preview",
      feature_enabled: true,
      survey: @copilot_code_review_beta.survey
    )

    perform_enqueued_jobs(only: [ApplicationDeliveryJob, InheritOrgEarlyAccessJob]) do
      org_membership.save!
    end

    assert_equal 3, EarlyAccessMembership.copilot_code_review_waitlist.where(parent_id: org_membership.id, feature_enabled: true).count
    assert_nil EarlyAccessMembership.find_by(member: @user_no_copilot, parent_id: org_membership.id)
    assert_equal(3, ActionMailer::Base.deliveries.length)

    # off-boarding org members
    perform_enqueued_jobs(only: [InheritOrgEarlyAccessJob]) do
      org_membership.update!(feature_enabled: false)
    end
    assert_equal 3, EarlyAccessMembership.copilot_code_review_waitlist.where(parent_id: org_membership.id).count
    assert_equal 3, EarlyAccessMembership.copilot_code_review_waitlist.where(parent_id: org_membership.id, feature_enabled: false).count
  end

  test "creates early access membership for every eligible org member but don't send onboarding emails if FF is enabled" do
    enable_feature_flag(:copilot_code_review_public_preview_skip_organization_onboarding_email, @org)

    org_membership = EarlyAccessMembership.new(
      member: @org,
      actor: @org_admin,
      feature_slug: "copilot_code_review_public_preview",
      feature_enabled: true,
      survey: @copilot_code_review_beta.survey
    )

    perform_enqueued_jobs(only: [ApplicationDeliveryJob, InheritOrgEarlyAccessJob]) do
      org_membership.save!
    end

    assert_equal 3, EarlyAccessMembership.copilot_code_review_waitlist.where(parent_id: org_membership.id, feature_enabled: true).count
    assert_nil EarlyAccessMembership.find_by(member: @user_no_copilot, parent_id: org_membership.id)
    assert_equal(0, ActionMailer::Base.deliveries.length)
  end

  test "does not create duplicate memberships" do
    org_membership = EarlyAccessMembership.new(
      member: @org,
      actor: @org_admin,
      feature_slug: "copilot_code_review_public_preview",
      feature_enabled: true,
      survey: @copilot_code_review_beta.survey
    )

    user_membership = EarlyAccessMembership.new(
      member: @user1,
      actor: @user1,
      feature_slug: "copilot_code_review_public_preview",
      feature_enabled: false,
      survey: @copilot_code_review_beta.survey)

    user_membership.save!
    perform_enqueued_jobs(only: [InheritOrgEarlyAccessJob]) do
      org_membership.save!
    end

    assert user_membership.reload.feature_enabled?

    assert_equal 2, EarlyAccessMembership.copilot_code_review_waitlist.where(parent_id: org_membership.id, feature_enabled: true).count
    InheritOrgEarlyAccessJob.perform_now(org_membership)
    assert_equal 2, EarlyAccessMembership.copilot_code_review_waitlist.where(parent_id: org_membership.id, feature_enabled: true).count
    assert_nil EarlyAccessMembership.find_by(member: @user_no_copilot, parent_id: org_membership.id)

    # off-boarding org
    perform_enqueued_jobs(only: [InheritOrgEarlyAccessJob]) do
      org_membership.update!(feature_enabled: false)
    end
    assert_equal 2, EarlyAccessMembership.copilot_code_review_waitlist.where(parent_id: org_membership.id, feature_enabled: false).count

    # individual membership should not be off-boarded
    assert user_membership.reload.feature_enabled?
  end

  test "creates early access membership for every eligible org member and removes members that are not in the org" do
    Copilot::Public::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)
    org_membership = EarlyAccessMembership.new(
      member: @org,
      actor: @org_admin,
      feature_slug: "copilot_code_review_public_preview",
      feature_enabled: true,
      survey: @copilot_code_review_beta.survey
    )

    perform_enqueued_jobs(only: [ApplicationDeliveryJob, InheritOrgEarlyAccessJob]) do
      org_membership.save!
    end

    assert_equal 3, EarlyAccessMembership.copilot_code_review_waitlist.where(parent_id: org_membership.id, feature_enabled: true).count
    assert_nil EarlyAccessMembership.find_by(member: @user_no_copilot, parent_id: org_membership.id)
    assert_equal(3, ActionMailer::Base.deliveries.length)
    perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob]) do
      @org.remove_member!(@user1)
    end
    InheritOrgEarlyAccessJob.perform_now(org_membership)

    assert_equal 2, EarlyAccessMembership.copilot_code_review_waitlist.where(parent_id: org_membership.id, feature_enabled: true).count
    assert_nil EarlyAccessMembership.find_by(member: @user1, parent_id: org_membership.id)
  end
end
