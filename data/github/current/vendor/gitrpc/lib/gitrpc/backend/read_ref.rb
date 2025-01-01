# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :read_symbolic_ref
    def read_symbolic_ref(refname)
      res = spawn_git("symbolic-ref", ["-q", refname])

      err = res["err"].chomp
      if err.include?(NOT_GIT_REPO)
        raise GitRPC::InvalidRepository, "path is not a repository: #{@path}"
      elsif !res["ok"]
        if res["status"] == 1
          raise GitRPC::InvalidReferenceName, refname
        else
          raise GitRPC::Failure.new(GitRPC::CommandFailed.new(res))
        end
      else
        res["out"].force_encoding("UTF-8").chomp
      end
    end
  end
end
