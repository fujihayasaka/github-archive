# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    RECURSION_LIMT = 3

    rpc_reader :peel_to_commit_or_tree
    def peel_to_commit_or_tree(oid)
      return nil if oid.nil? || null_oid?(oid)
      raise GitRPC::ObjectMissing.new("invalid object ID: #{oid}", oid) unless valid_oid?(oid)
      res = checked_spawn_git!("cat-file", ["--batch-check=%(objectname) %(objecttype)"], "%s^{}" % oid)
      line = res["out"].chomp

      # We expect the result to be one line "<target-oid> SP <target-type> LF"
      # in the happy path.  However, if the given OID was bogus, the output line
      # contains "<input> SP missing LF" -- where <input> is the formatted
      # string that we passed in. If the given OID is too short to resolve to a
      # single object, the output line is "<input> SP ambiguous".

      ary = line.split(" ")
      if ary.length != 2 || %w[missing ambiguous].include?(ary[1])
        raise GitRPC::ObjectMissing.new("failed to peel object: #{line}", oid)
      end

      if %w[commit tree].include?(ary[1])
        ary[0]
      else
        nil
      end
    end
  end
end
