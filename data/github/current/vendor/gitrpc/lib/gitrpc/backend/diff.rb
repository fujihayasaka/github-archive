# typed: true
# frozen_string_literal: true

module GitRPC
  class Backend
    rpc_reader :file_changed?
    def file_changed?(file, before, after)
      ensure_valid_commitish(before)
      ensure_valid_commitish(after)

      res = if null_oid?(before)
        spawn_git("show", ["--name-only", "--pretty=format:", after])
      else
        spawn_git("diff", ["--name-only", before, after])
      end

      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"].split("\n").include?(file)
    end

    rpc_reader :diff_shortstat
    def diff_shortstat(range)
      if range.start_with?("-")
        raise GitRPC::InvalidOid, "unacceptable range: '#{range}'"
      end

      res = spawn_git("diff", ["--shortstat", "--no-ext-diff", range, "--"])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"].strip
    end

    rpc_reader :diff_tree
    def diff_tree(before, after, include_tree_entry: false, recurse: false)
      ensure_valid_commitish(before)
      ensure_valid_commitish(after)

      argv = ["-z"]
      argv << "-t" if include_tree_entry
      argv << "-r" if recurse
      argv += [before, after]

      res = spawn_git("diff-tree", argv)
      if !res["ok"]
        raise GitRPC::ObjectMissing.new(res["err"], $1) if res["err"] =~ /fatal: bad object ([0-9a-f]{40})/
        raise GitRPC::CommandFailed.new(res)
      end
      res["out"].split("\0").each_slice(2).to_a
    end

    rpc_reader :diff_tree_path_renamed
    def diff_tree_path_renamed(commit_oid, similarity_index: nil, new_path: nil)
      ensure_valid_commitish(commit_oid)

      argv = ["-z"]
      argv << "-r"
      argv << "--no-commit-id"
      argv << "--name-status"
      argv << "--diff-filter=R"
      argv << "--skip-to=#{new_path}" if new_path
      if similarity_index
        argv << "-M#{similarity_index}%"
      else
        argv << "-M100%"
      end
      argv << "--end-of-options"
      argv << commit_oid

      res = spawn_git("diff-tree", argv)
      if !res["ok"]
        raise GitRPC::ObjectMissing.new(res["err"], $1) if res["err"] =~ /fatal: bad object ([0-9a-f]{40})/
        raise GitRPC::CommandFailed.new(res)
      end
      return [] if res["out"].empty?
      res["out"].split("\0").each_slice(3).to_a[0]
    end
  end
end
