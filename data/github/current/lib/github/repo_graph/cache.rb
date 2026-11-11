# typed: true
# frozen_string_literal: true

module GitHub
  module RepoGraph
    class Cache
      # This is the cache that all repository graphs use to build their own
      # data structure specific to their needs.
      #
      # repo       - The Repository instance.
      # network_id - Arbitrary String that uniquely identifies the network the
      #              repo belongs to. Typically Repository#network_id.
      # oid        - The SHA1 oid of the repo's current HEAD as a String. This is
      #              used to invalidate caches whenever the repo is pushed to
      #              or the default branch changes. Typically set to
      #              Repository#default_oid.
      #
      # Returns the new Cache instance.
      def initialize(repo, network_id, oid)
        Failbot.push("gh.repo.network_id": network_id, "git.commit.oid": oid)
        @repo = repo
        @network_id = network_id
        @oid = oid
      end

      def version
        2
      end

      # Detailed and up to date commit activity log for the repo. Please see
      # `gitrpc/backend/gh_graph/graph_data` for implementation details. This is done in a
      # single GitRPC invocation with @repo#command.
      #
      # Returns an Array of commits Arrays or an empty Array when the graphs
      #   for this repo are disabled.
      def data
        @data ||= data!
      end

      def data!
        return [] if disabled?

        log_entries = GitHub.cache.fetch(data_key) do
          GitHub.dogstats.time("repo_graph", tags: ["type:gh_graph"]) do
            tries = 3
            begin
              @repo.rpc.gh_graph_data(@oid, version: version)
            rescue GitRPC::Protocol::DGit::ResponseError => e
              tries -= 1
              if tries > 0
                Failbot.report!(e, app: "github-dgit-debug", "gh.repo.id": @repo.id)
                @repo.rpc.clear_graph_cache
                retry
              else
                raise
              end
            end
          end
        end

        if log_entries.empty?
          disable
          return log_entries
        end

        # Reject commits before 1970.  Some importers screw with the commit date
        # and some people do dumb things with git.  See https://github.com/github/github/issues/13974
        # for an example of the former.
        # Also will reject spammy and blocked users
        # so that the results will be cached

        emails = log_entries.flat_map { |entry| entry[4] }.uniq

        emails = emails.map { |email| GitHub::Encoding.try_guess_and_transcode(email) }

        # exclude strings with invalid encodings to avoid a mysql collation exception in the query below
        # emails support utf8mb3 but not utf8mb4
        emails = emails.select { |email| GitHub::UTF8.valid_email?(email) }

        # for the EMU we need to find the correct user by adding a short code to an email
        business = @repo.enterprise_managed_business if @repo.is_enterprise_managed?
        emails = business.add_emu_shortcode_to_emails(emails) if business.present?

        sql_bindings = {
          owner_id: @repo.owner_id,
          emails: emails,
        }

        # Get a list of emails to reject based on if they are spammy or blocked by the owner
        sql = Arel.sql <<-SQL, **sql_bindings
          (
            SELECT user_emails.email FROM user_emails
            INNER JOIN users ON user_emails.user_id = users.id AND users.spammy = 1
            WHERE user_emails.email IN (:emails)
          )
          UNION
          (
            SELECT user_emails.email FROM user_emails
            INNER JOIN users ON user_emails.user_id = users.id
            INNER JOIN ignored_users ON ignored_users.user_id = :owner_id AND
            ignored_users.ignored_id = users.id
          )
        SQL

        ActiveRecord::Base.connected_to(role: :reading_slow) do
          contributor_emails_to_reject = UserEmail.connection.select_rows(sql).flatten

          log_entries.reject do |entry|
            time, emails = entry.values_at(1, 4)
            time < 0 || (emails - contributor_emails_to_reject).empty?
          end
        end
      end

      # Are graphs for this repo currently disabled? This is true when a repo
      # only has commits with malformed emails or empty commits. We do this
      # to avoid scanning the whole history over and over again and writting
      # empty cache files.
      #
      # Returns a Boolean.
      def disabled?
        !GitHub.cache.get(cache_key("disabled")).nil?
      end

      def disable
        GitHub.cache.add(cache_key("disabled"), "1")
      end

      def enable!
        GitHub.cache.delete(cache_key("disabled"))
      end

      # Wipe the file cache and the memcached copy of it
      def clear
        GitHub.cache.delete(data_key)
        @repo.rpc.clear_graph_cache
      end

      # This finds all User records whose email is included in the history then
      # groups the data by user logins.
      #
      # Returns an Hash.
      def user_data
        if disabled?
          return {}
        end

        @user_data ||= begin
          users = {}

          business = @repo.enterprise_managed_business if @repo.is_enterprise_managed?

          reduction_promises = data.map do |_time, week_start, adds, dels, emails, _zone|
            Platform::Loaders::UserByEmail.load_all(emails, business: business).then do |authors|
              authors.uniq.each do |author|
                next unless author
                next if author.spammy?
                users[author.id] ||= []
                users[author.id] << [week_start, adds, dels]
              end
            end
          end

          Promise.all(reduction_promises).sync
          users
        end
      end

      # Build a new memcached key. All keys are prefixed with the repo's
      # network ID.
      #
      # suffix - String appended to the key prefix.
      #
      # Returns the new cache key String.
      def cache_key(suffix)
        "repo-graph:%s:%s:%s" % [
          "v#{version}",
          @network_id,
          suffix,
        ]
      end

      # Today at midnight represented in UTC. This is overridden in the test
      # suite to avoid time dependant errors.
      #
      # Returns a Time object.
      def now
        @now ||= Time.now.utc.midnight
      end

      # List of weeks starting from the oldest available commit up to now.
      # That is, they're ordered in ascendant order, oldest first and most
      # recent last. All weeks start on Sunday at midnight.
      #
      # Returns an Array of UNIX timestamps.
      def weeks
        if disabled? || data.empty?
          return []
        end

        @weeks ||= weeks!
      end

      # True if the graph is empty or disabled
      def empty?
        disabled? || data.empty?
      end

      def weeks!
        timestamps = []
        current_week = beginning_of_week(now)
        oldest_week = Time.at(data.map { |d| d[1] }.min).utc

        timestamps << oldest_week.midnight.to_i
        while current_week > oldest_week
          oldest_week = oldest_week + 60 * 60 * 24 * 7
          timestamps << oldest_week.midnight.to_i
        end

        timestamps
      end

      # Uncached log of just commit times for the current repo. Skips merge commits.
      #
      # Returns an array of [timestamp, offset] tuples
      def commit_timestamps_and_offsets(revision)
        GitHub.dogstats.time("repo_graph.git_log_times") do
          log = @repo.rpc.repo_graph_log_times(revision)

          week = %w[Sun Mon Tue Wed Thu Fri Sat]
          result = []

          log.each do |line|
            # commits with malformed timestamps will have a blank line
            next if line.empty?
            # parse day, hour
            # Tue, 20 Nov 2012 01:20:20 -0600
            line =~ /(\w+), \d+ \w+ \d+ (\d+):/
            day = $1
            hour = $2.to_i
            day = week.index day
            result << [day, hour]
          end

          result
        end
      end

      # All times offset from UTC by the offset of the author
      #
      # Returns an Array of Time objects
      def commit_times
        if disabled?
          return []
        end

        @commit_times ||= commit_timestamps_and_offsets(@oid)
      end

      # Time at the beginning of the week of the given time.
      #
      # time - required Time object.
      #
      # Returns a Time object.
      def beginning_of_week(time)
        raise ArgumentError, "Time object expected" unless time.is_a? Time

        if time.wday.zero?
          time
        else
          time - (time.wday * (60 * 60 * 24))
        end
      end

      private

      def data_key
        Digest::SHA256.hexdigest(cache_key("gh-graph:#{@oid}"))
      end
    end
  end
end
