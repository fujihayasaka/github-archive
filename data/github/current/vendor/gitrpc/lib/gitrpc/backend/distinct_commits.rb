# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    rpc_reader :distinct_commits
    def distinct_commits(ref, exclude: [], count: false, new_syntax: true)
      ensure_sanitary_argument(ref)

      argv = []
      argv << "--newsyntax"
      argv << "--count" if count
      exclude.each do |oid|
        # Check only for sanitary arguments to make sure that we can tolerate
        # calls like '<SHA-1>^' (as in Push#large_push?).
        ensure_sanitary_argument(oid) if oid

        argv << "^#{oid}"
      end
      argv << ref

      res = spawn_git("distinct-commits", argv)
      raise GitRPC::CommandFailed.new(res) if !res["ok"]

      if count
        res["out"].to_i
      else
        res["out"].split("\n")
      end
    end
  end
end
