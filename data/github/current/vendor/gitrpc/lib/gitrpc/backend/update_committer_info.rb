# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    rpc_writer :update_committer_info

    def update_committer_info(start_commit_oid, end_commit_oid, committer)
      committer = symbolize_keys(committer)
      committer[:time] = iso8601(committer[:time])

      ensure_valid_full_oid(start_commit_oid)
      ensure_valid_full_oid(end_commit_oid)

      # Ensure start_commit_oid is a descendant of end_commit_oid - prevents
      # us from writing new trees if we get bad (non-linearized) inputs.
      is_linear = descendant_of([[start_commit_oid, end_commit_oid]])
      raise GitRPC::Error, "#{end_commit_oid} is not an ancestor of #{start_commit_oid}" unless is_linear[[start_commit_oid, end_commit_oid]]

      res = checked_spawn_git!("replay",
        [
          "--show-oid-mappings-only",
          "--onto=#{end_commit_oid}",
          "#{end_commit_oid}..#{start_commit_oid}"
        ],
        nil,
        {
          "GIT_COMMITTER_NAME"  => committer[:name],
          "GIT_COMMITTER_EMAIL" => committer[:email],
          "GIT_COMMITTER_DATE"  => committer[:time].iso8601,
        })

      if res["out"].empty?
        # no output means nothing needed to be rebased, output is "onto"
        start_commit_oid
      else
        # If the output is non-empty, it will be a list of "<before>, <after>"
        # commit OID pairs in replay order. To get the replayed tip (with the
        # new committer info), we just need the last line of the output.
        last_line = res["out"].split("\n").last.split
        raise GitRPC::Error, "replayed tip #{last_line[0]} did not match input tip #{start_commit_oid}" unless last_line[0] == start_commit_oid
        last_line[1]
      end
    end
  end
end
