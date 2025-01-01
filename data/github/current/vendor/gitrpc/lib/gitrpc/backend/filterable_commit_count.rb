# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    include GitRPC::Util

    FILTERABLE_COMMIT_COUNT_TIMEOUT = 1

    # Public: Fetch the number of commits reachable from the passed in starting oid
    # filtered by additional options
    #
    # starting_oid - the commit to start counting from
    # until_date - the date to count up until
    # since - the date to count from
    # path - count only commits that touch a specified path
    # author - count only commits authored by particular person
    # committer - count only commits committed by particular person
    #
    # Returns the number of commits or nil
    rpc_reader :filterable_commit_count
    def filterable_commit_count(starting_oid, until_date, since, path, author_emails, committer_emails: [], timeout: FILTERABLE_COMMIT_COUNT_TIMEOUT)
      ensure_valid_commitish(starting_oid)

      opts = ["--count"]

      if starting_oid && [since, path, author_emails, committer_emails, until_date].flatten.compact.empty?
        return fast_commit_count(starting_oid, nil)
      end

      author_emails.each { |email| opts << "--author=#{email}" }
      committer_emails.each { |email| opts << "--committer=#{email}" }

      opts << "--since=#{since}" if since
      opts << "--until=#{until_date}" if until_date
      opts << starting_oid

      if path
        opts << "--"
        opts << "#{path}"
      end
      res = spawn_git("rev-list", opts, nil, {}, nil, timeout)

      if res["ok"]
        res["out"].to_i
      end
    end
  end
end
