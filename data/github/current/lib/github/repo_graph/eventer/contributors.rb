# typed: false
# frozen_string_literal: true

module GitHub
  module RepoGraph
    class Eventer
      class Contributors
        # Time.at(0).utc is Thursday. Our week starts on Sunday, so we need to compensate for this.
        INITIAL_WEEK_OFFSET = 3.days.to_i

        # A single week, in seconds
        WEEK_TS_DELTA = 1.week.to_i

        attr_reader :eventer_metrics, :current_week

        def initialize(eventer_metrics, business)
          @eventer_metrics = eventer_metrics
          @business = business
          @current_week = week_start(Time.now.to_i)
        end

        # Public: Formats the eventer data for use by the contributors graph
        #   in the repo insights tab.
        #
        # Example:
        #
        #   contributors.to_graph
        #   => [
        #      {
        #        total: => 42
        #        author: {
        #          id: 1,
        #          login: "monalisa",
        #          avatar: "https://avatars1.githubusercontent.com/u/1",
        #          path: "/monalisa",
        #          hovercard_url: "/users/monalisa/hovercard"
        #        }
        #        weeks: [
        #          {w:"1367712000", a:3, d:0, c:2},
        #          {w:"1367716800", a:11, d:4, c:5},
        #          ...
        #        ]
        #      },
        #      …
        #   ]
        #
        # Returns an Array of Hashes with metrics for each author.
        def to_graph
          return [] if eventer_metrics.empty? || eventer_metrics.values.all?(&:empty?)

          weekly_metrics = rollup_weekly_metrics
          top_contributors = Set.new(weekly_metrics.values).first(100).reverse
          pad_weeks(top_contributors) # TODO: Update client-side graph code to handle non-padded data

          top_contributors.map(&:to_graph)
        end

        private

        def rollup_weekly_metrics
          author_entries = Hash.new { |hash, author| hash[author] = AuthorEntry.new(author: author) }
          user_promises = []

          CONTRIBUTOR_DATA_EVENTS.each do |metric|
            eventer_metrics[metric].each do |author_emails, daily_metrics|
              counted_emails = []
              author_emails.split(",").each do |email| # duplicate metrics for each co-author
                user_promises << Platform::Loaders::UserByEmail.load(email, business: @business).then do |user|
                  next unless user
                  author_entry = author_entries[user]

                  # Prevent multiple emails for a single user resulting in duplicate metrics
                  next if (author_entry.emails & counted_emails).any?
                  author_entry.emails << email
                  counted_emails << email

                  daily_metrics.each do |day_ts, count|
                    week_ts = week_start(day_ts)

                    # disregard metrics from the future.
                    next if week_ts > current_week

                    author_entry.increment(metric, by: count, week: week_ts)
                  end
                end
              end
            end
          end

          Promise.all(user_promises).sync
          author_entries
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

        def pad_weeks(author_entries)
          return if author_entries.empty?

          first_week = author_entries.flat_map { |author| author.weeks.keys }.min

          (first_week..current_week).step(1.week.to_i) do |week_ts|
            author_entries.each { |author| author.weeks[week_ts] }
          end
        end

        class AuthorEntry
          include AvatarHelper
          include UrlHelper

          METRIC_KEYS = {
            ADDITIONS => :a,
            DELETIONS => :d,
            COMMITS => :c,
          }.freeze

          attr_reader :author, :weeks, :emails
          attr_accessor :total

          def initialize(author:)
            @author = author
            @total = 0
            @weeks = Hash.new { |hash, week_ts| hash[week_ts] = { w: week_ts, a: 0, d: 0, c: 0 } }
            @emails = Set.new
          end

          def increment(metric, by: 1, week:)
            metric_key = METRIC_KEYS[metric]
            self.total += by if metric_key == :c
            weeks[week][metric_key] += by
          end

          def <=>(other)
            [-total, author.display_login] <=> [-other.total, other.author.display_login]
          end

          def to_graph
            {
              total: total,
              author: {
                id: author.id,
                login: author.display_login,
                avatar: avatar_url_for(author, 60),
                path: user_path(author),
                hovercard_url: HovercardHelper.user_hovercard_path(user_login: author.display_login),
              },
              weeks: weeks.values.sort_by { |w| w[:w] },
            }
          end
        end
      end
    end
  end
end
