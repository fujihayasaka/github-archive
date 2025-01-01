# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    # Public: Write a blob into the repository
    # content - a string containing the blob contents
    #
    # Returns the object name for this new blob
    rpc_writer :write_blob
    def write_blob(content)
      raise ArgumentError.new("Content must be a String") unless content.is_a?(String)

      res = spawn_git("hash-object", ["-t", "blob", "--stdin", "-w"], content)
      if res["ok"]
        res["out"].rstrip
      else
        raise ::GitRPC::Error, res["err"]
      end
    end
  end
end
