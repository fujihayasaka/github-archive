# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    GIT_BLAME_TREE_TRACE2 = {
      "GIT_TRACE2_GRAPHITE" => "af_unix:dgram:/var/run/datadog/dsd.socket",
      "GIT_TRACE2_GRAPHITE_CATEGORIES" => ["blame-tree"].join(","),
    }

    def parse_blame(data)
      map = {}
      data.split("\0").map do |line|
        commit_oid, path = line.split("\t", 2)
        commit_oid.force_encoding "utf-8"
        map[path] = commit_oid
      end
      map
    end

    rpc_reader :blame_tree
    def blame_tree(commit_oid, path = nil, recursive = true, use_cache = true)
      ensure_valid_oid(commit_oid)

      opts = ["-z"]
      argv, env = ["--"], {}

      # blame-tree wants 0 for pathless non-recursive blames
      if !recursive
        if path && !path.empty?
          opts << "--max-depth=1"
        else
          opts << "--max-depth=0"
        end
      end

      if path && !path.empty?
        argv << path
      end

      if trace2_enabled?(:blame_tree)
        env = GIT_BLAME_TREE_TRACE2
      end

      res = spawn_git("blame-tree", [opts, commit_oid, argv].flatten,
                      nil, env)
      if res["ok"]
        parse_blame(res["out"])
      else
        raise ::GitRPC::Error, res["err"]
      end
    end
  end
end
