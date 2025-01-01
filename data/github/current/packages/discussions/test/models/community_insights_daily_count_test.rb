# typed: true
# frozen_string_literal: true

require "test_helper"

class CommunityInsightsDailyCountTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  context "validations" do
    test "requires a repository" do
      count = build(:community_insights_daily_count, repository: nil)
      refute_predicate count, :valid?
    end

    test "requires a date" do
      count = build(:community_insights_daily_count, entry_date: nil)
      refute_predicate count, :valid?
    end

    test "must specify at least one nonzero count" do
      count = build(:community_insights_daily_count, repository: @repo)
      count.discussions_count = 0
      count.issues_count = 0
      count.pull_requests_count = 0
      count.discussion_contributors_count = 0
      count.discussion_new_contributor_count = 0

      refute_predicate count, :valid?
    end
  end

  context ".increment" do
    test "creates and increments a count record for a given repository and day" do
      assert_difference -> { CommunityInsightsDailyCount.count }, 1 do
        CommunityInsightsDailyCount.increment(@repo.id, Date.today, :issues_count)
      end

      count = CommunityInsightsDailyCount.where(repository_id: @repo.id).last
      count = T.must(count)
      refute_nil count
      assert_equal 1, count.issues_count

      assert_equal 0, count.discussions_count
      assert_equal 0, count.pull_requests_count
      assert_equal 0, count.discussion_contributors_count
      assert_equal 0, count.discussion_new_contributor_count
      refute_nil count.updated_at
      refute_nil count.created_at
    end

    test "increments an existing count record" do
      day = Date.today - 1.day
      existing = travel_to(day) do
        create(:community_insights_daily_count, repository: @repo, entry_date: day, discussions_count: 1)
      end
      old_created_at = existing.created_at
      old_updated_at = existing.updated_at

      assert_no_difference -> { CommunityInsightsDailyCount.count } do
        CommunityInsightsDailyCount.increment(@repo.id, day, :discussions_count)
      end

      assert_equal 2, existing.reload.discussions_count

      assert_equal 0, existing.issues_count
      assert_equal 0, existing.pull_requests_count
      assert_equal 0, existing.discussion_contributors_count
      assert_equal 0, existing.discussion_new_contributor_count

      assert_equal old_created_at, existing.created_at, "should not have changed created_at"
      assert_operator old_updated_at, :<, existing.updated_at, "should have bumped updated_at"
    end
  end

  context ".set_count" do
    test "creates and populates a count record for a given repository and day" do
      count = assert_difference -> { CommunityInsightsDailyCount.count }, 1 do
        CommunityInsightsDailyCount.set_count(@repo.id, Date.today, :pull_requests_count, 47)
      end

      assert_equal 47, count.pull_requests_count

      assert_equal 0, count.issues_count
      assert_equal 0, count.discussions_count
      assert_equal 0, count.discussion_contributors_count
      assert_equal 0, count.discussion_new_contributor_count
    end

    test "overwrites a count in an existing count record" do
      day = Date.today
      existing = create(:community_insights_daily_count, repository: @repo, entry_date: day,
        discussion_contributors_count: 10, discussion_new_contributor_count: 5)

      count = assert_no_difference -> { CommunityInsightsDailyCount.count } do
        CommunityInsightsDailyCount.set_count(@repo.id, day, :discussion_contributors_count, 18)
      end

      assert_equal count.id, existing.id

      assert_equal 18, count.discussion_contributors_count
      assert_equal 5, count.discussion_new_contributor_count

      assert_equal 0, count.discussions_count
      assert_equal 0, count.issues_count
      assert_equal 0, count.pull_requests_count
    end

    test "does not create a count record when setting a new count to zero" do
      assert_no_difference -> { CommunityInsightsDailyCount.count } do
        CommunityInsightsDailyCount.set_count(@repo.id, Date.today, :issues_count, 0)
      end
    end

    test "deletes an existing count record when setting its last count to zero" do
      day = Date.today
      create(:community_insights_daily_count, repository: @repo, entry_date: day, issues_count: 5)

      assert_difference -> { CommunityInsightsDailyCount.count }, -1 do
        CommunityInsightsDailyCount.set_count(@repo.id, day, :issues_count, 0)
      end

      assert_nil CommunityInsightsDailyCount.find_by(repository: @repo, entry_date: day)
    end
  end

  context ".all_for_period" do
    test "collects counts for the past 30 days" do
      build_list(:community_insights_daily_count, 3, repository: @repo) do |count, index|
        count.entry_date = ((index + 1) * 10).days.ago
        count.save!
      end

      wrong_repo = create(:community_insights_daily_count, entry_date: Date.today)
      too_old = create(:community_insights_daily_count, repository: @repo, entry_date: 35.days.ago)

      counts = CommunityInsightsDailyCount.all_for_period(@repo, :last_30_days)

      # Note: we avoid asserting the exact contents of counts here to avoid time-based flakiness.
      refute_empty counts
      assert_operator counts.first.entry_date, :<, counts.last.entry_date
      refute_includes counts, wrong_repo
      refute_includes counts, too_old
    end

    test "collects counts for the past quarter" do
      build_list(:community_insights_daily_count, 4, repository: @repo) do |count, index|
        count.entry_date = (index * 30).days.ago
        count.save!
      end

      wrong_repo = create(:community_insights_daily_count, entry_date: Date.today)
      too_old = create(:community_insights_daily_count, repository: @repo, entry_date: 95.days.ago)

      counts = CommunityInsightsDailyCount.all_for_period(@repo, :last_3_months)

      # Note: we avoid asserting the exact contents of counts here to avoid time-based flakiness.
      refute_empty counts
      assert_operator counts.first.entry_date, :<, counts.last.entry_date
      refute_includes counts, wrong_repo
      refute_includes counts, too_old
    end

    test "collects counts for the past year" do
      build_list(:community_insights_daily_count, 4, repository: @repo) do |count, index|
        count.entry_date = (index * 100).days.ago
        count.save!
      end
      create(:community_insights_daily_count, repository: @repo, entry_date: 365.days.ago)

      wrong_repo = create(:community_insights_daily_count, entry_date: Date.today)
      too_old = create(:community_insights_daily_count, repository: @repo, entry_date: 370.days.ago)

      counts = CommunityInsightsDailyCount.all_for_period(@repo, :last_year)

      # Note: we avoid asserting the exact contents of counts here to avoid time-based flakiness.
      refute_empty counts
      assert_operator counts.first.entry_date, :<, counts.last.entry_date
      refute_includes counts, wrong_repo
      refute_includes counts, too_old
    end
  end
end
