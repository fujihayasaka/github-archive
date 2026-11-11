# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :describe
    def describe(commitish, len)
      # Explicitly do not sanitize 'commitish' to support older tag names such
      # as '-v2.0' or similar. Because of this, 'commitish' MUST appear in the
      # argument list after '--' lest it be interpreted as an option.
      res = spawn_git("describe",
                      ["--long", "--tags", "--abbrev=#{len}", "--always", "--", commitish])
      if !res["ok"]
        if res["err"] =~ /^fatal: Not a valid object name/
          raise ::GitRPC::ObjectMissing
        elsif res["err"] =~ /^fatal: .* is neither a commit nor blob$/
          raise ::GitRPC::ObjectMissing
        else
          raise ::GitRPC::Error, "describe failed: #{res['err']}" if !res["ok"]
        end
      end
      res["out"].rstrip
    end
  end
end
