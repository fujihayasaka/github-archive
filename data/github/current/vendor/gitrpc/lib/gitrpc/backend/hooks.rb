# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    rpc_reader :pre_receive_hook
    def pre_receive_hook(refline, sockstat_env = {})
      env = { "CUSTOM_HOOKS_ONLY" => "1"}
      env.merge!(sockstat_env.select { |k, v| k.to_s.start_with?("GIT_SOCKSTAT_VAR_") })

      hook_path =
        if sockstat_env["GIT_SOCKSTAT_VAR_pre_receive_fallback_enabled"] != "bool:true"
          if ["development", "test"].include?(sockstat_env["GIT_SOCKSTAT_VAR_githooks_env"])
            File.join(ENV["RAILS_ROOT"], "vendor/gitrpcd/build/githooks/ghe/fork/pre-receive")
          else
            "/usr/libexec/ghe-pre-receive-fork"
          end

        else
          "hooks/pre-receive"
        end

      res = spawn([hook_path], refline, env)
      {
        "ok" => res["ok"],
        "status" => res["status"],
        "out" => res["out"].force_encoding("UTF-8").scrub,
        "err" => res["err"].force_encoding("UTF-8").scrub
      }
    end
  end
end
