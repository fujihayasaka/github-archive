# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    rpc_writer :repack
    def repack
      res = spawn_git("repack")
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      nil
    end
  end
end
