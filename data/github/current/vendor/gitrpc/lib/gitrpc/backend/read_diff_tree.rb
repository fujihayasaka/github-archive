# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :read_diff_summary_with_base
    def read_diff_summary_with_base(oid1, oid2, base_oid, options = {})
      resolved_oid = resolve_base_for_diff(oid1, oid2, base_oid)
      read_diff_tree(resolved_oid, oid2, options["algorithm"], options["timeout"], true)
    end

    rpc_reader :native_read_diff_toc_with_base
    def native_read_diff_toc_with_base(oid1, oid2, base_oid, options = {})
      resolved_oid = resolve_base_for_diff(oid1, oid2, base_oid)
      read_diff_tree(resolved_oid, oid2, options["algorithm"], options["timeout"], false)
    end

    rpc_reader :native_read_diff_toc_multi
    def native_read_diff_toc_multi(commits, options = {})
      read_diff_tree(nil, nil, options["algorithm"], options["timeout"], false, commits.join("\n") + "\n")
    end

    def read_diff_tree(oid1, oid2, algorithm, timeout, stats, stdin = nil)
      args = [*DIFF_TREE_DETECT_RENAMES, "-z", "-r", "--raw"]
      args += ["--numstat", "--shortstat"] if stats
      if stdin
        args += ["--stdin"]
        args += ["--root"]
      else
        args += [oid1 || "--root", oid2]
      end
      args << "-w" if algorithm == GitRPC::Diff::ALGORITHM_IGNORE_WHITESPACE

      child = build_git("diff-tree", args, stdin, {}, timeout)
      begin
        child.exec!
      rescue Progeny::TimeoutExceeded
        raise GitRPC::Timeout
      rescue Errno::ENOENT => boom
        if Dir.exist?(@path)
          raise boom
        else
          raise GitRPC::InvalidRepository, "Does not exist: #{@path}"
        end
      end

      # let's parse this client side as it could be many thousands of files long
      # and parsing, serializing, and deserializing is more expensive than just parsing
      return child.out if child.success?

      if child.status.exitstatus == GITMON_BUSY
        raise GitRPC::CommandBusy
      elsif child.err =~ /fatal: bad object ([a-zA-Z0-9]{40})/
        raise ObjectMissing.new("object not found - no match for id (#{$1})", $1)
      elsif child.err =~ /fatal: ambiguous argument '(.+)': unknown revision or path not in the working tree/
        raise ObjectMissing.new("object not found - no match for id (#{$1})", $1)
      else
        raise Error, child.err
      end
    end
  end
end
