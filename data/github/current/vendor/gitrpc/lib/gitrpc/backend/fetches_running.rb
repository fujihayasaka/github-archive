# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    rpc_reader :fetches_running
    def fetches_running
      res = spawn(["ps", "axeo", "pid,stime,args"])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"].lines.grep(/git:.*upload/).size
    end

    rpc_reader :git_operations_running
    def git_operations_running
      res = spawn(["ps", "axeo", "pid,stime,args"])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"].lines.grep(/git:/).size
    end
  end
end
