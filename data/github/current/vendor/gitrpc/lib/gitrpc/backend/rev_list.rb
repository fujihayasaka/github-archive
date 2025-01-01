# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :rev_list
    def rev_list(include_oids, exclude_oids, options)
      (include_oids + exclude_oids).each do |oid|
        if !oid.is_a?(String)
          raise TypeError, "expected a valid string object ID"
        end
        if !valid_sha1?(oid)
          raise GitRPC::InvalidObject, "expected a valid object ID"
        end
      end

      git_opts = []
      git_opts << "--max-count" << options["limit"].to_s if options["limit"]
      git_opts << "--skip" << options["skip"].to_s if options["skip"]
      git_opts << "--reverse" if options["reverse"]
      git_opts << "--merges" if options["merges"]

      include_oids = include_oids.map { |oid| "#{oid}^{commit}" }
      exclude_oids = exclude_oids.map { |oid| "#{oid}^{commit}" }

      if options["symmetric"]
        git_opts << include_oids.join("...")
      else
        git_opts.concat(include_oids)
      end

      git_opts.concat(exclude_oids.map { |oid| "^#{oid}" })

      unless options["paths"].nil? || options["paths"].empty?
        git_opts << "--"
        git_opts.concat(options["paths"])
      end

      res = spawn_git("rev-list", git_opts)
      if res["ok"]
        res["out"].split("\n")
      elsif res["err"] =~ /expected commit type, but the object dereferences to (\w+) type/
        raise GitRPC::InvalidObject, "Invalid object type, expected commit or tag but was #{$1}"
      elsif res["err"] =~ /ambiguous argument '([0-9a-f]+)\^\{commit\}'/
        raise GitRPC::ObjectMissing.new("object not found - no match for id", $1)
      elsif res["err"] =~ /bad revision '\^?([0-9a-f]+)\^\{commit\}'/
        raise GitRPC::ObjectMissing.new("object not found - no match for id", $1)
      else
        fail res["err"]
      end
    end
  end
end
