# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    include GitRPC::Util

    # Public: Resolve an object name to a SHA1.
    #
    # Returns an oid or nil if the name could not be resolved.
    rpc_reader :rev_parse
    def rev_parse(object_name)
      if object_name.nil?
        raise TypeError, "object_name must be specified"
      elsif !sanitary_revspec?(object_name)
        return
      elsif valid_full_oid?(object_name)
        object_name
      end

      res = spawn_git("rev-parse", ["--verify", "--end-of-options", "#{object_name}"])
      if res["ok"]
        res["out"].rstrip
      elsif res["err"].include?("is ambiguous")
        raise GitRPC::Failure.new(GitRPC::InvalidObject.new("ambiguous object: #{object_name}"))
      else
        nil
      end
    end
  end
end
