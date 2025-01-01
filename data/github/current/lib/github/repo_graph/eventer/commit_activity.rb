# typed: true
# frozen_string_literal: true

module GitHub
  module RepoGraph
    class Eventer
      class CommitActivity
        # Time.at(0).utc is Thursday. Our week starts on Sunday, so we need to compensate for this.
        INITIAL_WEEK_OFFSET = 3.days.to_i

        # A single week, in seconds
        WEEK_TS_DELTA = 1.week.to_i

        # A single day, in seconds
        DAY_TS_DELTA = 1.day.to_i

        attr_reader :eventer_metrics, :first_week, :current_week

        def initialize(eventer_metrics)
          @eventer_metrics = eventer_metrics
          @first_week = week_start(52.weeks.ago)
          @current_week = week_start(Time.now)
        end

        # Public: Formats the eventer data for use by the commits graph
        #   in the repo insights tab.
        #
        # Example:
        #
        #   commit_activity.to_graph
        #   => [
        #     {week: 1367712000, total: 10, days: [0, 2, 3, 0, 0, 5, 0]},
        #     {week: 1367716800, total: 12, days: [0, 2, 0, 0, 0, 4, 6]},
        #     …
        #   ]
        #
        # Returns an Array of Hashes for last 52 weeks of commit activity.
        def to_graph
          weekly_metrics = rollup_weekly_metrics
          pad_weeks(weekly_metrics)
          last_52_weeks = weekly_metrics.values.sort.last(52)

          last_52_weeks.map(&:to_graph)
        end

        private

        def rollup_weekly_metrics
          weeks = Hash.new { |hash, week_ts| hash[week_ts] = Week.new(week: week_ts) }

          counts = eventer_metrics[COMMITS]
          return weeks if counts.nil?

          counts.each do |day_ts, count|
            week_ts = week_start(day_ts)
            next unless week_ts.between?(first_week, current_week)

            weeks[week_ts].increment(day: wday(day_ts), by: count)
          end

          weeks
        end

        # Internal: Calculate the timestamp for the beginning of the week (first second in Sunday, UTC)
        #   belonging to the given timestamp.
        #
        # day_ts - an integer (or something that responds to `to_i`) representing an epoch offset.
        #
        # Returns the epoch offset of the last Sunday before the given day_ts.
        def week_start(day_ts)
          day_ts = day_ts.to_i

          # timestamp since "first Sunday" (Dec 28th, 1969)
          adjusted_ts = day_ts - INITIAL_WEEK_OFFSET

          # how far are we passed the latest Sunday?
          offset_beyond_sunday = adjusted_ts % WEEK_TS_DELTA

          # subtract that offset into the week to get the latest sunday week timestamp
          day_ts - offset_beyond_sunday
        end

        def wday(day_ts)
          day_ts = day_ts.to_i

          # timestamp since "first Sunday" (Dec 28th, 1969)
          adjusted_ts = day_ts - INITIAL_WEEK_OFFSET

          # how far are we passed the latest Sunday?
          offset_beyond_sunday = adjusted_ts % WEEK_TS_DELTA

          # How many days since then?
          offset_beyond_sunday / DAY_TS_DELTA
        end

        # Internal: Each week between the first week and now must have data for the client to
        #  display things correctly. This method ensures each week is populated.
        #
        #  Returns nothing.
        def pad_weeks(weeks)
          (first_week..current_week).step(WEEK_TS_DELTA) do |week_ts|
            # Simply accessing the hash will trigger the default block to run and create
            # empty data for the week. Hurray for side effects!
            weeks[week_ts]
          end
        end

        class Week
          attr_reader :week, :days
          attr_accessor :total

          def initialize(week:)
            @week = week
            @total = 0
            @days = [0] * 7
          end

          def increment(day:, by: 1)
            self.total += by
            days[day] += by
          end

          def <=>(other)
            week <=> other.week
          end

          def to_graph
            {
              total: total,
              week: week,
              days: days,
            }
          end
        end
      end
    end
  end
end
