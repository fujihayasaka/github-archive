# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Backend
    rpc_writer :rewrite_merge_commit
    def rewrite_merge_commit(*args)
      options = rewrite_merge_commit_options(*args)
      create_commit(options, prettify: false)
    end

    rpc_reader :stage_signed_rewrite_merge_commit
    def stage_signed_rewrite_merge_commit(*args)
      options = rewrite_merge_commit_options(*args)
      create_commit(options, true, prettify: false)
    end

    rpc_writer :persist_signed_rewrite_merge_commit
    def persist_signed_rewrite_merge_commit(base_data, signature, *args)
      create_commit_with_signature_raw(base_data, signature)
    end

    def rewrite_merge_commit_options(commit_oid, info, squash_commits = false)
      raise ArgumentError.new("Committer is required") unless info["committer"]
      raise ArgumentError.new("Commit message is required") unless info["message"]

      message   = info["message"]
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

      ensure_valid_full_oid(commit_oid)
      tree = "#{commit_oid}^{tree}"
      parents = if squash_commits
        ["#{commit_oid}^1"]
      else
        res = spawn_git("rev-parse", ["#{commit_oid}^@"])
        if res["ok"]
          res["out"].split("\n")
        elsif res["err"].include?(NOT_GIT_REPO)
          raise GitRPC::InvalidRepository, res["err"].chomp
        else
          raise GitRPC::ObjectMissing.new(res["err"].chomp, commit_oid)
        end
      end

      {
        :message    => message,
        :committer  => committer,
        :author     => author,
        :parents    => squash_commits ? [parents.first] : parents,
        :tree       => tree,
      }
    end
  end
end
