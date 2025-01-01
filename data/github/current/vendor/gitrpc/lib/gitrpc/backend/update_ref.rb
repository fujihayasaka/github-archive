# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    def ensure_in_test
      raise DGitRequired if ENV["RAILS_ENV"] != "test"
      true
    end

    # NOTE: These will need to go through 3PC in dgit,
    # not simply writers
    rpc_writer :update_ref
    def update_ref(ref, new_value, old_value, dgit_disabled: false, committer_date: nil, repairing: false)
      ensure_valid_refname(ref)
      ensure_valid_full_oid(new_value)
      ensure_valid_full_oid(old_value) if old_value

      env = {}
      env["DGIT_DISABLED"] = "1" if (dgit_disabled && ensure_in_test) || repairing
      env["GIT_COMMITTER_DATE"] = committer_date if committer_date

      args = [ref, new_value]
      args << old_value if old_value
      res = spawn_git("update-ref", args, nil, env)
      if !res["ok"]
        raise GitRPC::RefUpdateError, res["err"]
      end
    end

    rpc_writer :update_ref_batch
    def update_ref_batch(batch, reason: nil, dgit_disabled: false, committer_date: nil, committer_name: nil, committer_email: nil, pusher: nil, sockstat_env: {}, tz: nil)
      args = ["--stdin"]
      args += ["-m", reason] if reason

      env = {}
      env["DGIT_DISABLED"] = "1" if dgit_disabled && ensure_in_test
      env["GIT_COMMITTER_DATE"] = committer_date if committer_date
      env["GIT_COMMITTER_NAME"] = committer_name if committer_name
      env["GIT_COMMITTER_EMAIL"] = committer_email if committer_email
      env["GIT_PUSHER"] = pusher if pusher
      env.merge!(sockstat_env.select { |k, v| k.to_s.match(/^GIT_SOCKSTAT_VAR_/) })
      env["TZ"] = tz if tz

      res = spawn_git("update-ref", args, batch, env)
      if !res["ok"]
        raise GitRPC::RefUpdateError, res["err"]
      end
    end

    rpc_writer :delete_ref
    def delete_ref(ref, old_value, dgit_disabled: false, committer_date: nil)
      ensure_valid_refname(ref)
      ensure_valid_full_oid(old_value) if old_value

      env = {}
      env["DGIT_DISABLED"] = "1" if dgit_disabled && ensure_in_test
      env["GIT_COMMITTER_DATE"] = committer_date if committer_date

      args = ["-d", ref]
      args << old_value if old_value
      res = spawn_git("update-ref", args, nil, env)
      if !res["ok"]
        raise GitRPC::RefUpdateError, res["err"]
      end
    end

    rpc_writer :update_symbolic_ref
    def update_symbolic_ref(ref, new_value)
      ensure_valid_refname(ref)
      ensure_valid_refname(new_value)

      res = spawn_git("symbolic-ref", [ref, new_value])
      if !res["ok"]
        raise GitRPC::RefUpdateError, res["err"]
      end
    end
  end
end
