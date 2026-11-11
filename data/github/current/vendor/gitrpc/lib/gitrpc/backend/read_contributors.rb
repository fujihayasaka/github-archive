# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Backend
    # Internal: Maximum number of blob contributors to return.
    @blob_contributors_limit = 1000
    (class <<self; attr_accessor :blob_contributors_limit; end)

    # Internal: Maximum amount of time to take retrieving blob contributors.
    @blob_contributors_timeout = 4
    (class <<self; attr_accessor :blob_contributors_timeout; end)

    # Retrieve authors of blob modifications in order from most recent to
    # least recent, starting at a given commit.
    #
    # commit_oid         - The commit SHA1 to start looking from
    # path               - The String path from the root of the blob to examine.
    #                      If not informed, the entire repository will be checked.
    # co_authors         - If true, treats emails in `Co_authored_by` trailers as authors
    # group_by_signature - If true, treat commits with same email but different name
    #                      as different authors (instead of just grouping by email)
    #
    # Returns structure holding an array of structures (each containing an
    # author email, last commit SHA, last author name and last commit epoch +
    # offset) plus a flag indicating if the limit was hit in terms of rows
    # of output or allotted time (i.e. there may be other authors missing
    # from results). Example:
    #
    # {
    #   "data" => [
    #     {
    #       "author" => "someone@blah.com",
    #       "name" => "Ms. Commit Author",
    #       "commit" => "beadc075b3f7cbf9087ac02567299ee1114eabd2",
    #       "time" => 1342581713,
    #       "offset" => -25200,
    #       "count" => 5
    #     },
    #     {
    #       "author" => "someone_else@bar.com",
    #       ...
    #       "count" => 8
    #     },
    #     ...
    #   ],
    #   "truncated" => false
    # }
    #
    # Raises GitRPC::ObjectMissing if the commit_oid or path cannot be
    # resolved
    rpc_reader :read_contributors
    def read_contributors(commit_oid, path = nil, co_authors: false, group_by_signature: false)
      # Each commit will output commit SHA (%H), timestamp (%ad) and signature (%aN <%aE>);
      # trailers will follow (if requested) and we wrap with extra newline (%n)
      #
      # Example:
      #
      # ae5897efddf8b278696bce73f7a69cf410c5d0c5|1111111114 -0500|Author 4 <author4@blah.com>
      # CO-AUTHORED-BY: Author 3 <author3@blah.com>
      #
      # 2ce80bc71da8a78c4754ec459d64956d906d2848|1111111113 -0500|Author 3 <author3@blah.com>
      # Some-unrelated-trailer:foo
      # Co-authored-by: <author2@blah.com>
      #
      # 051b417d4142bd1a8dd9a27dc7aa5ad56e1254e4|1111111111 -0500|Author 1 <author1@blah.com>
      #
      # ffc311e66324a7dd8324a32a23752b5a696810e6|1111111112 -0500|Author 1 <author1@blah.com>
      #
      if co_authors
        format_parameter = "--format=%H|%ad|%aN <%aE>%n%(trailers:only,unfold)"
      else
        format_parameter = "--format=%H|%ad|%aN <%aE>%n"
      end

      args = ["--date=raw", format_parameter, commit_oid]
      args += ["--", path] if path
      result = { "data" => [], "truncated" => false }
      seen = {}
      skipped_empty_author = false

      log = build_git("log", args, nil, {}, Backend.blob_contributors_timeout)

      begin
        log.exec!
      rescue Progeny::TimeoutExceeded
        result["truncated"] = true
      rescue Errno::ENOENT => boom
        if Dir.exist?(@path)
          raise boom
        else
          raise GitRPC::InvalidRepository, "Does not exist: #{@path}"
        end
      end

      log.out.split("\n\n").each do |block|
        rows = block.split("\n")
        commit, timestamp, signature = rows.first.split("|", 3)
        author_name, author_email = signature.match(/(.*?)\s\<(.*)\>/)&.captures
        author_email = author_email.to_s.strip
        if author_email.empty?
          skipped_empty_author = true
          next
        end

        trailers = rows.drop(1)
        co_author_names_and_emails = trailers.map(&method(:co_author)).compact if co_authors

        [[author_name, author_email], *co_author_names_and_emails].each do |name, email|
          epoch, offset = timestamp.split(" ")
          epoch  ||= "0"
          offset ||= "+0000"

          group_key = group_by_signature ? "#{name} <#{email}>" : email
          if seen[group_key]
            seen[group_key]["count"] += 1
          else
            result["data"] << (seen[group_key] = {
              "author" => email,
              "name"   => name,
              "commit" => commit,
              "time"   => epoch.to_i,
              "offset" => convert_tz_offset_to_seconds(offset),
              "count"  => 1,
            })

            if result["data"].size >= Backend.blob_contributors_limit
              result["truncated"] = true
              break
            end
          end
        end

        break if result["truncated"]
      end

      if result["data"].empty? && !result["truncated"] && !skipped_empty_author
        msg = log.err.empty? ? "invalid path" : log.err
        raise GitRPC::ObjectMissing.new(msg)
      end

      result
    end

    def convert_tz_offset_to_seconds(tz_offset)
      ((tz_offset[0] == "-" ? -1 : 1) *
       tz_offset[1, 2].to_i * 60 + tz_offset[3, 2].to_i) * 60
    end

    private

    COAUTHOR_MATCHER = /^Co-authored-by\:\s+(.*?)\s?\<([^\n]+)\>/i
    # Internal: extracts the name and email of a valid co-author commit comment trailer
    # (e.g.: `Co-authored-by: Peter Parker <peter@dailybugle.com>`)
    #
    # Returns array with name and e-mail if trailer is a valid co-author, `nil otherwise
    def co_author(trailer)
      # TODO: revert to the version (https://git.io/v7jFq) that used Rugged#signature_from_buffer
      # as soon as we can bump Rugged without crashing
      if match = COAUTHOR_MATCHER.match(trailer)
        match.captures
      end
    end
  end
end
