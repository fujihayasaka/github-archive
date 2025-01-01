# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend

    rpc_reader :symbolic_ref
    def symbolic_ref(ref)
      res = spawn_git("symbolic-ref", ref)
      res["out"].chomp
    end
  end
end
