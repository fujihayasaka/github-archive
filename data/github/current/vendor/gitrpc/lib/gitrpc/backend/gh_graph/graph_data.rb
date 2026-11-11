# typed: true
# frozen_string_literal: true

require "gitrpc/backend/contribution_caches"
require "zlib"

module GitRPC
  class Backend
    class GraphData

      # git log output for legacy (v1) parser
      # Eg:
      #
      #   946702800 -0500----someone@example.org"
      #   1 file changed, 1 insertion(+)"
      #
      #   946702800 -0500----someone@example.org
      #   1 file changed, 2 insertions(+)"
      LEGACY_FORMAT = "%ad----%ae"

      # git log output for co-author trailer parser (>= v2)
      # Eg:
      #   946702800 -0500----someone@example.org
      #   co-authored-by: Homer Simpson <hsimpson@github.com>
      #
      #   1 file changed, 2 insertions(+), 1 deletion(-)
      #
      #   946702800 -0500----someone@example.org
      #   1 file changed, 1 insertion(+)
      CO_AUTHOR_FORMAT = "%ad----%ae%n%-\(trailers:only,unfold\)"

      # matches the signature of an authorship trailer
      # NOTE: This is copied from app/models/git_actor.rb These must be kept in sync.
      #       The plan is to get this one into a proper gitrpc backend endpoint and then
      #       Reference that in GitActor instead of defining it there at all.
      # eg:
      #   Homer Simpson <hsimpson@github.com>
      SIGNATURE_MATCHER = /\A(?<name>.+)\s\<(?<email>.+@.+)\>\z/

      # matches the first log line for each commit.
      # eg:
      # 1510684028 -0500----hsimpson@github.com
      HEADER_MATCHER = /\A(\d+) (-?\+?\d+)----(.+)\z/

      # Regex to capture count (integer) and type (string 'insertion'
      # or 'deletion') for each stats line
      STATS_MATCHER = /(\d+) (\w+)/

      # Matches the beginning of the change statistics line
      STATS_LINE_START_MATCHER = /\A \d+ files? changed/

      # backend     - a reference to the GitRPC::Backend
      # revision    - the head commit revision for this graph's data
      # max_commits - the maximum number of ancestor commits to traverse
      # force       - force a complete rebuild
      # version     - the version for the algorithm and cache file we will be using.
      def initialize(backend, revision, max_commits: nil, force: false, version:)
        @backend     = backend
        @revision    = revision
        @max_commits = max_commits
        @force       = force
        @version     = version

        caches = GitRPC::Backend::ContributionCaches.new(backend)

        @read_cache  = caches.find_existing_cache(version: version)
        @write_cache = caches.new_instance(version: version)
      end

      # The head commit revision whose ancestry will be traversed to calculate the graph data
      attr_reader :revision

      # If specified, the maximum number of commits which will be traversed. If there are more
      # commits in the ancestry, they will be ignored.
      attr_reader :max_commits

      # The GitRPC::Backend instance
      attr_reader :backend

      # True if the we are forcing a rebuild of the entire cache
      attr_reader :force

      # The GitRPC::Backend::ContributionCaches::AbstractCache to which we'll be writing
      attr_reader :write_cache

      # The GitRPC::Backend::ContributionCaches::AbstractCache from which we'll be reading
      attr_reader :read_cache

      # The version of the cache file and parsing algorithm we are using
      attr_reader :version

      # Public: returns an array of data, each row corresponding to a single commit in the ancestry
      #         of the given commit OID.
      #
      # Each row is formatted as follows:
      #   [timestamp, week_midnight_timestamp, addition_count, deletion_count, email, timezone]
      def process
        # Reading cache_file.head_sha will raise a Zlib exception if the graph
        # data is corrupt. In that case, force a rebuild from scratch.
        begin
          read_cache.head_oid unless read_cache.nil?
        rescue Zlib::Error
          force = true
        end

        # Either a force request or the first time building the graph, we
        # need to do a full build and write it out to the cache.
        if force || read_cache.nil?
          rebuild_from_scratch
        elsif read_cache.head_oid != revision
          # We can do an less resource-intensive update if the old head sha is in the
          # new head sha's history. For this, we just get a range of commits from whatever
          # we have cached on disk and the current passed in HEAD sha.
          #
          # If the commit is not in the history, we'll need to do a full rebuild
          # of the history and write out to the cache file.
          if commit_is_in_history?(read_cache.head_oid, revision)

            # All commits between the cached head and the passed in head sha
            range = "#{read_cache.head_oid}..#{revision}"

            missing_data = build_data(range)
            fresh_data   = missing_data + adapted_existing_data

            write_cache.write(revision, fresh_data)
            fresh_data
          else
            rebuild_from_scratch
          end
        else
          # The passed in sha matches the head sha of the cached file, so
          # just dump out the cached data
          adapted_existing_data
        end
      end

      private

      def build_data(range)
        if version < 2
          legacy_build_data(range)
        else
          build_data_next(range)
        end
      end

      # Internal: Output formatted data about the git history.
      #
      # The result of `git log` will look like:
      #
      #   1368227541----jbarnette@github.com
      #    1 file changed, 1 insertion(+), 1 deletion(-)
      #
      #   1368226585----jbarnette@github.com
      #    1 file changed, 11 insertions(+), 10 deletions(-)
      #
      #   1368226272----timothy.clem@gmail.com
      #    1 file changed, 1 insertion(+)
      #
      # We then massage the data and return an array of commits.
      #
      # revision - The sha (or range of shas "sha..sha"), to start this
      #            log at.
      #
      # count    - Total number of commits to return. Defaults to nil (no limit)
      def legacy_build_data(revision_or_range)
        lines = fetch_log(revision_or_range, format: LEGACY_FORMAT)
        data = []

        while lines.any?
          email_line, stats_line = nil, nil

          email_line = lines.shift
          next if email_line.empty?

          if lines.first =~ / \d+ files? changed/
            stats_line = lines.shift
          else
            # an empty commit will not have any changes - ignore it.
            next
          end

          # The first line contains the unix epoch and the email address
          epoch, email = email_line.split("----", 2)
          email = email.split(" ")[0]

          # Bail out of this iteration and go to the next line if
          # any of the data is empty
          next if email.nil? || email.empty?
          next if epoch.empty?

          timestamp, zone = epoch.split(" ")
          timestamp = Integer(timestamp)
          zone = parse_zone(zone)
          time = Time.at(timestamp).localtime(zone)
          week_midnight = Time.utc(time.year, time.month, time.day) - time.wday * 24 * 60 * 60

          # The second line contains data on files changed, insertions
          # and deletions
          additions = 0
          deletions = 0

          # Regex to capture count (integer) and type (string 'insertion'
          # or 'deletion') for each stats line
          stats_re = /(\d+) (\w+)/

          matches = stats_line.scan(stats_re).each do |count, type|
            case type
            when /^insertion/
              additions = Integer(count || 0)
            when /^deletion/
              deletions = Integer(count || 0)
            else
              next
            end
          end

          if matches.empty?
            next
          end

          data << [
            timestamp,
            week_midnight.to_i,
            additions,
            deletions,
            email,
            zone,
          ]
        end

        data
      end

      # Internal: Check if the old_head_oid if part of the history of new_head_oid. If it's not
      # then range queries are not possible and full rebuild of graph data is necessary.
      #
      # Returns true if the previous head oid is in the history of the new head oid.
      def commit_is_in_history?(old_head_oid, new_head_oid)
        pair = [new_head_oid, old_head_oid]
        res = backend.descendant_of([pair])
        res[pair]
      rescue GitRPC::ObjectMissing
        false
      end

      # Internal: Parse a zone string into a UTC offset
      #
      # Returns an integer UTC offset
      def parse_zone(zone)
        offset = 0
        pos = zone.slice!(0, 1)
        parts = []
        while part = zone.slice!(-2, 2)
          parts << part
        end
        parts << zone
        parts.reverse_each do |part|
          offset *= 60
          offset += part.to_i
        end
        utc_offset = (pos == "-" ? -1 : 1) * offset * 60
        if -86400 < utc_offset && utc_offset < 86400
          utc_offset
        else
          # Invalid offset, just assume UTC
          0
        end
      end

      # Internal: Read all requested data from `git log` and overwrite the cache file
      #   with this new data.
      #
      # Returns the array of data read
      def rebuild_from_scratch
        full_data = build_data(revision)

        return full_data if full_data.empty?

        write_cache.write(revision, full_data)

        full_data
      end

      def fetch_log(revision_or_range, format:)
        args = [
          "--pretty=format:#{format}",
          "--date=raw",
          "--shortstat",
          "--no-renames",
          "--no-merges"
        ]
        args << "--max-count=#{max_commits}" if max_commits
        args << revision_or_range

        res = backend.spawn_git_ro("log", args)
        fail GitRPC::CommandFailed.new(res) unless res["ok"]

        res["out"].split("\n")
      end

      def build_data_next(revision_or_range)
        lines = fetch_log(revision_or_range, format: CO_AUTHOR_FORMAT)
        parse_data(lines)
      end

      # Public: parses the `git log` output to return an array of arrays one inner array for
      # each author of each commit in the range.
      # eg:
      # [[timestamp, week_midnight, additions, deletions, [email1, email2...], timezone_offset]...]
      def parse_data(lines)
        data = []

        while lines.any?
          commit_data = extract_commit_lines(lines)
          next unless commit_data

          emails = [commit_data[:email]]

          data << [
            commit_data[:timestamp],
            commit_data[:week_midnight],
            commit_data[:stats][0],
            commit_data[:stats][1],
            emails,
            commit_data[:zone]
          ]

          next unless commit_data[:coauthor_emails]

          commit_data[:coauthor_emails].each do |coauthor|
            emails << coauthor
          end
        end

        data
      end

      def extract_commit_lines(lines)
        return nil if lines.empty?

        line = lines.shift
        line = lines.shift while line && line !~ HEADER_MATCHER

        commit_data = extract_header_data(line)
        return nil if commit_data.nil?

        line = lines.first
        while line && line !~ HEADER_MATCHER
          if line =~ STATS_LINE_START_MATCHER
            commit_data[:stats] = extract_change_counts(line)

            # we know there are no trailers when we find this line so it is safe to return early.
            lines.shift
            return commit_data
          elsif match = line.match(GitRPC::Backend::GIT_TRAILER_MATCHER)
            email = extract_coauthor_email(match)

            if email
              commit_data[:coauthor_emails] ||= []
              commit_data[:coauthor_emails] << email if email
            end
          end
          lines.shift

          line = lines.first
        end

        # empty commits have no contribution relevance
        return unless commit_data.key?(:stats)

        commit_data
      end


      # The first line contains the unix epoch and the email address
      def extract_header_data(header_line)
        return if header_line.nil?

        epoch, email = header_line.split("----", 2)
        email = email.split(" ")[0]

        return if email.nil? || email.empty?
        return if epoch.empty?

        timestamp, zone = epoch.split(" ")
        timestamp = Integer(timestamp)
        zone = parse_zone(zone)
        time = Time.at(timestamp).localtime(zone)
        week_midnight = Time.utc(time.year, time.month, time.day) - time.wday * 24 * 60 * 60

        { email: email, timestamp: timestamp, week_midnight: week_midnight.to_i, zone: zone }
      end


      # The second line contains data on files changed, insertions
      # and deletions
      def extract_change_counts(stats_line)
        additions = 0
        deletions = 0
        matches = stats_line.scan(STATS_MATCHER).each do |count, type|
          case type
          when /^insertion/
            additions = Integer(count || 0)
          when /^deletion/
            deletions = Integer(count || 0)
          else
            next
          end
        end

        [additions, deletions]
      end

      def extract_coauthor_email(trailer_match)
        return unless trailer_match[:key].downcase == "co-authored-by"

        signature = trailer_match[:value]
        match = signature.match(SIGNATURE_MATCHER)
        return unless match

        match[:email]
      end

      # If the data from the read cache is older than the version the user has
      # requested (write_cache version) then it needs to be adapted to fit the
      # expected format.
      def adapted_existing_data
        # if write_cache is v1, read_cache is at most v1 by the logic of
        # ContributionCaches#find_existing_cache.
        return read_cache.commits if write_cache.version == 1 || read_cache.version > 1

        read_cache.commits.map do |commit|
          commit[4] = [commit[4]]
          commit
        end
      end
    end
  end
end
