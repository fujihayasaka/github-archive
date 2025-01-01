# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    # Public: Get the raw text for a diff
    #
    # commit1_oid - a commit sha1
    # commit2_oid - a commit sha1
    # timeout - Maximum number of seconds that the operation can take to complete
    #
    # Returns the raw diff text as a String
    rpc_reader :native_diff_text
    def native_diff_text(commit1_oid, commit2_oid, paths = [], full_index: false, timeout: nil)
      paths = Array(paths)
      commit1_oid, commit2_oid = select_commits(commit1_oid, commit2_oid)

      argv = DIFF_TREE_DETECT_RENAMES + %w[-p]
      argv << "--full-index" if full_index

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

      unless paths.empty?
        argv << "--"
        argv += paths
      end

      res = spawn_git("diff-tree", argv, nil, {}, nil, timeout)
      if res["ok"]
        res["out"]
      elsif res["err"] =~ /unknown revision|bad object/
        raise GitRPC::InvalidObject
      else
        raise GitRPC::Error, res["err"]
      end
    end

    # Public: Get the raw text for a diff in patch format
    #
    # commit1_oid - a commit sha1
    # commit2_oid - a commit sha1
    # timeout - Maximum number of seconds that the operation can take to complete
    #
    # Returns the diff text in patch format as a String
    rpc_reader :native_patch_text
    def native_patch_text(commit1_oid, commit2_oid = nil, full_index: false, timeout: nil)
      commit1_oid, commit2_oid = select_commits(commit1_oid, commit2_oid)

      argv = ["--stdout", "--no-signature"]
      if commit1_oid.nil?
        argv += ["--root", commit2_oid]
      else
        argv << "#{commit1_oid}..#{commit2_oid}"
      end

      argv << "--full-index" if full_index

      res = spawn_git("format-patch", argv, nil, {}, nil, timeout)
      if res["ok"]
        res["out"]
      elsif res["err"] =~ /unknown revision|bad object|Invalid revision range/
        raise GitRPC::InvalidObject
      else
        raise GitRPC::Error, res["err"]
      end
    end

    # Private: Determine the two oids necessary to perform a diff. Ensures
    # any OIDs returned are full SHAs, but does not necessarily validate
    # whether they exist in the repository or aren't some other type of
    # object.
    #
    # This is a utility method that will fill in the parent commit if one
    # hasn't been specified by the caller.
    def select_commits(commit1_oid, commit2_oid = nil)
      if commit2_oid
        if !valid_sha1?(commit2_oid) || (commit1_oid && !valid_sha1?(commit1_oid))
          raise GitRPC::InvalidObject
        end
        [commit1_oid, commit2_oid]
      else
        raise GitRPC::InvalidObject unless valid_sha1?(commit1_oid)
        res = spawn_git("rev-parse", ["--revs-only", "--end-of-options", "#{commit1_oid}^@", "--"])
        raise GitRPC::InvalidObject unless res["ok"]

        # The output contains all the parents, but we only want the first one.
        # Look for the first newline and take everything before it.
        newline = res["out"].index("\n")
        parent_oid = newline.nil? ? res["out"].chomp : res["out"][0..newline-1]
        if parent_oid.empty?
          # commit1_oid is valid, but has no parent
          [nil, commit1_oid]
        else
          # If the output is not empty, the first line should be a valid OID. If
          # not, there's an issue with Git or our parsing so ensure_valid_sha1
          # should raise an exception.
          ensure_valid_sha1(parent_oid)
          [parent_oid, commit1_oid]
        end
      end
    end
  end
end
