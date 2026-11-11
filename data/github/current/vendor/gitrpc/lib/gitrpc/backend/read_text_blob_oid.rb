# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    # Fetch the first non-binary blob's oid from a gist repo.
    # This is typically used to serve as a default blob
    # for URLs like https://gist.github.com/12345.txt
    #
    # commit_oid - 40 char oid string identifying the commit
    #              of which to find the first text blob
    #
    # Returns blob's 40 char oid or nil
    rpc_reader :read_text_blob_oid
    def read_text_blob_oid(commit_oid)
      res = spawn_git("ls-tree",
                      ["--format=%(objectmode) %(objectname) b/%(eolinfo:blob)%x09%(path)", "-z", "--end-of-options",
                       commit_oid])

      raise GitRPC::CommandFailed.new(res) if !res["ok"]

      res["out"].split("\0").each do |line|
        # The textmode options here are "b/lf", "b/crlf", "b/mixed", "b/none", and "b/-text".
        # The latter is binary, and all other options are text.
        # "b/" is also possible for non-regular files, and we'll accept it for
        # a symlink.
        attrs, _file = line.split("\t", 2)
        mode, oid, eol = attrs.split(" ", 3)
        if %w[100644 100755 120000].include?(mode) && eol != "b/-text"
          return oid
        end
      end

      nil
    end
  end
end
