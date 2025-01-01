# typed: true
# frozen_string_literal: true

require "test_helper"

class ComplianceChecksDryRunTest < GitHub::TestCase
  fixtures do

    @owner = create(:user, login: "owner")
    @free_org_owner = create(:user, login: "free-org-owner")
    @org = create(:organization, admin: @owner)
    @free_org = create(:free_org, admin: @free_org_owner)

    @user_1 = create(:user)
    @user_2 = create(:user)
    @user_3 = create(:user)
    @user_4 = create(:user)

    @restricted_user_1 = create(:user, :fully_trade_restricted)
    @restricted_user_2 = create(:user, :fully_trade_restricted)
    @restricted_user_3 = create(:user, :fully_trade_restricted)
    @restricted_user_4 = create(:user, :fully_trade_restricted)

    @paid_org_repo = create(:repository, owner: @org)
    @free_org_repo = create(:repository, owner: @free_org)
  end

  context "organization_billing_manager reason" do
    test "reason is absent for org without billing managers" do
      assert_empty @org.billing_managers

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run
      refute checker.violations.key?(:organization_billing_manager)
    end

    test "reason is present for a paid org whose trade restricted billing managers is = 50%" do
      [@user_1, @user_2, @restricted_user_1, @restricted_user_2].each do |u|
        @org.billing.add_manager(u, actor: @owner)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run

      assert @org.billing_managers.count == 4
      assert @org.billing_managers.to_a.count { |e| e.has_any_trade_restrictions? } == 2
      assert checker.violations.key?(:organization_billing_manager)
    end

    test "reason is present for a paid org whose trade restricted billing managers > 50%" do
      [@user_1, @user_2, @restricted_user_1, @restricted_user_2, @restricted_user_3].each do |u|
        @org.billing.add_manager(u, actor: @owner)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run

      assert @org.billing_managers.count == 5
      assert @org.billing_managers.to_a.count { |e| e.has_any_trade_restrictions? } == 3
      assert checker.violations.key?(:organization_billing_manager)
    end

    test "reason is absent for a paid org whose trade restricted billing managers is < 50%" do
      [@user_1, @user_2, @restricted_user_1].each do |u|
        @org.billing.add_manager(u, actor: @owner)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run

      assert @org.billing_managers.count == 3
      assert @org.billing_managers.to_a.count { |e| e.has_any_trade_restrictions? } == 1
      refute checker.violations.key?(:organization_billing_manager)
    end

    test "reason is present for a free org whose trade restricted billing managers is = 50%" do
      [@user_1, @user_2, @restricted_user_1, @restricted_user_2].each do |u|
        @free_org.billing.add_manager(u, actor: @free_org_owner)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@free_org)
      checker.run

      assert @free_org.billing_managers.count == 4
      assert @free_org.billing_managers.to_a.count { |e| e.has_any_trade_restrictions? } == 2
      assert checker.violations.key?(:organization_billing_manager)
    end

    test "reason is present for a free org whose trade restricted billing managers > 50%" do
      [@user_1, @user_2, @restricted_user_1, @restricted_user_2, @restricted_user_3].each do |u|
        @free_org.billing.add_manager(u, actor: @free_org_owner)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@free_org)
      checker.run

      assert @free_org.billing_managers.count == 5
      assert @free_org.billing_managers.to_a.count { |e| e.has_any_trade_restrictions? } == 3
      assert checker.violations.key?(:organization_billing_manager)
    end

    test "reason is present for a free org whose trade restricted billing managers is = 25%" do
      [@user_1, @user_2, @user_3, @restricted_user_1].each do |u|
        @free_org.billing.add_manager(u, actor: @free_org_owner)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@free_org)
      checker.run

      assert @free_org.billing_managers.count == 4
      assert @free_org.billing_managers.to_a.count { |e| e.has_any_trade_restrictions? } == 1
      assert checker.violations.key?(:organization_billing_manager)
    end

    test "reason is present for a free org whose trade restricted billing managers > 25%" do
      [@user_1, @user_2, @user_3, @restricted_user_1, @restricted_user_2].each do |u|
        @free_org.billing.add_manager(u, actor: @free_org_owner)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@free_org)
      checker.run

      assert @free_org.billing_managers.count == 5
      assert @free_org.billing_managers.to_a.count { |e| e.has_any_trade_restrictions? } == 2
      assert checker.violations.key?(:organization_billing_manager)
    end

    test "reason is absent for a free org whose trade restricted billing managers is < 25%" do
      [@user_1, @user_2, @user_3, @user_4, @restricted_user_1].each do |u|
        @free_org.billing.add_manager(u, actor: @free_org_owner)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@free_org)
      checker.run

      assert @free_org.billing_managers.count == 5
      assert @free_org.billing_managers.to_a.count { |e| e.has_any_trade_restrictions? } == 1
      refute checker.violations.key?(:organization_billing_manager)
    end
  end

  context "organization_admin reason" do
    test "reason is absent for org without restricted owners" do
      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run

      assert @org.admins.to_a.count { |e| e.has_any_trade_restrictions? } == 0
      refute checker.violations.key?(:organization_admin)
    end

    test "reason is present for a paid org whose trade restricted admins is = 50%" do
      [@user_1, @restricted_user_1, @restricted_user_2].each do |u|
        @org.add_admin(u)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run

      assert @org.admins.count == 4
      assert @org.admins.to_a.count { |e| e.has_any_trade_restrictions? } == 2
      assert checker.violations.key?(:organization_admin)
    end

    test "reason is present for a paid org whose trade restricted admins > 50%" do
      [@user_1, @restricted_user_1, @restricted_user_2, @restricted_user_3].each do |u|
        @org.add_admin(u)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run

      assert @org.admins.count == 5
      assert @org.admins.to_a.count { |e| e.has_any_trade_restrictions? } == 3
      assert checker.violations.key?(:organization_admin)
    end

    test "reason is absent for a paid org whose trade restricted admins is < 50%" do
      [@user_1, @restricted_user_1].each do |u|
        @org.add_admin(u)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run

      assert @org.admins.count == 3
      assert @org.admins.to_a.count { |e| e.has_any_trade_restrictions? } == 1
      refute checker.violations.key?(:organization_admin)
    end

    test "reason is present for a free org whose trade restricted admins is = 50%" do
      [@user_1, @restricted_user_1, @restricted_user_2].each do |u|
        @free_org.add_admin(u)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@free_org)
      checker.run

      assert @free_org.admins.count == 4
      assert @free_org.admins.to_a.count { |e| e.has_any_trade_restrictions? } == 2
      assert checker.violations.key?(:organization_admin)
    end

    test "reason is present for a free org whose trade restricted admins > 50%" do
      [@user_1, @restricted_user_1, @restricted_user_2, @restricted_user_3].each do |u|
        @free_org.add_admin(u)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@free_org)
      checker.run

      assert @free_org.admins.count == 5
      assert @free_org.admins.to_a.count { |e| e.has_any_trade_restrictions? } == 3
      assert checker.violations.key?(:organization_admin)
    end

    test "reason is present for a free org whose trade restricted admins = 25%" do
      [@user_1, @user_2, @restricted_user_1].each do |u|
        @free_org.add_admin(u)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@free_org)
      checker.run

      assert @free_org.admins.count == 4
      assert @free_org.admins.to_a.count { |e| e.has_any_trade_restrictions? } == 1
      assert checker.violations.key?(:organization_admin)
    end

    test "reason is present for a free org whose trade restricted admins is > 25%" do
      [@user_1, @user_2, @user_3, @restricted_user_1, @restricted_user_2].each do |u|
        @free_org.add_admin(u)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@free_org)
      checker.run

      assert @free_org.admins.count == 6
      assert @free_org.admins.to_a.count { |e| e.has_any_trade_restrictions? } == 2
      assert checker.violations.key?(:organization_admin)
    end

    test "reason is absent for a free org whose trade restricted admins is < 25%" do
      [@user_1, @user_2, @user_3, @user_4, @restricted_user_1].each do |u|
        @free_org.add_admin(u)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@free_org)
      checker.run

      assert @free_org.admins.count == 6
      assert @free_org.admins.to_a.count { |e| e.has_any_trade_restrictions? } == 1
      refute checker.violations.key?(:organization_admin)
    end
  end

  context "organization_member reason" do
    test "reason is absent for org without restricted members" do
      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run

      assert @org.members.to_a.count { |e| e.has_any_trade_restrictions? } == 0
      refute checker.violations.key?(:organization_member)
    end

    test "reason is absent for a free org whose trade restricted members is < 25%" do
      [@user_1, @user_2, @user_3, @user_4, @restricted_user_1].each do |u|
        @free_org.add_member(u)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@free_org)
      checker.run

      assert @free_org.members.count == 6
      assert @free_org.members.to_a.count { |e| e.has_any_trade_restrictions? } == 1
      refute checker.violations.key?(:organization_admin)
    end
  end

  context "billing_email reason" do
    test "reason is absent for org without a sanctioned billing email" do
      @org.update(billing_email: "test@example.uk")

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run
      refute checker.violations.key?(:billing_email)
    end

    test "reason is present for org with sanctioned billing email" do
      @org.update(billing_email: "test@example.sy")

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run
      assert checker.violations.key?(:billing_email)
    end

    test "reason is present for org with a sanctioned external billing email" do
      @org.billing_external_emails.create(email: "test2@example.sy")

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run
      assert checker.violations.key?(:billing_email)
    end
  end

  context "profile_email reason" do
    test "reason is absent for user without a sanctioned profile email" do
      @owner.create_profile(email: "test@example.uk")

      checker = TradeControls::ComplianceChecksDryRun.new(@owner)
      checker.run
      refute checker.violations.key?(:profile_email)
    end

    test "reason is absent for org without a sanctioned profile email" do
      @org.create_profile(email: "test@example.uk")

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run
      refute checker.violations.key?(:profile_email)
    end

    test "reason is present for user with sanctioned profile email" do
      @owner.create_profile(email: "test@example.sy")

      checker = TradeControls::ComplianceChecksDryRun.new(@owner)
      checker.run
      assert checker.violations.key?(:profile_email)
    end

    test "reason is present for org with sanctioned profile email" do
      @org.create_profile(email: "test@example.sy")

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run
      assert checker.violations.key?(:profile_email)
    end

    test "reason is present for user with other sanctioned emails" do
      @owner.add_email("test2@example.sy")

      checker = TradeControls::ComplianceChecksDryRun.new(@owner)
      checker.run

      assert_nil @owner.profile_email
      assert_equal 2, @owner.emails.count
      assert checker.violations.key?(:profile_email)
    end
  end

  context "website_url reason" do
    test "reason is absent for user without a sanctioned profile blog" do
      @owner.create_profile(blog: "www.my-blog.uk")

      checker = TradeControls::ComplianceChecksDryRun.new(@owner)
      checker.run
      refute checker.violations.key?(:website_url)
    end

    test "reason is absent for org without a sanctioned profile blog" do
      @org.create_profile(blog: "www.my-blog.uk")

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run
      refute checker.violations.key?(:website_url)
    end

    test "reason is present for user with sanctioned profile blog" do
      @owner.create_profile(blog: "www.my-blog.sy")

      checker = TradeControls::ComplianceChecksDryRun.new(@owner)
      checker.run
      assert checker.violations.key?(:website_url)
    end

    test "reason is present for org with sanctioned profile blog" do
      @org.create_profile(blog: "www.my-blog.sy")

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run
      assert checker.violations.key?(:website_url)
    end
  end

  context "humanize_violations reason" do
    test "is empty without violations" do
      @owner.create_profile(blog: "www.my-blog.uk")

      checker = TradeControls::ComplianceChecksDryRun.new(@owner)
      checker.run
      assert_empty checker.humanize_violations
    end

    test "it humanizes organization_billing_manager violation" do
      [@user_1, @user_2, @restricted_user_1, @restricted_user_2].each do |u|
        @org.billing.add_manager(u, actor: @owner)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run

      compliance = TradeControls::BillingManagersCompliance.new(organization: @org)
      assert_includes checker.humanize_violations, TradeControls::Notices.percentage_restriction_reason(percent: compliance.current_threshold, type: "billing managers")
    end

    test "it humanizes organization_admin violation" do
      [@user_1, @restricted_user_1, @restricted_user_2].each do |u|
        @org.add_admin(u)
      end

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run

      compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @org)
      assert_includes checker.humanize_violations, TradeControls::Notices.percentage_restriction_reason(percent: compliance.current_threshold, type: "owners")
    end

    test "it humanizes billing_email violation" do
      @org.update(billing_email: "test@example.sy")

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run

      assert_includes checker.humanize_violations, TradeControls::Notices.billing_email_restriction_reason
    end

    test "it humanizes external billing_email violation" do
      @org.billing_external_emails.create(email: "test2@example.sy")

      checker = TradeControls::ComplianceChecksDryRun.new(@org)
      checker.run

      assert_includes checker.humanize_violations, TradeControls::Notices.external_billing_email_restriction_reason
    end

    test "it humanizes profile_email violation" do
      @owner.create_profile(email: "test@example.sy")

      checker = TradeControls::ComplianceChecksDryRun.new(@owner)
      checker.run

      assert_includes checker.humanize_violations, TradeControls::Notices.profile_email_restriction_reason
    end

    test "it humanizes other user emails violation" do
      @owner.add_email("test2@example.sy")

      checker = TradeControls::ComplianceChecksDryRun.new(@owner)
      checker.run

      assert_includes checker.humanize_violations, TradeControls::Notices.user_emails_restriction_reason
    end

    test "it humanizes website_url violation" do
      @owner.create_profile(blog: "www.my-blog.sy")

      checker = TradeControls::ComplianceChecksDryRun.new(@owner)
      checker.run

      assert_includes checker.humanize_violations, TradeControls::Notices.website_url_restriction_reason
    end
  end

  test "it works with a single reason" do
    [@user_1, @user_2, @restricted_user_1, @restricted_user_2].each do |u|
      @org.billing.add_manager(u, actor: @owner)
    end

    checker = TradeControls::ComplianceChecksDryRun.new(@org, reason: :organization_billing_manager)
    checker.run

    assert @org.billing_managers.count == 4
    assert @org.billing_managers.to_a.count { |e| e.has_any_trade_restrictions? } == 2
    assert checker.violations.key?(:organization_billing_manager)
  end
end
