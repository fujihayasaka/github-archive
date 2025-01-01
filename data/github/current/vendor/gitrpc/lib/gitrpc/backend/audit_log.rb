# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :sha1sum_audit_log
    def sha1sum_audit_log
      res = spawn(["sha1sum", "audit_log"])
      return res["out"][0..6] if res["ok"]
      return "missing" if res["err"] =~ /No such file or directory/
      "fail" + res["status"].to_s
    end

    rpc_reader :last_audit_log_time
    def last_audit_log_time
      res = spawn(["tail", "-1", "audit_log"])
      raise GitRPC::CommandFailed, res["err"] if !res["ok"]

      time_str = res["out"].strip.match(/\b\d{10}\b/)[0]
      Time.at(time_str.to_i)
    end
  end
end
