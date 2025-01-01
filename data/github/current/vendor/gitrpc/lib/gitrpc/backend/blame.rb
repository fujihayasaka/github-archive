# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    rpc_reader :blame
    def blame(commit_oid, path, annotate: [], timeout: nil, since: nil, ignore_revs_file: nil, incremental: false)
      ensure_valid_full_oid(commit_oid)

      argv = incremental ? ["--incremental"] : ["--porcelain"]
      argv += ["--ignore-revs-file", "/dev/stdin"] if ignore_revs_file
      argv += ["--since", "#{since.to_i}"] if since
      annotate.each do |linenum|
        argv += ["-L", "#{linenum},#{linenum}"]
      end
      argv += [commit_oid, "--", path]

      res = spawn_git("blame", argv, ignore_revs_file, {}, nil, timeout)

      if !res["ok"]
        raise NoSuchPath, path if res["err"].start_with?("fatal: no such path")
        raise BadLineRange if /has only \d+ lines?\n?\z/.match?(res["err"])
        raise InvalidIgnoreRevs if !ignore_revs_file.nil? && res["err"].start_with?("fatal: invalid object name")
        raise GitRPC::CommandFailed.new(res)
      end

      res["out"]
    end
  end
end
