# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    # This is a read-only method, but we treat it as a writer because we don't
    # want to claim that an object exists unless a quorum of replicas agree
    # that it does.
    rpc_writer :object_exists?
    def object_exists?(oid, type = nil)
      if type
        res = spawn_git("cat-file", ["-t", oid])
        res["ok"] && res["out"].chomp == type
      else
        res = spawn_git("cat-file", ["-e", oid])
        res["ok"]
      end
    end
  end
end
