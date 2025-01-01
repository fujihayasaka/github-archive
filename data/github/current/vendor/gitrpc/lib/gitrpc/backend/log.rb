# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend

    NAME_EMAIL_MATCHER = /(.+?) <(.+)>/n
    CO_AUTHORED_BY_TRAILER_NAME = "Co-authored-by".freeze

    rpc_reader :activity_summary_coauthors
    def activity_summary_coauthors(since)
      authoredRes = spawn_git(
        "shortlog",
        ["--branches", "--tags", "--since=#{since.to_i}", "--no-merges", "-s", "-e", "--group=author", "--group=trailer:Co-authored-by"])
      raise GitRPC::CommandFailed.new(authoredRes) if !authoredRes["ok"]

      commitedRes = spawn_git(
        "shortlog",
        ["--branches", "--tags", "--since=#{since.to_i}", "--no-merges", "-s", "-e", "--group=committer"])
      raise GitRPC::CommandFailed.new(commitedRes) if !commitedRes["ok"]

      results = Hash.new do |hash, key|
        hash[key] = { authored_count: 0, committed_count: 0 }
      end

      authoredRes["out"].split("\n").each do |line|
        name, email, count = parse_committer_info(line)
        results[[name,email]][:authored_count] += count if name != nil && email != nil
      end

      commitedRes["out"].split("\n").each do |line|
        name, email, count = parse_committer_info(line)
        results[[name,email]][:committed_count] += count if name != nil && email != nil
      end

      results.sort_by { |(name, email), counts| [-counts[:authored_count], -counts[:committed_count]] }
    end

    def parse_committer_info(line)
      count, rest = line.split("\t", 2)
      name_email = rest.match(NAME_EMAIL_MATCHER)
      return [nil, nil, 0] if name_email.nil?
      [name_email[1].force_encoding("UTF-8").chomp, name_email[2].force_encoding("UTF-8").chomp, count.strip.to_i]
    end

    rpc_reader :contributor_shortlog
    def contributor_shortlog(oid, ignore_merge_commits: false, since: nil)
      ensure_sanitary_argument(oid)

      options = ["--numbered", "--email", "--summary"]
      options << "--no-merges" if ignore_merge_commits
      options << "--since=#{since}" if since
      options << oid.to_s

      res = spawn_git("shortlog", options)
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"]
    end

    rpc_reader :contributor_log
    def contributor_log(oid, ignore_merge_commits: false, mailmap: false, since: nil)
      ensure_valid_full_oid(oid)

      format = mailmap ? "%aN <%aE>" : "%an <%ae>"
      options = ["--format=#{format}"]
      options << "--no-merges" if ignore_merge_commits
      options << "--since=#{since}" if since
      options << oid
      options << "--"

      res = spawn_git("log", options)
      raise GitRPC::CommandFailed.new(res) if !res["ok"]

      count_hash = Hash.new(0)

      res["out"].split("\n").each_with_object(count_hash) do |name_email, hash|
        hash[name_email] += 1
      end

      count_hash.transform_keys! do |key|
        match = key.match(NAME_EMAIL_MATCHER)
        next if match.nil?
        { name: match[1], email: match[2] }
      end

      count_hash.delete(nil)

      count_hash
    end

    rpc_reader :repo_graph_log_times
    def repo_graph_log_times(oid)
      ensure_sanitary_argument(oid)

      res = spawn_git("log", ["--pretty=format:%aD", "--max-count=20000", "--no-merges", oid])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"].split("\n")
    end

    rpc_reader :commit_stats_log
    def commit_stats_log(commitish)
      ensure_valid_commitish(commitish)

      res = spawn_git("log", ["--pretty=format:%H", "--skip=0", "--max-count=10", "--shortstat", "--no-merges", "-z", commitish])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"].split("\0")
    end

    rpc_reader :paged_commits_log
    def paged_commits_log(commit_oid, path: nil, author_emails: [], committer_emails: [], since_time: nil, until_time: nil, skip: nil, max_count: nil)
      ensure_sanitary_argument(commit_oid)

      argv = ["-i", "-F", "--format=%H"]
      argv << "--since=#{since_time}" if since_time
      argv << "--until=#{until_time}" if until_time
      argv << "--skip=#{skip}" if skip
      argv << "--max-count=#{max_count}" if max_count
      argv += author_emails.map { |email| "--author=<#{email}>" }
      argv += committer_emails.map { |email| "--committer=<#{email}>" }
      argv << commit_oid
      argv += ["--", path] if path

      res = spawn_git("log", argv)
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"].split("\n")
    end

    rpc_reader :log_last_commit_oneline
    def log_last_commit_oneline
      res = spawn_git("log", ["-1", "--oneline"])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"].chomp
    end
  end
end
