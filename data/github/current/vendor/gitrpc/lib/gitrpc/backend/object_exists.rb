# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    rpc_reader :object_exists?
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
