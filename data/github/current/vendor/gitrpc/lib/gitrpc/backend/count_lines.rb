# typed: true
# frozen_string_literal: true

module GitRPC
  class Backend
    rpc_reader :count_lines
    def count_lines(oids)
      counts = {}

      res = checked_spawn_git!("cat-file", ["--batch-check=%(objecttype) %(lc)", "-Z"], oids.join("\0"))

      res["out"].split("\0").each_with_index do |line, i|
        case line
        # if line contains "missing" then the object is missing
        # so the line count should be nil
        when /missing^/
          lc = nil
        # if line matches "blob \d+" then it is a valid line count
        when /^blob (\d+)$/
          lc = $1.to_i
        # anything else is a different object type, or is an error.. skip!
        else
          next
        end

        oid = oids[i]
        counts[oid] = lc
      end

      counts
    end
  end
end
