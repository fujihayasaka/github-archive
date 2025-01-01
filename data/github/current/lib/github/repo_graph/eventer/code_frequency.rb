# typed: true
# frozen_string_literal: true

module GitHub
  module RepoGraph
    class Eventer
      class CodeFrequency
        # Time.at(0).utc is Thursday. Our week starts on Sunday, so we need to compensate for this.
        INITIAL_WEEK_OFFSET = 3.days.to_i

        # A single week, in seconds
        WEEK_TS_DELTA = 1.week.to_i

        attr_reader :eventer_metrics

        def initialize(eventer_metrics)
          @eventer_metrics = eventer_metrics
        end

        # Public: Formats the eventer data for use by the code frequency graph
        #   in the repo insights tab.
        #
        # Example:
        #
        #   contributors.to_graph
        #   => [
        #        [1296950400, 45, -3]
        #      …
        #   ]
        #
        # Returns an Array of Hashes with metrics for each author.
        def to_graph
          return [] if eventer_metrics.empty? || eventer_metrics.values.all?(&:empty?)

          week_counts_map = Hash.new { |hash, week_start| hash[week_start] = [week_start, 0, 0] }

          CODE_FREQUENCY_EVENTS.each do |metric|
            eventer_metrics[metric].each do |day_ts, operation_count|
              week_ts = week_start(day_ts)

              if metric == ADDITIONS
                week_counts_map[week_ts][1] += operation_count
              else
                week_counts_map[week_ts][2] -= operation_count
              end
            end
          end

          pad_weeks(week_counts_map)
        end

        private

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

        # Internal: Each week between the first week and now must have data for the client to
        #  display things correctly. This method ensures each week is populated.
        #
        #  Returns a non-sparse array for the weekly addition and deletion count, sorted by date.
        def pad_weeks(week_counts_map)
          first_week = week_counts_map.keys.min
          current_week = week_start(Time.now.to_i)

          (first_week..current_week).step(WEEK_TS_DELTA) do |week_ts|
            # Simply accessing the hash will trigger the default block to run and create
            # empty data for the week. Hurray for side effects!
            week_counts_map[week_ts]
          end

          week_counts_map.values.sort
        end
      end
    end
  end
end
