# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Run the pre-receive hook
    #
    # refline      - line describing the ref update, to feed to the hook's stdin
    # sockstat_env - hash of "GIT_SOCKSTAT_VAR_" variables
    #
    # We want to pass both refline and env as *args to `send_message`, which is
    # why we pass an empty **{}, otherwise when `env = {}`, ruby will pass
    # them as kwargs, and when we have string keys it will pass them as part of
    # the args.
    #
    # Returns a hash with "ok", "status", "out", "err" keys.
    def pre_receive_hook(refline, env)
      send_message(:pre_receive_hook, refline, env, **{})
    end
  end
end
