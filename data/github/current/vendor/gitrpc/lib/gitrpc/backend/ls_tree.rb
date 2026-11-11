# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :ls_tree
    def ls_tree(treeish, path: nil, long: nil, recurse: nil, show_trees: nil, byte_limit: nil)
      args = ["-z"]
      args << "-l" if long
      args << "-r" if recurse
      args << "-t" if show_trees
      args << "--"
      args << treeish

      Array(path).each do |p|
        args << p
      end

      res = spawn_git("ls-tree", args, nil, {}, byte_limit)
      if !res["ok"] && !(res["truncated"] && res["err"] == "")
        raise GitRPC::CommandFailed.new(res)
      end

      entries = []
      result = {}
      outlines = res["out"].split("\0")
      if res["truncated"]
        result["truncated"] = true
        # If the last line got truncated, drop it.
        outlines = outlines[0...-1] if res["out"][-1] != "\0"
      else
        result["truncated"] = false
      end

      outlines.each do |outline|
        others, path = outline.split("\t", 2)
        entry = others.split(" ") + [path]
        entries << entry
      end

      result["entries"] = entries
      result
    end
  end
end
