# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :ahead_behind
    def ahead_behind(base_ref, others, timeout = nil)
      ensure_valid_commitish(base_ref)

      argv = ["--stdin", "--base", base_ref]

      ret = spawn_git("ahead-behind", argv, others.join("\n"), {}, nil, timeout)
      ahead_behinds = {}

      if ret["ok"]
        ret["out"].each_line do |line|
          begin
            ref, ahead, behind = line.split(" ")
            ahead_behinds[ref] = [Integer(ahead), Integer(behind)]
          rescue ArgumentError, TypeError
            raise GitRPC::ObjectMissing
          end
        end
      end

      ahead_behinds
    end
  end
end
