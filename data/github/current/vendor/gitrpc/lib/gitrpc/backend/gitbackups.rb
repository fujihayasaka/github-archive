# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    # Although we write into the DB and permanent storage, this is a reader as
    # far as GitRPC is concerned since we only read data from the filesystem.
    rpc_reader :gitbackups_perform
    def gitbackups_perform(wiki, parent = nil)
      argv = ["/data/gitbackups/current/bin/git-backup", "perform"]
      if parent
        argv << "--priming-source"
        argv << parent.to_s
      end

      # Wiki backup is weird in that it actually runs in the parent repository's
      # RPC context, so we need to figure out the wiki's path and run the backup
      # from there.
      path = if wiki
        repo_dir = rugged.path
        repo     = File.basename(repo_dir)
        repo_id  = File.basename(repo_dir, ".git")
        repo_dir.sub(repo, "#{repo_id}.wiki.git")
      else
        rugged.path
      end

      opts = { :chdir => path }
      native.spawn(argv, nil, {}, opts)
    end

    rpc_writer :gitbackups_restore
    def gitbackups_restore(spec, target)
      argv = ["/data/gitbackups/current/bin/git-backup", "restore", "--repository", spec, "--target", target]
      result = native.spawn(argv, nil, {}, {})
      if result[:ok]
        return :ok
      end
      if result[:status] == 4
        return :not_found
      end

      [result[:out], result[:err]]
    end
  end
end
