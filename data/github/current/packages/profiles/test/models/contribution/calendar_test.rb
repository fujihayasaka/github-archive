# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionCalendarTest < GitHub::TestCase
  include CommitTestHelper

  fixtures do
    # Ensure all the fixture data is created in the expected time range
    # so tests are cool with running at a midnight boundary.
    @now = Time.zone.now.freeze
    @today = @now.to_date.freeze
    @repo = create(:repository)
    @user = create(:user, login: "ari", plan: "medium", created_at: @now - 1.week)
  end

  setup do
    @collector = Contribution::Collector.new(
      user: @user,
      time_range: Contribution::Calendar.time_range_ending_on(@now),
      viewer: @user,
      lightweight: true,
    )
    @calendar = Contribution::Calendar.new(collector: @collector)
  end

  def build_calendar(user:, to: Time.zone.today, viewer: nil, organization_id: nil)
    collector = Contribution::Collector.new(
      user: user,
      time_range: Contribution::Calendar.time_range_ending_on(to),
      viewer: viewer,
      organization_id: organization_id,
      lightweight: true,
    )
    Contribution::Calendar.new(collector: collector)
  end

  context "#user_login" do
    test "returns login of the calendar user" do
      assert_equal @user.login, @calendar.user_login
    end
  end

  context "#quantile" do
    test "handles nil counts" do
      collector = Contribution::Collector.new(
        user: @user,
        time_range: Time.zone.today..Time.zone.today,
        viewer: @user,
        organization_id: nil,
        lightweight: true,
      )
      calendar = Contribution::Calendar.new(collector: collector)
      OutlierFilter.any_instance.stubs(:filter).returns([])

      refute_nil calendar.quantile
    end
  end

  context "#colors" do
    test "returns to normal contribution colors for the 11th month" do
      Time.use_zone("Australia/Sydney") do
        time = Time.zone.local(2014, 11, 1)

        Timecop.freeze(time) do
          assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
        end
      end

      Time.use_zone("Australia/Sydney") do
        time = Time.zone.local(2014, 10, 30, 23, 59, 59)

        Timecop.freeze(time) do
          assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
        end
      end
    end

    test "uses special colors for Halloween" do
      Time.use_zone("Australia/Sydney") do
        time = Time.zone.local(2014, 10, 31)

        Timecop.freeze(time) do
          assert_equal Contribution::Calendar::HALLOWEEN_COLORS, @calendar.colors
        end
      end
    end

    context "when the winter theme feature flag is enabled" do
      context "when it's the northern hemisphere" do
        context "when it's 21st of December" do
          test "uses winter colors" do
            Time.use_zone("Europe/London") do
              # time_zone_name is set when we create the user object, so we need to update it here
              @calendar.viewer.time_zone_name = Time.zone.name
              enable_feature_flag(:contribution_graph_winter_theme, @calendar.viewer)
              time = Time.zone.local(2014, 12, 21)

              Timecop.freeze(time) do
                assert_equal Contribution::Calendar::WINTER_COLORS, @calendar.colors
              end
            end
          end
        end

        context "when it's not 21st of December" do
          test "uses normal colors" do
            Time.use_zone("Europe/London") do
              # time_zone_name is set when we create the user object, so we need to update it here
              @calendar.viewer.time_zone_name = Time.zone.name
              enable_feature_flag(:contribution_graph_winter_theme, @calendar.viewer)
              time = Time.zone.local(2014, 12, 23)

              Timecop.freeze(time) do
                assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
              end
            end
          end
        end
      end

      context "when it's the southern hemisphere" do
        context "when it's 21st of June" do
          test "uses winter colors" do
            Time.use_zone("Australia/Sydney") do
              # time_zone_name is set when we create the user object, so we need to update it here
              @calendar.viewer.time_zone_name = Time.zone.name
              enable_feature_flag(:contribution_graph_winter_theme, @calendar.viewer)
              time = Time.zone.local(2014, 06, 21)

              Timecop.freeze(time) do
                assert_equal Contribution::Calendar::WINTER_COLORS, @calendar.colors
              end
            end
          end
        end

        context "when it's not 21st of June" do
          test "uses normal colors" do
            Time.use_zone("Australia/Sydney") do
              # time_zone_name is set when we create the user object, so we need to update it here
              @calendar.viewer.time_zone_name = Time.zone.name
              enable_feature_flag(:contribution_graph_winter_theme, @calendar.viewer)
              time = Time.zone.local(2014, 06, 23)

              Timecop.freeze(time) do
                assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
              end
            end
          end
        end
      end

      context "when we don't know the viewer's time zone" do
        context "when it's 21st of December" do
          test "uses normal colors" do
            enable_feature_flag(:contribution_graph_winter_theme, @calendar.viewer)
            time = Time.zone.local(2014, 12, 21)

            Timecop.freeze(time) do
              assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
            end
          end
        end

        context "when it's 21st of June" do
          test "uses normal colors" do
            enable_feature_flag(:contribution_graph_winter_theme, @calendar.viewer)
            time = Time.zone.local(2014, 06, 21)

            Timecop.freeze(time) do
              assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
            end
          end
        end

        context "when it's not 21st of December of 21st of June" do
          test "uses normal colors" do
            enable_feature_flag(:contribution_graph_winter_theme, @calendar.viewer)
            time = Time.zone.local(2014, 12, 23)

            Timecop.freeze(time) do
              assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
            end
          end
        end
      end
    end

    context "when the winter theme feature flag is disabled" do
      context "when it's the northern hemisphere" do
        context "when it's 21st of December" do
          test "uses normal colors" do
            Time.use_zone("Europe/London") do
              # time_zone_name is set when we create the user object, so we need to update it here
              @calendar.viewer.time_zone_name = Time.zone.name
              disable_feature_flag(:contribution_graph_winter_theme)
              time = Time.zone.local(2014, 12, 21)

              Timecop.freeze(time) do
                assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
              end
            end
          end
        end

        context "when it's not 21st of December" do
          test "uses normal colors" do
            Time.use_zone("Europe/London") do
              # time_zone_name is set when we create the user object, so we need to update it here
              @calendar.viewer.time_zone_name = Time.zone.name
              disable_feature_flag(:contribution_graph_winter_theme)
              time = Time.zone.local(2014, 12, 23)

              Timecop.freeze(time) do
                assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
              end
            end
          end
        end
      end

      context "when it's the southern hemisphere" do
        context "when it's 21st of June" do
          test "uses normal colors" do
            Time.use_zone("Australia/Sydney") do
              # time_zone_name is set when we create the user object, so we need to update it here
              @calendar.viewer.time_zone_name = Time.zone.name
              disable_feature_flag(:contribution_graph_winter_theme)
              time = Time.zone.local(2014, 06, 21)

              Timecop.freeze(time) do
                assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
              end
            end
          end
        end

        context "when it's not 21st of June" do
          test "uses normal colors" do
            Time.use_zone("Australia/Sydney") do
              # time_zone_name is set when we create the user object, so we need to update it here
              @calendar.viewer.time_zone_name = Time.zone.name
              disable_feature_flag(:contribution_graph_winter_theme)
              time = Time.zone.local(2014, 06, 23)

              Timecop.freeze(time) do
                assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
              end
            end
          end
        end
      end

      context "when we don't know the viewer's time zone" do
        context "when it's 21st of December" do
          test "uses normal colors" do
            disable_feature_flag(:contribution_graph_winter_theme)
            time = Time.zone.local(2014, 12, 21)

            Timecop.freeze(time) do
              assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
            end
          end
        end

        context "when it's 21st of June" do
          test "uses normal colors" do
            disable_feature_flag(:contribution_graph_winter_theme)
            time = Time.zone.local(2014, 06, 21)

            Timecop.freeze(time) do
              assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
            end
          end
        end

        context "when it's not 21st of December of 21st of June" do
          test "uses normal colors" do
            disable_feature_flag(:contribution_graph_winter_theme)
            time = Time.zone.local(2014, 12, 23)

            Timecop.freeze(time) do
              assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
            end
          end
        end
      end


    end

    context "when the winter theme feature flag is enabled for a different user" do
      context "when it's the northern hemisphere" do
        context "when it's 21st of December" do
          test "uses normal colors" do
            Time.use_zone("Europe/London") do
              # time_zone_name is set when we create the user object
              @different_user = create(:user, login: "ari2", plan: "medium", created_at: @now - 1.week)

              enable_feature_flag(:contribution_graph_winter_theme, @different_user)
              time = Time.zone.local(2014, 12, 21)

              Timecop.freeze(time) do
                assert_equal Contribution::Calendar::DEFAULT_COLORS, @calendar.colors
              end
            end
          end
        end
      end
    end
  end

  context "#days" do
    test "does not include future contributions" do
      future_time = 1.week.from_now
      create :issue, repository: @repo,
        user: @user,
        created_at: future_time,
        contributed_at: future_time

      calendar = build_calendar(user: @user)

      refute calendar.days.map(&:first).include?(future_time.to_date),
        "Future date #{future_time.to_date} should not be included"
    end

    test "does not skip any days" do
      days = @calendar.days

      diffs = []
      days.each_cons(2) do |a, b|
        diffs << (b.first - a.first).to_i # difference in days
      end
      diffs.uniq!

      assert_equal [1], diffs,
        "Expected a difference of 1 day between each date in contribution graph"
    end

    test "days are consecutive" do
      Time.use_zone "Australia/Melbourne" do
        create :issue, repository: @repo, user: @user, contributed_at: Time.zone.now

        days = @calendar.days

        diffs = []
        days.each_cons(2) do |a, b|
          diffs << (b.first - a.first).to_i # difference in days
        end
        diffs.uniq!

        assert_equal [1], diffs,
          "Expected a difference of 1 day between each date in contribution graph"
      end
    end

    test "counts contribution on timezone aware day" do
      created_at = Time.utc(@today.year, @today.month, @today.day, 21).localtime
      contributed_at_melbourne = created_at.in_time_zone(ActiveSupport::TimeZone["Australia/Melbourne"])
      contributed_at_amsterdam = created_at.in_time_zone(ActiveSupport::TimeZone["Europe/Amsterdam"])
      contributed_at_pacific   = created_at.in_time_zone(ActiveSupport::TimeZone["America/Los_Angeles"])
      contributed_dates = [contributed_at_melbourne, contributed_at_amsterdam, contributed_at_pacific]
      contributed_dates.each do |contributed_at|
        create :issue, repository: @repo,
          user: @user,
          created_at: created_at,
          contributed_at: contributed_at
      end

      Timecop.freeze(created_at) do
        Time.use_zone "Australia/Melbourne" do
          calendar = build_calendar(
            user:   @user,
            viewer: @user,
          )

          days = calendar.days
          last = days[-1]
          assert_equal contributed_at_melbourne.to_date, last[0]
          assert_equal 1, last[1]

          second_last = days[-2]
          assert_equal contributed_at_amsterdam.to_date, second_last[0]
          assert_equal contributed_at_pacific.to_date, second_last[0]
          assert_equal 2, second_last[1]
        end
      end
    end

    test "does not filter data by viewer when private contribs included" do
      Timecop.freeze("2016-10-25T23:57:02Z") do
        user = create(:user, :show_private_contributions, plan: "medium", created_at: 1.week.ago)
        private_repo = create(:private_repository, owner: user,
                                       created_at: 1.week.ago)
        create :issue, repository: private_repo, user: user,
                   created_at: Time.zone.now,
                   contributed_at: Time.zone.now

        calendar = build_calendar(user: user, viewer: create(:user))
        assert_equal 1, calendar.days.last[1]
      end
    end

    test "filters calendar data by the viewer when private contribs excluded" do
      user = create(:user, plan: "medium", created_at: @now - 4.days)
      profile_settings = user.profile_settings
      private_repo = create :private_repository, owner: user
      create :issue, repository: private_repo,
        user: user,
        created_at: @now,
        contributed_at: @now

      profile_settings.show_private_contribution_count = false

      calendar = build_calendar(
        user:   user,
        viewer: create(:user),
      )
      assert_equal 0, calendar.days.last[1]
    end

    test "includes yesterday's count" do
      user = create(:user)
      repo = create(:repository, owner: user, created_at: 3.days.ago)

      Time.use_zone("America/Los_Angeles") do
        yesterday = Time.zone.now.beginning_of_day - 1.day

        create :commit_contribution, :with_summaries,
            repository: repo,
            user: user,
            commit_count: 2,
            committed_date: yesterday

        calendar = build_calendar(
          user:   user,
          viewer: user,
        )

        fresh_days = Hash[calendar.days]
        assert_equal 2, fresh_days[yesterday.to_date],
            "Should see contribution from #{yesterday.to_date} in data"
      end
    end

    test "goes up to current day if no recent contributions" do
      Timecop.freeze("2016-10-25T23:57:02Z") do
        user = create(:user)
        repo = create(:repository, owner: user)
        create(:issue, repository: repo, user: user,
                   contributed_at: 1.day.ago)

        calendar = build_calendar(user: user, viewer: user)
        assert_equal Date.current, calendar.days[-1].first,
            "Latest date should be today, not date of yesterday's contribution"
      end
    end

    test "filters contributions to those within an organization if specified" do
      Timecop.freeze("2016-10-25T23:57:02Z") do
        org = create(:organization)
        other_org = create(:organization)
        user = create(:user, created_at: 1.week.ago)

        org_repo = create(:repository, owner: org, created_at: 1.week.ago)
        non_org_repo = create(:repository, owner: user, created_at: 1.week.ago)
        other_org_repo = create(:repository, owner: other_org, created_at: 1.week.ago)

        create(:issue, repository: org_repo, user: user,
               created_at: Time.zone.now, contributed_at: Time.zone.now)
        create(:issue, repository: non_org_repo, user: user,
               created_at: Time.zone.now, contributed_at: Time.zone.now)
        create(:issue, repository: other_org_repo, user: user,
               created_at: Time.zone.now, contributed_at: Time.zone.now)

        calendar = build_calendar(user: user, viewer: create(:user), organization_id: org.id)
        assert_equal 1, calendar.days.last[1]
      end
    end

    test "returns contributions within the last year by default" do
      calendar = build_calendar(user: @user)
      to = Time.zone.today
      from = (to - 1.year).beginning_of_week(:sunday)
      days = calendar.days

      assert_equal from.to_date, days.first[0]
      assert_equal to.to_date, days.last[0]
    end

    test "returns contributions from a year before the specified 'to' date" do
      to = 5.weeks.ago
      ends_on_last_day_of_year = to.end_of_year.to_date == to.to_date
      from = if ends_on_last_day_of_year
        to.beginning_of_year.beginning_of_week(:sunday)
      else
        (to - 1.year).beginning_of_week(:sunday)
      end
      calendar = build_calendar(user: @user, to: to)
      days = calendar.days

      assert_equal to.to_date, days.last.first
      assert_equal from.to_date, days.first.first
    end

    test "returns contributions from a year before the specified 'to' date at the end of the year" do
      to = Date.new(2023, 12, 31)
      from = to.beginning_of_year.beginning_of_week(:sunday)
      calendar = build_calendar(user: @user, to: to)
      days = calendar.days

      assert_equal to.to_date, days.last.first
      assert_equal from.to_date, days.first.first
    end

    test "returns contributions from a year before the specified 'to' date NOT at the end of the year" do
      to = Date.new(2023, 12, 30)
      from = (to - 1.year).beginning_of_week(:sunday)
      calendar = build_calendar(user: @user, to: to)
      days = calendar.days

      assert_equal to.to_date, days.last.first
      assert_equal from.to_date, days.first.first
    end
  end

  context "#total_contributions" do
    test "returns the total count of contributions for the user" do
      user = create(:user)
      repo = create :repository, owner: user
      create :issue, repository: repo,
        user: user,
        created_at: @now,
        contributed_at: @now

      create :issue, repository: repo,
        user: user,
        created_at: @now,
        contributed_at: @now

      calendar = build_calendar(user: user)
      assert_equal 4, calendar.total_contributions,
          "Should include user signup, repo creation, issue creation"
    end

    test "returns 1 if no contributions exist for the user other than signup" do
      user = create(:user)
      calendar = build_calendar(user: user)
      assert_equal 1, calendar.total_contributions
    end

    test "does not include CreatedIssueComment contributions" do
      user = create(:user)
      Timecop.freeze(2016, 10, 1) do
        repo = create(:repository, owner: user)
        issue = create(:issue, repository: repo, user: user)
        create(:issue_comment, issue: issue, user: user)
        calendar = build_calendar(user: user)

        assert_equal 2, calendar.total_contributions
      end
    end
  end

  context ".time_range_ending_on" do
    test "returns Jan 1 - Dec 31 if given Dec 31, 2012" do
      ending_on = Time.zone.local(2012, 12, 31)
      time_range = Contribution::Calendar.time_range_ending_on(ending_on)

      # January 1st is a sunday
      assert_equal Time.zone.local(2012, 1, 1).beginning_of_day, time_range.begin
      assert_equal Time.zone.local(2012, 12, 31).end_of_day, time_range.end
    end

    test "returns Aug 20, 2017 - Aug 22, 2018 if given Aug 22, 2018" do
      ending_on = Time.zone.local(2018, 8, 22)
      time_range = Contribution::Calendar.time_range_ending_on(ending_on)

      assert_equal Time.zone.local(2017, 8, 20).beginning_of_day, time_range.begin
      assert_equal Time.zone.local(2018, 8, 22).end_of_day, time_range.end
    end
  end
end
