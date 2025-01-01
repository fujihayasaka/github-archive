# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Backend
    rpc_writer :revert_range
    def revert_range(commit_oid1, commit_oid2 = nil, info = {})
      # Deprecated: fallback to HEAD oid
      parent_oid = info["parent_oid"]
      raise GitRPC::InvalidObject unless parent_oid.nil? || valid_sha1?(parent_oid)
      parent_oid ||= "HEAD"

      rdiff = reverse_diff(commit_oid1, commit_oid2, info["path"])
      tree_oid = apply_reverse_diff(parent_oid, rdiff)

      committer = symbolize_keys(info["committer"])
      author    = symbolize_keys(info["author"] || committer.dup)
      [author, committer].each do |person|
        person[:time] =
          case person[:time]
          when String
            iso8601(person[:time])
          when Array
            unixtime_to_time(person[:time])
          else
            raise ArgumentError, "Invalid time value: #{person[:time]}"
          end
      end

      opts = {
        :message   => info["message"],
        :committer => committer,
        :author    => author,
        :parents   => [parent_oid],
        :tree      => tree_oid
      }

      begin
        create_commit(opts, prettify: false)
      rescue GitRPC::Failure => e
        raise unless e.original.is_a?(GitRPC::CommandFailed) && e.original.err =~ /unknown revision|bad object/
        raise GitRPC::InvalidObject
      end
    end

    def reverse_diff(commit_oid1, commit_oid2 = nil, path = nil)
      commit1_oid, commit2_oid = select_commits(commit_oid1, commit_oid2)

      argv = ["-p", "-R"]
      if commit1_oid.nil?
        argv += [EMPTY_TREE_OID, commit2_oid]
      else
        base_oid = merge_base(commit1_oid, commit2_oid)
        if base_oid
          argv += [base_oid, commit2_oid]
        else
          # No merge base found, just do a direct diff between the commits
          argv += [commit1_oid, commit2_oid]
        end
      end

      argv += ["--", path] if path

      res = spawn_git("diff-tree", argv)
      if res["ok"]
        res["out"]
      elsif res["err"] =~ /unknown revision|bad object/
        raise GitRPC::InvalidObject
      else
        raise ::GitRPC::Error, res["err"]
      end
    end

    def apply_reverse_diff(oid, diff_text)
      with_tempfile("index") do |tmp_index|
        env = {"GIT_INDEX_FILE" => tmp_index.path}

        # set GIT_INDEX_FILE env
        res = spawn_git("read-tree", [oid], nil, env)
        if !res["ok"]
          raise ::GitRPC::Error, res["err"]
        end

        res = spawn_git("apply", ["--cached"], diff_text, env)
        if !res["ok"]
          raise ::GitRPC::Error, res["err"]
        end

        res = spawn_git("write-tree", [], nil, env)
        if res["ok"]
          res["out"].rstrip
        else
          raise ::GitRPC::Error, res["err"]
        end
      end
    end

    def with_tempfile(prefix)
      tmpfile = Tempfile.new(prefix)
      File.unlink(tmpfile.path)
      yield tmpfile
    ensure
      tmpfile.close
    end
  end
end
