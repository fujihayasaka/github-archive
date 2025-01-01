# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    # Fetch the first non-auto generated filename from a gist
    # repository. This is typically used as the gist's title.
    #
    # Returns a String or nil
    rpc_reader :gist_title
    def gist_title(oid)
      return nil if oid.nil?

      args = ["-r", "-z", oid]
      res = spawn_git("ls-tree", args)
      if res["ok"]
        entries = res["out"].force_encoding("UTF-8").chomp.split("\x00").map do |entry|
          mode, type, id, name = entry.match(/^(\d+)\s(\S+)\s(\S+)\t(.+)$/m).captures
          { mode: mode, object_type: type, id: id, name: name }
        end

        entries.each do |entry|
          next unless entry[:object_type] == "blob"

          # get last component of full path
          filename = entry[:name].split("/").last
          return filename if filename !~ /^gistfile/
        end

        nil
      elsif res["err"].include?(NOT_GIT_REPO)
        raise GitRPC::InvalidRepository, "path is not a repository: #{@path}"
      elsif res["err"] =~ /[Nn]ot a valid object name/
        raise ::GitRPC::InvalidObject, res["err"]
      elsif res["err"] =~ /[Nn]ot a tree/ ||
            res["err"] =~ /failed to parse tree/ ||
            res["err"] =~ /empty filename in tree entry/
        raise ::GitRPC::ObjectMissing, res["err"]
      else
        raise ::GitRPC::CommandFailed, res
      end
    end
  end
end
