# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    GIT_NW_REPACK_TRACE2 = {
      "GIT_TRACE2_GRAPHITE" => "af_unix:dgram:/var/run/datadog/dsd.socket",
      "GIT_TRACE2_GRAPHITE_CATEGORIES" => [
        "commit-graph",
        "delta-islands",
        "midx",
        "pack-bitmap",
        "pack-bitmap-write",
        "pack-objects",
      ].join(","),
    }

    rpc_writer :nw_rm
    def nw_rm
      res = spawn_git("nw-rm", "--force")
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["ok"]
    end

    rpc_reader :nw_linked?
    def nw_linked?
      res = spawn_git("nw-linked")
      !!res["ok"]
    end

    rpc_writer :nw_sync
    def nw_sync(ignore_locking_errors: false)
      res = spawn_git("nw-sync")
      return nil if res["ok"]
      # It is expected that sometimes this command will fail to acquire
      # locks. In this case we can ignore the error and report success to
      # avoid an expensive recompute checksum calculation that would be
      # triggered by disagreeing backends. Recomputing the checksum is
      # not necessary for nw-sync because this command does not change
      # the hard state.
      return nil if ignore_locking_errors && res["status"] == 2 && res["err"] =~ /fatal: could not get the (nw-sync|network) lock/
      raise GitRPC::CommandFailed.new(res)
    end

    rpc_cache_writer :nw_gc, output_varies: true, no_git_repo: true, require_unanimous: true
    def nw_gc(log: true, root_network: nil, window_byte_limit: nil, geometric: false, pristine: false, auto: false, max_cruft_size: nil)
      argv, env = [], {}
      argv << "--log" if log
      # TODO: reintroduce the `--root-network` argument.  This
      # currently tickles an edge case (at least) in the
      # `chromium/chromium` repository, where passing this makes
      # building bitmaps take 3+ hours, and thus the network is
      # failing maintenance.  See also
      # https://github.com/github/git/issues/1026
      argv << "--window-byte-limit=#{window_byte_limit}" if window_byte_limit
      argv << "--geometric" if geometric
      argv << "--pristine" if pristine
      argv << "--auto" if auto
      argv << "--max-cruft-size=#{max_cruft_size}" if max_cruft_size

      if trace2_enabled?(:nw_gc)
        env = GIT_NW_REPACK_TRACE2
      end

      spawn_git("nw-gc", argv, nil, maint_env(env))
    end

    def maint_env(env)
      if options[:info]
        if options[:info][:repo_name] && !options[:info][:repo_name].empty?
          env["GIT_NW_NWO"] = options[:info][:repo_name]
        end
        if options[:info][:request_id] && !options[:info][:request_id].empty?
          env["GIT_NW_REQUEST_ID"] = options[:info][:request_id]
        end
      end
      env
    end

    rpc_writer :nw_link
    def nw_link
      res = spawn_git("nw-link")
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      nil
    end

    rpc_writer :nw_unlink
    def nw_unlink
      res = spawn_git("nw-unlink")
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      nil
    end

    rpc_cache_writer :nw_repack, output_varies: true, require_unanimous: true
    def nw_repack(window_byte_limit: nil, geometric: false, max_cruft_size: nil)
      argv, env = [], {}
      argv << "--log"
      argv << "--window-byte-limit=#{window_byte_limit}" if window_byte_limit
      if trace2_enabled?(:nw_repack)
        env = GIT_NW_REPACK_TRACE2
      end
      argv << "--geometric" if geometric
      argv << "--max-cruft-size=#{max_cruft_size}" if max_cruft_size
      spawn_git("nw-repack", argv, nil, maint_env(env))
    end

    rpc_writer :nw_fsck, output_varies: true
    def nw_fsck(trust_synced: false, clean_output: false)
      argv = []
      argv << "--connectivity-only"
      argv << "--trust-synced" if trust_synced
      res = spawn_git("nw-fsck", argv)
      # The caller only cares about "ok". We return "out" and "err"
      # only for debugging purposes.
      {"ok" => res["ok"], "out" => res["out"], "err" => res["err"]}
    end

    rpc_writer :last_fsck, output_varies: true
    def last_fsck(never: false, force: false)
      argv = []
      argv << "--never" if never
      argv << "--force" if force
      res = spawn_git("last-fsck", argv)

      # The caller only cares about the text, not the exit statuses,
      # and we don't want to raise an exception if the backend exit
      # statuses disagree (e.g. because some backends have never run
      # fsck on this repo before.)
      res["status"] = 0

      res
    end

    rpc_writer :janitor, output_varies: true
    def janitor(fix: false, type: nil, ignore_hooks: false, no_check_ownership: false)
      argv = []
      argv << "--fix" if fix
      if type
        raise GitRPC::Error, "invalid type #{type}" unless ["network", "fork", "wiki", "gist"].include?(type)
        argv << "--type=#{type}"
      end
      argv << "--ignore-hooks" if ignore_hooks
      argv << "--no-check-ownership" if no_check_ownership

      spawn_git("janitor", argv)
    end
  end
end
