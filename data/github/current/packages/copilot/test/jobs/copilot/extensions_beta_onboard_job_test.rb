# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::ExtensionsBetaOnboardJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include JobTestHelper

  fixtures do
    @user = create(:user, :verified)
    @user_membership = create(:early_access_membership,
      member: @user,
      actor: @user,
      feature_slug: "copilot_extension_access",
      feature_enabled: false
    )

    @organization = create(:organization)
    @organization_membership = create(:early_access_membership,
      member: @organization,
      actor: @organization.admin,
      feature_slug: "copilot_extension_access",
      feature_enabled: false
    )

    @business = create(:business)
    @business_membership = create(:early_access_membership,
      member: @business,
      actor: @business.admins.first,
      feature_slug: "copilot_extension_access",
      feature_enabled: false
    )
  end

  setup do
    disable_feature_flag(:copilot_extension_access)
    enable_feature_group(:copilot_extension_access, "early_access_enabled")
    @mailer = mock
    @mailer.stubs(:deliver_later)
  end

  context "when the member to be onboarded is a user" do
    test "updates the membership and sends an email" do
      refute @user.feature_enabled?(:copilot_extension_access)
      refute @user_membership.feature_enabled?

      CopilotExtensionsBetaMembershipMailer.expects(:individual_waitlist_acceptance).with(@user_membership).returns(@mailer).once
      @mailer.expects(:deliver_later)

      logs = capture_logs { Copilot::ExtensionsBetaOnboardJob.perform_now([@user.display_login]) }

      assert @user_membership.reload.feature_enabled?
      assert GitHub.flipper[:copilot_extension_access].enabled?(@user)
      assert_includes logs, "User onboarded to Copilot Extensions Beta"
      assert_includes logs, "gh.user.id=\"#{@user.id}\""
      assert_includes logs, "gh.user.name=\"#{@user.display_login}\""
    end

    test "does not update the membership if it cannot be onboarded" do
      @user_membership.update(can_onboard: false)
      refute @user_membership.reload.can_onboard?

      CopilotExtensionsBetaMembershipMailer.expects(:individual_waitlist_acceptance).never

      logs = capture_logs { Copilot::ExtensionsBetaOnboardJob.perform_now(@user_membership) }

      refute GitHub.flipper[:copilot_extension_access].enabled?(@user)
      refute @user_membership.reload.can_onboard?
      assert_includes logs, "Failed to onboard User to Copilot Extensions Beta"
      assert_includes logs, "gh.user.id=\"#{@user.id}\""
      assert_includes logs, "gh.user.name=\"#{@user.display_login}\""
    end
  end

  context "when the member to be onboarded is an organization" do
    test "updates the membership and sends emails" do
      refute @organization.feature_enabled?(:copilot_extension_access)
      refute @organization_membership.feature_enabled?

      CopilotExtensionsBetaMembershipMailer.expects(:business_waitlist_acceptance)
        .with(@organization_membership, @organization.admins.first)
        .returns(@mailer)
        .once
      @mailer.expects(:deliver_later)

      logs = capture_logs { Copilot::ExtensionsBetaOnboardJob.perform_now([@organization.display_login]) }

      assert @organization_membership.reload.feature_enabled?
      assert GitHub.flipper[:copilot_extension_access].enabled?(@organization)
      assert_includes logs, "Organization onboarded to Copilot Extensions Beta"
      assert_includes logs, "gh.organization.id=\"#{@organization.id}\""
      assert_includes logs, "gh.organization.name=\"#{@organization.display_login}\""
    end

    test "does not update the membership if it cannot be onboarded" do
      @organization_membership.update(can_onboard: false)
      refute @organization_membership.reload.can_onboard?

      CopilotExtensionsBetaMembershipMailer.expects(:business_waitlist_acceptance).never

      logs = capture_logs { Copilot::ExtensionsBetaOnboardJob.perform_now(@organization_membership) }

      refute GitHub.flipper[:copilot_extension_access].enabled?(@organization)
      refute @organization_membership.reload.can_onboard?
      assert_includes logs, "Failed to onboard Organization to Copilot Extensions Beta"
      assert_includes logs, "gh.organization.id=\"#{@organization.id}\""
      assert_includes logs, "gh.organization.name=\"#{@organization.display_login}\""
    end
  end

  context "when the member to be onboarded is a business" do
    test "updates the membership and sends emails" do
      refute @business.feature_enabled?(:copilot_extension_access)
      refute @business_membership.feature_enabled?

      CopilotExtensionsBetaMembershipMailer.expects(:business_waitlist_acceptance)
        .with(@business_membership, @business.admins.first)
        .returns(@mailer)
        .once
      @mailer.expects(:deliver_later)

      logs = capture_logs { Copilot::ExtensionsBetaOnboardJob.perform_now(@business_membership) }

      assert @business_membership.reload.feature_enabled?
      assert GitHub.flipper[:copilot_extension_access].enabled?(@business)
      assert_includes logs, "Business onboarded to Copilot Extensions Beta"
      assert_includes logs, "gh.business.id=\"#{@business.id}\""
      assert_includes logs, "gh.business.name=\"#{@business.display_login}\""
    end

    test "does not update the membership if it cannot be onboarded" do
      @business_membership.update(can_onboard: false)
      refute @business_membership.reload.can_onboard?

      CopilotExtensionsBetaMembershipMailer.expects(:business_waitlist_acceptance).never

      logs = capture_logs { Copilot::ExtensionsBetaOnboardJob.perform_now(@business_membership) }

      refute GitHub.flipper[:copilot_extension_access].enabled?(@business)
      refute @business_membership.reload.can_onboard?
      assert_includes logs, "Failed to onboard Business to Copilot Extensions Beta"
      assert_includes logs, "gh.business.id=\"#{@business.id}\""
      assert_includes logs, "gh.business.name=\"#{@business.display_login}\""
    end
  end
end if GitHub.copilot_enabled?
