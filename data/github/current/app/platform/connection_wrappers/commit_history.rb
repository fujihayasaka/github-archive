# typed: false
# frozen_string_literal: true

require "scientist"

module Platform
  module ConnectionWrappers
    class CommitHistory < ConnectionWrappers::Base
      include CursorGenerator
      include Scientist

      class Edge
        attr_reader :node, :cursor

        def initialize(node, cursor)
          @node, @cursor = node, cursor
        end
      end

      attr_accessor :repository

      def initialize(
        repository,
        first: nil,
        last: nil,
        after: nil,
        before: nil,
        arguments: nil,
        field: nil,
        max_page_size: 100,
        **kwargs
      )
        if last
          @cursor = before
          if !@cursor
            raise Errors::MissingBackwardsPaginationArgument.new(field)
          else
            commit_oid, skip = self.class.decode_cursor(arguments[:commit_oid], @cursor)
            skip -= last
          end
        else
          @cursor = after
          commit_oid, skip = self.class.decode_cursor(arguments[:commit_oid], @cursor)
          if @cursor
            # We want to see _after_ the cursor, so increment the skip to bypass that commit
            skip += 1
          end
        end

        @repository = repository
        @commit_oid = commit_oid
        @skip = skip
        @limit = determine_limit(max_page_size, first, last)

        super(
          nil,
          first: first,
          last: last,
          after: after,
          before: before,
          arguments: arguments,
          field: field,
          max_page_size: max_page_size,
          **kwargs
        )
      end

      def edges
        @edges ||= results.then do |oids|
          Loaders::GitObject.load_all(@repository, oids, expected_type: :commit).then do |commits|
            commits.each_with_index.map do |commit, index|
              Edge.new(commit, self.class.encode_cursor(@commit_oid, @skip + index))
            end
          end
        end
      end

      def edge_nodes
        self.edges.then { |edges| edges.map(&:node) }
      end

      def page_info
        @page_info ||= edges.then do |e|
          PageInfo.new(
            has_next_page: @has_next_page,
            has_previous_page: @skip > 0,
            start_cursor: e.first.try(:cursor),
            end_cursor: e.last.try(:cursor),
          )
        end
      end

      def self.encode_cursor(commit_oid, offset)
        "#{commit_oid} #{offset}"
      end

      def self.decode_cursor(commit_oid, cursor)
        return [commit_oid, 0] if !cursor

        if cursor =~ /\A([0-9a-f]{40}) (\d+)\z/i
          # a 40-char hex-encoded OID, followed by a space and an offset
          return [$1.downcase, $2.to_i]
        end

        decoded = CursorGenerator.resolve_cursor(cursor)

        case decoded
        when /\A(.{20})\+(\d+)\z/m
          # an OID packed to 20 bytes, followed by a "+" and an offset
          [$1.unpack("H40").first, $2.to_i]
        when /\A(\d+)\z/
          # a bare offset
          [commit_oid, $1.to_i]
        else
          raise Errors::Cursor.new(cursor)
        end
      end

      def git_args
        regexp_ignore_case = fixed_strings = false
        fetch_author_emails.then do |author_emails|
          if author_emails == []
            @has_next_page = false
            []
          else
            since_time = @arguments[:since] ? @arguments[:since].iso8601 : nil
            until_time = @arguments[:until] ? @arguments[:until].iso8601 : nil

            regexp_ignore_case = fixed_strings = true

            @repository.async_enterprise_managed_business.then do |business|
              if author_emails
                # If any of the emails is a stealthy email we need to use wildcard matching.
                fixed_strings = false if author_emails.any? { |email| email.match(StealthEmail::STEALTH_EMAIL_REGEX) }

                # Prefer Array#map to avoid unexpected mutations.
                author_emails = author_emails.map do |email|
                  email = format_emu_email(email, business) if business
                  email = email_to_pattern(email) unless fixed_strings
                  email
                end
              end

              if @skip < 0
                # The client is trying to paginate before the first entry, which is impossible.
                # So just use the check to see if there are any results at all.
                skip_results = 0
                max_results = 1
              else
                # Select up to one extra,
                # that way we can tell if there are more pages
                max_results = @limit + 1
                skip_results = @skip
              end

              {
                max: max_results,
                skip: skip_results,
                authors: author_emails || [],
                regexp_ignore_case: regexp_ignore_case,
                fixed_strings: fixed_strings,
                since_time: since_time,
                until_time: until_time,
                path: @arguments[:path] || nil,
              }
            end
          end
        end
      end

      def total_count
        git_args.then do |args|
          if args.empty?
            0
          else
            # We can ignore `max` and `skip` here, because we're not getting
            # a subset, but the total number of commits given the arguments
            @repository.rpc.count_revision_history(@commit_oid, args.except(:max, :skip))
          end
        end
      end

      private

      def results
        @results ||= results!
      end

      def results!
        git_args.then do |args|
          if args.empty?
            []
          else
            begin
              # at first we need to include the parent so increment max by 1 when retrieving the rename commits
              if @arguments[:exclude_parent]
                args[:max] += 1
              end

              oids = @repository.rpc.list_revision_history_multiple([@commit_oid], args)

              # if browsing rename history we remove the parent commit since it was already shown/known.
              if @arguments[:exclude_parent]
                oids -= @arguments[:exclude_parent]
              end

            rescue GitRPC::ObjectMissing
              raise Errors::Cursor.new(@cursor)
            end
            if oids.length > @limit || @skip < 0
              @has_next_page = true
              # Remove the extra oid, which was checking for next page
              oids.pop
            else
              @has_next_page = false
            end
            oids
          end
        end
      end

      # Returns a promise of author emails based on the author argument passed
      # to the connection.
      #
      # A promise of nil indicates that no author filtering was requested.
      #
      # A promise of an empty array indicates that either no email addresses
      # were passed or that the user passed has no email addresses. In this
      # we return no commits. This deviates from Git's command-line behaviour,
      # where the absence of --author arguments means that no filtering is
      # performed.
      #
      # This will also return an empty array if a valid User-type Cursor is passed,
      # but the User cannot be found
      def fetch_author_emails
        if !@arguments[:author]
          return ::Promise.resolve(nil)
        end

        if @arguments[:author][:id]
          type_name, id = Platform::Helpers::NodeIdentification.from_global_id(@arguments[:author][:id])

          return ::Promise.resolve([]) unless %w[User Bot].include? type_name

          return Loaders::UserEmails.load(id.to_i)
        end

        author_emails = @arguments[:author][:emails].dup
        if author_emails
          return ::Promise.resolve(author_emails)
        end

        ::Promise.resolve(nil)
      end

      # Get the smallest, non-nil number
      def determine_limit(max_page_size, first, last)
        limit = max_page_size
        if first && first < limit
          limit = first
        end
        if last && last < limit
          limit = last
        end
        limit
      end

      def email_to_pattern(email)
        match = email.match(StealthEmail::STEALTH_EMAIL_REGEX)
        # Stealthy emails are already wildcard patterns and don't need escaping
        return "#{match[1]}\+.*@#{GitHub.stealth_email_host_name}" if match

        # If fixed_strings is false all emails will be interpreted as patterns and must be regexp escaped.
        # Example: to find authors with email github-actions[bot]@users.noreply.github.com
        # we need to escape special regexp characters.
        # Note: escaping of the + sign does not work, because git uses a different RegExp flavour.
        # + sign must not be escaped.
        Regexp.escape(email).gsub(/\\\+/, "+")
      end

      def format_emu_email(email, business)
        shortcode = business.shortcode
        # This is the EMU removal of the shortcode to match commits from this repo
        return email.split("+#{shortcode}@").join("@") if shortcode && email["+#{shortcode}@"]
        email
      end
    end
  end
end
