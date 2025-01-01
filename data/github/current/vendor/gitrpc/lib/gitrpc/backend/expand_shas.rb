# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :expand_shas
    def expand_shas(sha_list, expected_type)
      rugged.expand_oids(sha_list, expected_type)
    end

    rpc_reader :alternative_expand_shas
    def alternative_expand_shas(sha_list, expected_type)
      if sha_list.any? { |sha| sha !~ /\A[a-fA-F\d]*\Z/ }
        raise BadRepositoryState.new("expand_shas - unable to parse OID - contains invalid characters")
      end

      input = sha_list.map { |sha| sha.downcase }.join("\n")
      res = spawn_git("cat-file", ["--batch-check=%(objectname) %(objecttype)"], input)
      raise GitRPC::CommandFailed.new(res) if !res["ok"]

      result = {}
      sha_list.zip(res["out"].lines).map do |short, line|
        next unless line
        oid, type = line.split
        next if !type || type == "missing" || (expected_type && type != expected_type)
        result[short] = oid if oid.start_with?(short.downcase)
      end
      result
    end
  end
end
