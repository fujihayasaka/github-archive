# typed: false
# frozen_string_literal: true

require "test_helper"

if GitHub.can_report?
  class AbuseReportTest < GitHub::TestCase
    fixtures do
      @rando = create(:user)
      @user = create(:user)
      @user_repo = create(:repository)
      @user_repo_content = create(:issue, repository: @user_repo)
      @org_admin = create(:user)
      @org = create(:organization, admin: @org_admin)
      @org_member = create(:user)
      @org_member2 = create(:user)
      @org.add_member(@org_member)
      @org.add_member(@org_member2)
      @org_repo = create(:repository, owner: @org)
      @org_repo.enable_tiered_reporting(actor: @org_admin)
      @org_repo_content = create(:issue, repository: @org_repo)
      @gist = create(:gist, owner: @rando)
      @gist_comment = create(:gist_comment, gist: @gist, user: @rando)

      @content_report_for_maintainer = create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member, repository: @org_repo, show_to_maintainer: true)
      @content_report_for_maintainer2 = create(:abuse_report, reported_content: @org_repo_content, reporting_user: @org_member2, repository: @org_repo, show_to_maintainer: true)
    end

    setup do
      reset_monolith_redis_rate_limiter
    end

    context "reported_user_sponsors_listing_stafftools_metadata relation" do
      test "returns the Sponsors stafftools metadata record for the reported user" do
        stafftools_metadata = create(:sponsors_listing_stafftools_metadata)
        user = stafftools_metadata.sponsorable
        abuse_report = create(:abuse_report, :user_report, reported_user: user)
        assert_equal stafftools_metadata, abuse_report.reported_user_sponsors_listing_stafftools_metadata
      end

      test "returns nil when no Sponsors stafftools metadata record exists for the reported user" do
        abuse_report = create(:abuse_report, :user_report)
        assert_nil abuse_report.reported_user_sponsors_listing_stafftools_metadata
      end

      test "returns nil when there is no reported user" do
        abuse_report = create(:abuse_report)
        abuse_report.reported_user&.delete
        assert_nil abuse_report.reported_user_sponsors_listing_stafftools_metadata
      end
    end

    context "validations" do
      test "reported_user set before validation" do
        abuse_report = AbuseReport.new(reported_content: @user_repo_content, reporting_user: @user, repository: @user_repo)
        assert abuse_report.valid?
      end

      test "repository set before validation" do
        abuse_report = AbuseReport.new(reported_content: @user_repo_content, reported_user: @rando, reporting_user: @user)
        assert abuse_report.valid?
      end

      test "repository not set for gist or gist comment" do
        abuse_report = AbuseReport.create(reported_content: @gist, reported_user: @rando, reporting_user: @user)
        refute abuse_report.repository
        abuse_report = AbuseReport.create(reported_content: @gist_comment, reported_user: @rando, reporting_user: @user)
        refute abuse_report.repository
      end

      test "all fields set correctly" do
        abuse_report = AbuseReport.new(reported_content: @user_repo_content, reported_user: @rando, reporting_user: @user, repository: @user_repo)
        assert abuse_report.valid?
      end

      test "accepts show_to_maintainer as true if reporter can report this content to the maintainer" do
        assert @content_report_for_maintainer.show_to_maintainer
      end

      test "doesn't accept show_to_maintainer as true if the reporter cannot report this content to the maintainer" do
        abuse_report = AbuseReport.new(reported_content: @user_repo_content, reported_user: @rando, reporting_user: @user, repository: @user_repo, show_to_maintainer: true)

        refute abuse_report.valid?
        assert_includes abuse_report.errors[:base], "You cannot perform that action at this time"
      end

      test "show_to_maintainer defaults to false" do
        abuse_report = create(:abuse_report, reported_content: @user_repo_content, reported_user: @rando, reporting_user: @user, repository: @user_repo)

        refute abuse_report.show_to_maintainer
      end

      test "resolved defaults to false" do
        abuse_report = create(:abuse_report, reported_content: @user_repo_content, reported_user: @rando, reporting_user: @user, repository: @user_repo)

        refute abuse_report.resolved
      end

      test "user can't report the same content twice" do
        abuse_report1 = create(:abuse_report, reported_content: @user_repo_content, reported_user: @rando, reporting_user: @user, repository: @user_repo)
        abuse_report2 = AbuseReport.new(reported_content: @user_repo_content, reported_user: @rando, reporting_user: @user, repository: @user_repo)

        refute abuse_report2.save
      end
    end

    context "#async_zendesk_url" do
      test "returns zendesk search url for context" do
        abuse_report = create(:abuse_report, reported_content: @user_repo_content)
        path = CGI.escape(@user_repo_content.async_path_uri.sync)
        assert_equal "https://github.zendesk.com/agent/search/1?q=#{path}", abuse_report.async_zendesk_url.sync
      end

      test "returns nil for deleted content" do
        abuse_report = create(:abuse_report, reported_content: @user_repo_content)
        abuse_report.reported_content.destroy!
        assert_nil abuse_report.reload.async_zendesk_url.sync
      end

      test "returns zendesk search url for reporting user if user report" do
        abuse_report = create(:abuse_report, reporting_user: @user, reported_user: create(:user), reported_content: nil)
        assert_equal "https://github.zendesk.com/agent/search/1?q=#{@user.login}%20#{abuse_report.reported_user.login}",
                     abuse_report.async_zendesk_url.sync
      end

      test "returns url with just reported user for anonymous user if user report" do
        abuse_report = create(:abuse_report, reported_user: create(:user), reported_content: nil, reporting_user: nil)
        assert_equal "https://github.zendesk.com/agent/search/1?q=%20#{abuse_report.reported_user.login}",
                     abuse_report.async_zendesk_url.sync
      end

      test "returns nil for reported user that doesn't exist and anonymous user" do
        deleted_user = create :user
        deleted_user_id = deleted_user.id
        deleted_user.destroy!
        assert_nil User.find_by_id(deleted_user_id)

        abuse_report = create(:abuse_report, reported_user_id: deleted_user_id, reported_content: nil, reporting_user: nil)
        assert_nil abuse_report.async_zendesk_url.sync
      end
    end

    context "#user_report?" do
      test "returns true if abuse report is a user report" do
        abuse_report = create(:abuse_report, reported_user: create(:user), reported_content: nil)
        assert abuse_report.user_report?
      end

      test "returns false if abuse report is a content report" do
        abuse_report = create(:abuse_report, reported_content: @user_repo_content)
        refute abuse_report.user_report?
      end
    end

    context "#content_report?" do
      test "returns true if abuse report is a content report" do
        abuse_report = create(:abuse_report, reported_content: @user_repo_content)
        assert abuse_report.content_report?
      end

      test "returns false if abuse report is a user report" do
        abuse_report = create(:abuse_report, reported_user: create(:user), reported_content: nil)
        refute abuse_report.content_report?
      end
    end

    test "reporting a gist enqueues a spam check" do
      assert_enqueued_with(job: GistFlaggedByUserJob, args: [@gist.id, @user.id]) do
        abuse_report = create(:abuse_report, reporting_user: @user, reported_content: @gist)
      end
    end

    context "audit logs" do
      test "creation for gist is audit logged" do
        events = subscribe "user.report_abuse"
        expected_payload = {
          org: nil,
          repo: nil,
          content_url: @gist.url,
          user: @user.login,
          user_id: @user.id,
          reported_user: @gist.user.login,
          reported_user_id: @gist.user.id,
        }

        create(:abuse_report, reported_content: @gist, reporting_user: @user)

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "creation in user-owned repo is audit logged" do
        events = subscribe "user.report_abuse"
        expected_payload = {
          org: nil,
          content_url: @user_repo_content.url,
          user: @user.login,
          user_id: @user.id,
          reported_user: @user_repo_content.user.login,
          reported_user_id: @user_repo_content.user.id,
          repo: @user_repo.nwo,
          repo_id: @user_repo.id,
          public_repo: @user_repo.public?,
        }

        create(:abuse_report, reported_content: @user_repo_content, reporting_user: @user)

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "creation for org-owned repo is audit logged" do
        events = subscribe "user.report_abuse"
        expected_payload = {
          org_id: @org.id,
          content_url: @org_repo_content.url,
          user: @user.login,
          user_id: @user.id,
          reported_user: @org_repo_content.user.login,
          reported_user_id: @org_repo_content.user.id,
          org: @org.login,
          repo: @org_repo.nwo,
          repo_id: @org_repo.id,
          public_repo: @org_repo.public?,
        }

        create(:abuse_report, reported_content: @org_repo_content, reporting_user: @user)

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    test "creation is rate limited" do
      with_cache_enabled do
        Timecop.freeze do
          4.times do
            report = AbuseReport.new(reported_content: create(:issue, repository: @org_repo), reporting_user: @user)
            assert report.save
          end

          report = AbuseReport.new(reported_content: create(:issue, repository: @org_repo), reporting_user: @user)
          refute report.save
          assert report.errors[:base].first.include? "We've received too many reports"
        end
      end
    end

    context "#async_readable_by?" do
      test "returns true for site admins" do
        @content_report_for_maintainer.show_to_maintainer = false
        @content_report_for_maintainer.save!

        assert @content_report_for_maintainer.async_readable_by?(create(:staff_admin_user)).sync
      end

      test "returns true for maintainers if show_to_maintainer is true" do
        assert @content_report_for_maintainer.async_readable_by?(@org_admin).sync
      end

      test "returns false for maintainers if show_to_maintainer is false" do
        @content_report_for_maintainer.show_to_maintainer = false
        @content_report_for_maintainer.save!

        refute @content_report_for_maintainer.async_readable_by?(@org_admin).sync
      end

      test "returns false for repo members" do
        member = create(:user)
        @org_repo.add_member(member, action: :read)
        assert @org_repo.readable_by?(member)
        refute @content_report_for_maintainer.async_readable_by?(member).sync
      end

      test "returns false for a random person" do
        rando = create(:user)
        refute @content_report_for_maintainer.async_readable_by?(rando).sync
      end
    end

    context "#reported_content_for" do
      test "returns the reported content for Gists" do
        gist_abuse_report = AbuseReport.create(reported_content: @gist, reported_user: @rando, reporting_user: @user)

        assert_equal @gist, gist_abuse_report.reported_content_for(@rando)
      end

      test "returns the reported content if the repo is readable" do
        assert_equal @org_repo_content, @content_report_for_maintainer.reported_content_for(@org_admin)
      end

      test "returns nil if the repo is not readable" do
        private_repo = create(:private_repository)
        private_repo_content = create(:issue, repository: private_repo)
        report = create(:abuse_report, reported_content: private_repo_content, reporting_user: @org_member, repository: private_repo)

        assert_nil report.reported_content_for(@rando)
      end
    end

    context "mark_resolved" do
      test "marks as resolved for admin if show_to_maintainer is true" do
        assert @content_report_for_maintainer.mark_resolved(@org_admin)
        assert @content_report_for_maintainer.resolved?
      end

      test "fails for admin if show_to_maintainer is false" do
        @content_report_for_maintainer.show_to_maintainer = false
        @content_report_for_maintainer.save!

        refute @content_report_for_maintainer.mark_resolved(@org_admin)
        refute @content_report_for_maintainer.resolved?
      end

      test "fails for org member" do
        refute @content_report_for_maintainer.mark_resolved(@org_member)
        refute @content_report_for_maintainer.resolved?
      end

      test "fails for repo member" do
        repo_member = create(:user)
        @org_repo.add_member(repo_member, action: :write)

        refute @content_report_for_maintainer.mark_resolved(repo_member)
        refute @content_report_for_maintainer.resolved?
      end

      test "fails for random person" do
        refute @content_report_for_maintainer.mark_resolved(@rando)
        refute @content_report_for_maintainer.resolved?
      end

      test "is audit logged" do
        events = subscribe "repo.resolve_abuse_report"

        expected_payload = {
          visibility: :public,
          abuse_report: @content_report_for_maintainer.id,
          repo: @org_repo.nwo,
          repo_id: @org_repo.id,
          public_repo: @org_repo.public?,
          org: @org.login,
          org_id: @org.id,
          fork_source: @org_repo.nwo,
          fork_source_id: @org_repo.id,
        }

        assert @content_report_for_maintainer.mark_resolved(@org_admin)

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    context "mark_resolved_for_content" do
      test "marks two reports as resolved for admin if show_to_maintainer is true" do
        assert AbuseReport.mark_resolved_for_content(@org_admin, @org_repo_content.class.to_s, @org_repo_content.id)
        @content_report_for_maintainer.reload
        @content_report_for_maintainer2.reload
        assert @content_report_for_maintainer.resolved?
        assert @content_report_for_maintainer2.resolved?
      end

      test "fails for admin if show_to_maintainer on the reports is false" do
        @content_report_for_maintainer.show_to_maintainer = false
        @content_report_for_maintainer.save!
        @content_report_for_maintainer2.show_to_maintainer = false
        @content_report_for_maintainer2.save!

        refute AbuseReport.mark_resolved_for_content(@org_admin, @org_repo_content.class.to_s, @org_repo_content.id)
        @content_report_for_maintainer.reload
        @content_report_for_maintainer2.reload
        refute @content_report_for_maintainer.resolved?
        refute @content_report_for_maintainer2.resolved?
      end

      test "fails for org member" do
        refute AbuseReport.mark_resolved_for_content(@org_member, @org_repo_content.class.to_s, @org_repo_content.id)
        @content_report_for_maintainer.reload
        @content_report_for_maintainer2.reload
        refute @content_report_for_maintainer.resolved?
        refute @content_report_for_maintainer2.resolved?
      end

      test "fails for repo member" do
        repo_member = create(:user)
        @org_repo.add_member(repo_member, action: :write)

        refute AbuseReport.mark_resolved_for_content(repo_member, @org_repo_content.class.to_s, @org_repo_content.id)
        @content_report_for_maintainer.reload
        @content_report_for_maintainer2.reload
        refute @content_report_for_maintainer.resolved?
        refute @content_report_for_maintainer2.resolved?
      end

      test "fails for random person" do
        refute AbuseReport.mark_resolved_for_content(@rando, @org_repo_content.class.to_s, @org_repo_content.id)
        @content_report_for_maintainer.reload
        @content_report_for_maintainer2.reload
        refute @content_report_for_maintainer.resolved?
        refute @content_report_for_maintainer2.resolved?
      end

      test "is audit logged" do
        events = subscribe "repo.resolve_abuse_report"

        expected_payload = {
          visibility: :public,
          abuse_reports: [@content_report_for_maintainer.id, @content_report_for_maintainer2.id].sort,
          repo: @org_repo.nwo,
          repo_id: @org_repo.id,
          public_repo: @org_repo.public?,
          org: @org.login,
          org_id: @org.id,
          fork_source: @org_repo.nwo,
          fork_source_id: @org_repo.id,
        }

        assert AbuseReport.mark_resolved_for_content(@org_admin, @org_repo_content.class.to_s, @org_repo_content.id)

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    context "mark_unresolved" do
      test "marks as unresolved for admin if show_to_maintainer is true" do
        @content_report_for_maintainer.resolved = true
        @content_report_for_maintainer.save!

        assert @content_report_for_maintainer.mark_unresolved(@org_admin)
        refute @content_report_for_maintainer.resolved?
      end

      test "fails for admin if show_to_maintainer is false" do
        @content_report_for_maintainer.show_to_maintainer = false
        @content_report_for_maintainer.resolved = true
        @content_report_for_maintainer.save!

        refute @content_report_for_maintainer.mark_unresolved(@org_admin)
        assert @content_report_for_maintainer.resolved?
      end

      test "fails for org member" do
        @content_report_for_maintainer.resolved = true
        @content_report_for_maintainer.save!

        refute @content_report_for_maintainer.mark_unresolved(@org_member)
        assert @content_report_for_maintainer.resolved?
      end

      test "fails for repo member" do
        @content_report_for_maintainer.resolved = true
        @content_report_for_maintainer.save!

        repo_member = create(:user)
        @org_repo.add_member(repo_member, action: :write)

        refute @content_report_for_maintainer.mark_unresolved(repo_member)
        assert @content_report_for_maintainer.resolved?
      end

      test "fails for random person" do
        @content_report_for_maintainer.resolved = true
        @content_report_for_maintainer.save!

        refute @content_report_for_maintainer.mark_unresolved(@rando)
        assert @content_report_for_maintainer.resolved?
      end

      test "is audit logged" do
        events = subscribe "repo.unresolve_abuse_report"

        expected_payload = {
          visibility: :public,
          abuse_report: @content_report_for_maintainer.id,
          repo: @org_repo.nwo,
          repo_id: @org_repo.id,
          public_repo: @org_repo.public?,
          org: @org.login,
          org_id: @org.id,
          fork_source: @org_repo.nwo,
          fork_source_id: @org_repo.id,
        }

        assert @content_report_for_maintainer.mark_unresolved(@org_admin)

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    context "mark_unresolved_for_content" do
      test "marks as unresolved for admin if show_to_maintainer is true" do
        @content_report_for_maintainer.resolved = true
        @content_report_for_maintainer.save!
        @content_report_for_maintainer2.resolved = true
        @content_report_for_maintainer2.save!

        assert AbuseReport.mark_unresolved_for_content(@org_admin, @org_repo_content.class.to_s, @org_repo_content.id)
        @content_report_for_maintainer.reload
        @content_report_for_maintainer2.reload
        refute @content_report_for_maintainer.resolved?
        refute @content_report_for_maintainer2.resolved?
      end

      test "fails for admin if show_to_maintainer on the reports is false" do
        @content_report_for_maintainer.show_to_maintainer = false
        @content_report_for_maintainer.resolved = true
        @content_report_for_maintainer.save!
        @content_report_for_maintainer2.show_to_maintainer = false
        @content_report_for_maintainer2.resolved = true
        @content_report_for_maintainer2.save!

        refute AbuseReport.mark_unresolved_for_content(@org_admin, @org_repo_content.class.to_s, @org_repo_content.id)
        @content_report_for_maintainer.reload
        @content_report_for_maintainer2.reload
        assert @content_report_for_maintainer.resolved?
        assert @content_report_for_maintainer2.resolved?
      end

      test "fails for org member" do
        @content_report_for_maintainer.resolved = true
        @content_report_for_maintainer.save!
        @content_report_for_maintainer2.resolved = true
        @content_report_for_maintainer2.save!

        refute AbuseReport.mark_unresolved_for_content(@org_member, @org_repo_content.class.to_s, @org_repo_content.id)
        @content_report_for_maintainer.reload
        @content_report_for_maintainer2.reload
        assert @content_report_for_maintainer.resolved?
        assert @content_report_for_maintainer2.resolved?
      end

      test "fails for repo member" do
        repo_member = create(:user)
        @org_repo.add_member(repo_member, action: :write)

        @content_report_for_maintainer.resolved = true
        @content_report_for_maintainer.save!
        @content_report_for_maintainer2.resolved = true
        @content_report_for_maintainer2.save!

        refute AbuseReport.mark_unresolved_for_content(repo_member, @org_repo_content.class.to_s, @org_repo_content.id)
        @content_report_for_maintainer.reload
        @content_report_for_maintainer2.reload
        assert @content_report_for_maintainer.resolved?
        assert @content_report_for_maintainer2.resolved?
      end

      test "fails for random person" do
        @content_report_for_maintainer.resolved = true
        @content_report_for_maintainer.save!
        @content_report_for_maintainer2.resolved = true
        @content_report_for_maintainer2.save!

        refute AbuseReport.mark_unresolved_for_content(@rando, @org_repo_content.class.to_s, @org_repo_content.id)
        @content_report_for_maintainer.reload
        @content_report_for_maintainer2.reload
        assert @content_report_for_maintainer.resolved?
        assert @content_report_for_maintainer2.resolved?
      end

      test "is audit logged" do
        events = subscribe "repo.unresolve_abuse_report"

        expected_payload = {
          visibility: :public,
          abuse_reports: [@content_report_for_maintainer.id, @content_report_for_maintainer2.id].sort,
          repo: @org_repo.nwo,
          repo_id: @org_repo.id,
          public_repo: @org_repo.public?,
          org: @org.login,
          org_id: @org.id,
          fork_source: @org_repo.nwo,
          fork_source_id: @org_repo.id,
        }

        assert AbuseReport.mark_unresolved_for_content(@org_admin, @org_repo_content.class.to_s, @org_repo_content.id)

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    context ".most_recent_for_each_reported_content" do
      test "excludes reports made to site admins, rather than maintainers" do
        earlier_report = @content_report_for_maintainer
        later_report = @content_report_for_maintainer2
        later_report.show_to_maintainer = false
        later_report.save!

        assert_equal AbuseReport.most_recent_for_each_reported_content(@org_repo.id), [earlier_report]
      end

      test "returns the most recent abuse report per piece of reported content, sorted in desc order" do
        Timecop.freeze do
          issue_1_earlier_report = @content_report_for_maintainer
          issue_1_later_report = @content_report_for_maintainer2

          issue_1_earlier_report.created_at = 5.minutes.ago
          issue_1_earlier_report.save!
          issue_1_later_report.created_at = 4.minutes.ago
          issue_1_later_report.save!

          issue_2 = create(:issue, repository: @org_repo)
          issue_2_earlier_report = create(:abuse_report, reported_content: issue_2, reporting_user: @org_member, repository: @org_repo, show_to_maintainer: true)
          issue_2_later_report = create(:abuse_report, reported_content: issue_2, reporting_user: @org_member2, repository: @org_repo, show_to_maintainer: true)
          issue_2_earlier_report.created_at = 3.minutes.ago
          issue_2_earlier_report.save!
          issue_2_later_report.created_at = 2.minutes.ago
          issue_2_later_report.save!

          assert_equal AbuseReport.most_recent_for_each_reported_content(@org_repo.id), [issue_2_later_report, issue_1_later_report]
        end
      end

      test "bumps the content group to the front of the list when a new report is filed on it" do
        Timecop.freeze do
          issue_1_earlier_report = @content_report_for_maintainer
          issue_1_later_report = @content_report_for_maintainer2

          issue_1_earlier_report.created_at = 5.minutes.ago
          issue_1_earlier_report.save!
          issue_1_later_report.created_at = 4.minutes.ago
          issue_1_later_report.save!

          issue_2 = create(:issue, repository: @org_repo)
          issue_2_report = create(:abuse_report, reported_content: issue_2, reporting_user: @org_member, repository: @org_repo, show_to_maintainer: true)
          issue_2_report.created_at = 8.minutes.ago
          issue_2_report.save!

          assert_equal AbuseReport.most_recent_for_each_reported_content(@org_repo.id), [issue_1_later_report, issue_2_report]

          issue_2_new_report = create(:abuse_report, reported_content: issue_2, reporting_user: @org_member2, repository: @org_repo, show_to_maintainer: true)
          issue_2_new_report.created_at = 2.minutes.ago

          assert_equal AbuseReport.most_recent_for_each_reported_content(@org_repo.id), [issue_2_new_report, issue_1_later_report]
        end
      end
    end

    context ".for_repository_maintainer" do
      test "returns reports to show maintainer" do
        @content_report_for_maintainer2.show_to_maintainer = false
        @content_report_for_maintainer2.save!

        assert_equal AbuseReport.for_repository_maintainer(@org_repo.id), [@content_report_for_maintainer]
      end
    end

    context "content_spammy?" do
      test "returns true if the abuse report related to content already flagged as spammy" do
        spam_user = create(:user, spammy: true)
        spam_content = create(:issue, repository: @org_repo, user: spam_user)
        report_on_spam = create(:abuse_report, reported_content: spam_content, reporting_user: @org_member, repository: @org_repo, show_to_maintainer: true)

        assert report_on_spam.content_spammy?
        refute @content_report_for_maintainer.spammy?
      end

      test "returns true if the abuse report is related to a comment where the top-level content is spammy" do
        spam_user = create(:user, spammy: true)
        spam_user.emails.each(&:verify!) # email verification required for discussion creation
        @org_member.emails.each(&:verify!)

        spam_issue = create(:issue, repository: @org_repo, user: spam_user)
        issue_comment = create(:issue_comment, repository: @org_repo, issue: spam_issue, user: @org_member)

        @org_repo.turn_on_discussions(actor: @org_admin, instrument: false)
        spam_discussion = create(:discussion, repository: @org_repo, user: spam_user)
        discussion_comment = create(:discussion_comment, discussion: spam_discussion, repository: @org_repo, user: @org_member)

        issue_comment_report = create(:abuse_report, reported_content: issue_comment, reporting_user: @org_member, repository: @org_repo, show_to_maintainer: true)
        discussion_comment_report = create(:abuse_report, reported_content: discussion_comment, reporting_user: @org_member, repository: @org_repo, show_to_maintainer: true)

        assert issue_comment_report.content_spammy?
        assert discussion_comment_report.content_spammy?
      end
    end

    if GitHub.sponsors_enabled?
      context "#report_sponsors_listing_abuse_report" do
        test "should mark as has_received_abuse_report on stafftools_metadata" do
          listing = create(:sponsors_listing)
          refute_predicate listing.stafftools_metadata, :has_received_abuse_report?

          create(:abuse_report, :user_report, reported_user: listing.sponsorable)

          assert_predicate listing.reload_stafftools_metadata, :has_received_abuse_report?
        end
      end
    end
  end
end
