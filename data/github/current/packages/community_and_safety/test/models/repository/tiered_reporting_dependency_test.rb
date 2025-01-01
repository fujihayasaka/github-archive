# typed: true
# frozen_string_literal: true

require "test_helper"

class TieredReportingDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @org_repo = create(:repository, owner: @org)

    @org_repo_admin = create(:user)
    @org.add_member(@org_repo_admin)
    @org_repo.add_member(@org_repo_admin, action: :admin)

    @org_member = create(:user)
    @org.add_member(@org_member)

    @org_repo_member = create(:user)
    @org_repo.add_member(@org_repo_member, action: :read)
    @org_repo_content = create(:issue, repository: @org_repo)
    if GitHub.can_report?
      @org_repo.enable_tiered_reporting(actor: @org_repo_admin)
    end

    @user_repo_admin = create(:user)
    @user_repo = create(:repository, owner: @user_repo_admin)
  end

  setup do
    reset_monolith_redis_rate_limiter
  end

  context "eligible_for_tiered_reporting?" do
    if GitHub.enterprise?
      test "false for enterprise" do
        refute_predicate @org_repo, :eligible_for_tiered_reporting?
      end
    else
      test "false for a user-owned repo" do
        refute_predicate @user_repo, :eligible_for_tiered_reporting?
      end

      test "true for an org-owned repo" do
        assert_predicate @org_repo, :eligible_for_tiered_reporting?
      end
    end
  end

  context "can_access_tiered_reporting?" do
    if GitHub.enterprise?
      test "false for enterprise" do
        refute @org_repo.can_access_tiered_reporting?(@org_repo_admin)
      end
    else
      test "true for org repo admins" do
        assert @org_repo.can_access_tiered_reporting?(@org_repo_admin)
      end

      test "false for user repo admins" do
        refute @user_repo.can_access_tiered_reporting?(@user_repo_admin)
      end

      test "false for org repo members" do
        refute @org_repo.can_access_tiered_reporting?(@org_repo_member)
      end
    end
  end

  context "can_enable_tiered_reporting?" do
    if GitHub.enterprise?
      test "false for enterprise" do
        refute @org_repo.can_enable_tiered_reporting?(@org_repo_admin)
      end
    else
      test "true for org repo admins" do
        assert @org_repo.can_enable_tiered_reporting?(@org_repo_admin)
      end

      test "false on private repo" do
        @org_repo.toggle_visibility(actor: @org_repo_admin)
        refute @org_repo.can_enable_tiered_reporting?(@org_repo_admin)
      end

      test "false for user repo admins" do
        refute @user_repo.can_enable_tiered_reporting?(@user_repo_admin)
      end

      test "false for org repo members" do
        refute @org_repo.can_enable_tiered_reporting?(@org_repo_member)
      end
    end
  end

  if GitHub.can_report?
    context "show_abuse_report_banner?" do
      context "tiered reporting" do
        test "returns false if tiered reporting is disabled" do
          report = create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: true)
          @org_repo.disable_tiered_reporting(actor: @org_repo_admin)

          refute @org_repo.show_abuse_report_banner?(@org_repo_admin)
        end

        test "returns false for non-admins" do
          report = create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: true)

          refute @org_repo.show_abuse_report_banner?(@org_repo_member)
          refute @org_repo.show_abuse_report_banner?(@org_member)
        end

        test "returns false if there are no abuse reports" do
          refute @org_repo.show_abuse_report_banner?(@org_repo_admin)
        end

        test "returns false if there is one abuse report, but from a spammy user" do
          @org_member.mark_as_spammy
          create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: true)

          refute @org_repo.show_abuse_report_banner?(@org_repo_admin)
        end

        test "returns false if there is one abuse report, but on content created by a spammy user" do
          spammer = create(:user, spammy: true)
          spammy_issue = create(:issue, repository: @org_repo, user: spammer)
          create(:abuse_report, reported_content: spammy_issue, reporting_user: @org_member, show_to_maintainer: true)

          refute @org_repo.show_abuse_report_banner?(@org_repo_admin)
        end

        test "returns false if the only abuse report has `show_to_maintainer == false`" do
          report = create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: false)

          refute @org_repo.show_abuse_report_banner?(@org_repo_admin)
        end

        test "returns true for admin if tiered reporting is enabled and there are abuse reports" do
          report = create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: true)

          assert @org_repo.show_abuse_report_banner?(@org_repo_admin)
        end
      end

      context "tiered reporting all users" do
        test "returns false if tiered reporting is disabled" do
          report = create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: true)
          @org_repo.disable_tiered_reporting(actor: @org_repo_admin)
          @org_repo.disable_tiered_reporting_all_users(actor: @org_repo_admin)

          refute @org_repo.show_abuse_report_banner?(@org_repo_admin)
        end

        test "returns false for non-admins" do
          @org_repo.enable_tiered_reporting_all_users(actor: @org_repo_admin)
          report = create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: true)

          refute @org_repo.show_abuse_report_banner?(@org_repo_member)
          refute @org_repo.show_abuse_report_banner?(@org_member)
        end

        test "returns false if there are no abuse reports" do
          @org_repo.enable_tiered_reporting_all_users(actor: @org_repo_admin)
          refute @org_repo.show_abuse_report_banner?(@org_repo_admin)
        end

        test "returns false if there is one abuse report, but from a spammy user" do
          @org_repo.enable_tiered_reporting_all_users(actor: @org_repo_admin)
          @org_member.mark_as_spammy
          create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: true)

          refute @org_repo.show_abuse_report_banner?(@org_repo_admin)
        end

        test "returns false if there is one abuse report, but on content created by a spammy user" do
          @org_repo.enable_tiered_reporting_all_users(actor: @org_repo_admin)
          spammer = create(:user, spammy: true)
          spammy_issue = create(:issue, repository: @org_repo, user: spammer)
          create(:abuse_report, reported_content: spammy_issue, reporting_user: @org_member, show_to_maintainer: true)

          refute @org_repo.show_abuse_report_banner?(@org_repo_admin)
        end

        test "returns false if the only abuse report has `show_to_maintainer == false`" do
          @org_repo.enable_tiered_reporting_all_users(actor: @org_repo_admin)
          report = create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: false)

          refute @org_repo.show_abuse_report_banner?(@org_repo_admin)
        end

        test "returns true for admin if tiered reporting is enabled and there are abuse reports" do
          @org_repo.enable_tiered_reporting_all_users(actor: @org_repo_admin)
          report = create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: true)

          assert @org_repo.show_abuse_report_banner?(@org_repo_admin)
        end
      end
    end

    context "unresolved_abuse_report_count" do
      test "returns 1 if there is one" do
        report = create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: true)
        assert_equal @org_repo.unresolved_abuse_report_count, 1
      end

      test "returns 0 if the one is resolved" do
        report = create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: true)
        report.mark_resolved(@org_repo_admin)

        assert_equal @org_repo.unresolved_abuse_report_count, 0
      end

      test "returns 0 if there are none" do
        assert_equal @org_repo.unresolved_abuse_report_count, 0
      end

      test "returns 0 if there is one unresolved, but from a spammy user" do
        @org_member.mark_as_spammy
        create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, show_to_maintainer: true)

        assert_equal @org_repo.unresolved_abuse_report_count, 0
      end

      test "returns 0 if there is one unresolved, but on content created by a spammy user" do
        spammer = create(:user, spammy: true)
        spammy_issue = create(:issue, repository: @org_repo, user: spammer)
        create(:abuse_report, reported_content: spammy_issue, reporting_user: @org_member, show_to_maintainer: true)

        assert_equal @org_repo.unresolved_abuse_report_count, 0
      end
    end
  end
end
