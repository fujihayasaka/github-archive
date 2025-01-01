# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Backend
    # Public: Retrieve a revision list starting at the commit given.
    rpc_reader :list_revision_history
    def list_revision_history(oid, **options)
      ensure_valid_commitish(oid)

      oids = []

      git_opts = [oid]
      if options && options.is_a?(Hash)
        git_opts += ["-n", options[:limit].to_s] if options.key?(:limit)
        git_opts += ["--skip", options[:offset].to_s] if options.key?(:offset)
        git_opts += ["--until", options[:until].to_s] if options.key?(:until)
        git_opts << "--no-merges" if options[:ignore_merge_commits]

        path = options.fetch(:path, nil)
        git_opts += ["--", path.to_s] if path && !path.empty?
      end

      res = spawn_git("rev-list", git_opts)
      if res["ok"]
        oids += res["out"].split("\n")
      elsif res["err"].include? "bad object"
        raise GitRPC::ObjectMissing.new(res["err"], oid)
      end

      oids
    end

    # Public: Retrieve a revision count starting at the commit given.
    rpc_reader :count_revision_history
    def count_revision_history(commitish, use_bitmap_index: false, no_merges: false, max_count: nil, since_time: nil, until_time: nil, regexp_ignore_case: false, fixed_strings: false, authors: [], path: nil)
      ensure_valid_commitish(commitish)

      git_opts = [commitish, "--count"]

      git_opts << "--use-bitmap-index" if use_bitmap_index
      git_opts << "--no-merges" if no_merges
      git_opts << "--max-count=#{max_count.to_i}" if max_count
      git_opts << "--since=#{since_time}" if since_time
      git_opts << "--until=#{until_time}" if until_time
      git_opts << "--regexp-ignore-case" if regexp_ignore_case
      git_opts << "--fixed-strings" if fixed_strings
      authors.each do |author|
        git_opts << "--author=<#{author}>"
      end
      git_opts << "--"
      git_opts << path.to_s if path

      res = spawn_git("rev-list", git_opts)
      if !res["ok"]
        raise GitRPC::BadRevision if res["err"] =~ /fatal: bad revision/
        raise GitRPC::CommandFailed.new(res)
      end
      res["out"].to_i
    end

    # Public: Retrieve a revision list starting at the commit(s) given.
    rpc_reader :list_revision_history_multiple
    def list_revision_history_multiple(roots, exclude: [], findobjs: [], skip: nil, max: nil, since_time: nil, until_time: nil, regexp_ignore_case: false, fixed_strings: false, authors: [], path: nil, timeout: nil)
      pathargs = ["--"]
      pathargs << path.to_s if path

      roots.each { |oid| ensure_valid_full_oid(oid) }
      exclude.each { |oid| ensure_valid_full_oid(oid) }
      findobjs.each { |oid| ensure_valid_full_oid(oid) }

      roots = ["--all"] if roots.empty?
      args = roots + exclude.map { |oid| "^#{oid}" }
      args << "--find-stdin"
      args << "--show-commit-as-path"
      args << "--skip=#{skip.to_i}" if skip
      args << "--max-count=#{max.to_i}" if max
      args << "--since=#{since_time}" if since_time
      args << "--until=#{until_time}" if until_time
      args << "--regexp-ignore-case" if regexp_ignore_case
      args << "--fixed-strings" if fixed_strings
      authors.each do |author|
        args << "--author=<#{author}>"
      end
      args += pathargs

      res = spawn_git("rev-list", args, findobjs.join("\n"), {}, nil, timeout)
      if !res["ok"]
        raise GitRPC::BadRevision if res["err"] =~ /fatal: bad revision/
        raise GitRPC::ObjectMissing.new(res["err"], $1) if res["err"] =~ /fatal: bad object ([a-zA-Z0-9]{40})/
        raise GitRPC::CommandFailed.new(res)
      end

      res["out"].split("\n")
    end

    # Public: Search commit authors, committers, or messages
    rpc_reader :search_revision_history
    def search_revision_history(choice, query, commitish, max: nil)
      ensure_valid_commitish(commitish)

      args = ["--#{choice}=#{query}"]
      args << "--max-count=#{max.to_i}" if !max.nil?

      case choice
      when "grep"
        args << "--fixed-strings"
      when "author", "committer"
        args << "--regexp-ignore-case" << "--extended-regexp"
      else
        raise ArgumentError, "invalid choice"
      end

      args << commitish
      args << "--"

      res = spawn_git("rev-list", args)
      if !res["ok"]
        raise GitRPC::BadRevision if res["err"] =~ /fatal: bad revision/
        raise GitRPC::CommandFailed.new(res)
      end

      res["out"].split("\n")
    end
  end
end
