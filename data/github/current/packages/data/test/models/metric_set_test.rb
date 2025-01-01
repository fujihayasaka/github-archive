# typed: true
# frozen_string_literal: true

require "test_helper"

class MetricSetTest < GitHub::TestCase
  def make_five_issues_close_one
    4.times { create :issue }
    create(:issue).close
  end

  test "#as_json returns hash representation of metric" do
    GitHub.flipper[:metric_query_kv].disable
    travel_to Time.zone.parse("2022-05-30 01:02:03") do
      make_five_issues_close_one

      timespan = MetricTimespan::Week.new
      hash = MetricSet.build(%w[issues_closed issues_created], timespan: timespan).
        tap { |set| set.each(&:reload!) }. # force fresh query read
        as_json

      assert_equal timespan, hash[:timespan]

      issues_closed, issues_created = hash[:metrics].as_json

      assert_equal "issues_closed", issues_closed[:name]
      assert_equal 1, issues_closed[:total]
      assert_equal 1, issues_closed[:max]
      assert_equal 1, issues_closed[:total_change]
      assert_equal 100, issues_closed[:percent_change]

      assert_equal "issues_created", issues_created[:name]
      assert_equal 5, issues_created[:total]
      assert_equal 5, issues_created[:max]
      assert_equal 5, issues_created[:total_change]
      assert_equal 500, issues_created[:percent_change]
    end
  end


  context "#percentages" do
    test "#percentages returns zeroes when no activity exists" do
      timespan = MetricTimespan::Week.new
      metrics = MetricSet.build(%w[issues_closed issues_created], timespan: timespan).
        tap { |set| set.each(&:reload!) } # force fresh query read

      assert_equal 0, metrics.percentages(&:by_display_name)["Issues"]
      assert_equal 0, metrics.percentages(&:by_display_name)["Issues Closed"]
    end

    test "percents should add up to 100" do
      travel_to Time.zone.parse("2022-05-30 01:02:03") do
        user = create(:user, plan: :silver)
        repo = create(:repository, owner: user)

        # Create issues
        create_list(:issue, 3, user: user, repository: repo)

        # create commits
        CommitContribution.create \
          repository: repo,
          user: user,
          commit_count: 1,
          committed_date: Time.zone.today

        # Create pull request
        pr = create(:pull_request, :disable_disk_access, user: user)

        # Create code review
        # The :commented trait is required here since the default is pending and won't show up
        # as a contribution.
        create(:pull_request_review, :disable_disk_access, :commented, user: user, pull_request: pr)

        # 3 issues | 1 commit | 1 pull request | 1 code review
        # When using #round on percents we get 50,17,17,17 for a total of 101.
        # When using #floored on percents we get 50,16,16,16 for a total of 98.

        timespan = MetricTimespan::Week.new
        metrics = MetricSet.build(%w[pull_request_reviews_created issues_created pull_requests_created commits_contributed], timespan: timespan, owner_id: user.id).
          tap { |set| set.each(&:reload!) } # force fresh query read

        total = metrics.percentages(&:by_display_name).sum { |p| p[1] }

        assert_equal 100, total
      end
    end
  end

  context "#by_name" do
    test "creates a hash of the metrics index by name" do
      metrics = [Metric.build(:issues_created), Metric.build(:issues_closed)]
      metrics.each(&:reload!) # force fresh query read
      set = MetricSet.new(metrics)

      assert_equal({ "issues_created" => metrics.first,
                     "issues_closed" => metrics.second },
                     set.by_name)
    end

    test "transforms the metrics via provided block" do
      travel_to Time.zone.parse("2022-05-30 01:02:03") do
        create(:issue)
        metrics = [Metric.build(:issues_created), Metric.build(:issues_closed)]
        metrics.each(&:reload!) # force fresh query read
        set = MetricSet.new(metrics)

        assert_equal({ "issues_created" => 1,
                       "issues_closed" => 0 },
                       set.by_name(&:total))
      end
    end
  end

  context "#by_display_name" do
    test "creates a hash of the metrics index by display name" do
      metrics = [Metric.build(:issues_created), Metric.build(:issues_closed)]
      metrics.each(&:reload!) # force fresh query read
      set = MetricSet.new(metrics)

      assert_equal({ "Issues" => metrics.first,
                     "Issues Closed" => metrics.second },
                     set.by_display_name)
    end

    test "transforms the metrics via provided block" do
      travel_to Time.zone.parse("2022-05-30 01:02:03") do
        create(:issue)
        metrics = [Metric.build(:issues_created), Metric.build(:issues_closed)]
        metrics.each(&:reload!) # force fresh query read
        set = MetricSet.new(metrics)

        assert_equal({ "Issues" => 1,
                       "Issues Closed" => 0 },
                       set.by_display_name(&:total))
      end
    end
  end

  context ".build" do
    test "accepts multiple query names" do
      MetricSet.build(%w[issues_closed issues_created])
    end

    test "accepts single query name" do
      MetricSet.build(:issues_closed)
    end

    test "accepts empty query names" do
      MetricSet.build
      MetricSet.build(nil)
      MetricSet.build([])
    end

    test "raises when given invalid query name" do
      assert_raises NameError do
        MetricSet.build(:invalid_metric_name)
      end
    end
  end
end
