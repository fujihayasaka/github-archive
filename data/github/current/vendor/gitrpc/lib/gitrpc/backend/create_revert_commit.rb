# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Backend
    rpc_writer :create_revert_commit_rugged
    def create_revert_commit_rugged(*args)
      options, err = create_revert_commit_options(*args)
      return [nil, err] unless err.nil?

      [create_commit(options), nil]
    rescue Rugged::IndexError
      [nil, "merge_conflict"]
    rescue Rugged::TreeError, Rugged::RevertError => e
      [e.to_s, "error"]
    end

    rpc_reader :stage_signed_revert_commit
    def stage_signed_revert_commit(*args)
      options, err = create_revert_commit_options(*args)
      return [nil, err] unless err.nil?

      [create_commit(options, true), nil]
    rescue Rugged::IndexError
      [nil, "merge_conflict"]
    rescue Rugged::TreeError, Rugged::RevertError => e
      [e.to_s, "error"]
    end

    rpc_writer :persist_signed_revert_commit
    def persist_signed_revert_commit(base_data, signature, *args)
      # ensure that any blobs/trees are created on all replicas.
      _, err = create_revert_commit_options(*args)
      return [nil, err] unless err.nil?

      [create_commit_with_signature_raw(base_data, signature), nil]
    rescue Rugged::IndexError
      [nil, "merge_conflict"]
    rescue Rugged::TreeError, Rugged::RevertError => e
      [e.to_s, "error"]
    end

    def create_revert_commit_options(revert, ours, author, commit_message, mainline, committer = nil)
      revert_parent = begin
        resolve_commit("#{revert}^")
      rescue GitRPC::InvalidObject
        OpenStruct.new(oid: EMPTY_TREE_OID)
      end
      revert = begin
        ensure_valid_full_oid(revert)
        OpenStruct.new(oid: revert)
      end
      ours = begin
        ensure_valid_full_oid(ours)
        OpenStruct.new(oid: ours)
      end

      author = symbolize_keys(author)
      author[:time] = iso8601(author[:time])

      committer ||= author
      committer = symbolize_keys(committer)
      committer[:time] = iso8601(committer[:time])

      merge_options = {
        :fail_on_conflict => true,
        :skip_reuc => true,
        :mainline => mainline,
        :no_recursive => true,
      }

      merge_options[:merge_base] = revert

      tree, conflicts, err, _ = merge_tree(
        base: revert_parent,
        head: ours,
        merge_options: merge_options,
        resolutions: []
      )
      return [nil, err] if err
      return [nil, "merge_conflict"] if conflicts

      options = {
        :message    => commit_message,
        :committer  => committer,
        :author     => author,
        :parents    => [ours],
        :tree       => tree,
      }

      [options, nil]
    end

    def build_revert_commit_message(commit)
      <<-EOS
Revert "#{commit.summary}"

This reverts commit #{commit.oid}.
      EOS
    end

    RevertTimeout = Class.new(Timeout)

    def revert_commits_rev_list(range_start_commit_oid, range_end_commit_oid)
      res = spawn_git("rev-list", [
        "--no-commit-header",
        "--pretty=format:%H%x09%P%x09%s",
        range_end_commit_oid,
        "^#{range_start_commit_oid}"
      ])
      if res["ok"]
        res["out"].chomp.split("\n").map do |ln|
          oid, parents, summary = ln.split("\t", 3)
          OpenStruct.new(oid: oid, parent_ids: parents.split(" "), summary: summary)
        end
      elsif res["err"] =~ /expected commit type, but the object dereferences to (\w+) type/
          raise GitRPC::InvalidObject, "Invalid object type, expected commit or tag but was #{$1}"
      elsif res["err"] =~ /ambiguous argument '([0-9a-f]+)\^\{commit\}'/
        raise GitRPC::ObjectMissing.new("object not found - no match for id", $1)
      elsif res["err"] =~ /bad revision '\^?([0-9a-f]+)\^\{commit\}'/
        raise GitRPC::ObjectMissing.new("object not found - no match for id", $1)
      else
        fail res["err"]
      end
    end

    # Public: Revert all commits starting at (but not including) `range_start_commit_oid`
    # and ending at `range_end_commit_oid`, on top of `target_commit_oid`.
    rpc_writer :create_revert_commits_for_range
    def create_revert_commits_for_range(range_start_commit_oid, range_end_commit_oid, target_commit_oid, author, committer, timeout)
      ours = resolve_commit(target_commit_oid)


      commits = revert_commits_rev_list(range_start_commit_oid, range_end_commit_oid)

      deadline = timeout ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout : nil

      revert_commit_id = commits.inject(ours.oid) do |result_id, commit|
        if deadline && deadline < Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise RevertTimeout
        end

        if commit.parent_ids.size > 1
          return ["merge commit encountered in specified commit range", "error"]
        end

        message = build_revert_commit_message(commit)

        options, err = create_revert_commit_options(commit.oid, result_id, author, message, nil, committer)
        return [nil, err] unless err.nil?

        create_commit(options)
      end

      [revert_commit_id, nil]
    end
  end
end
