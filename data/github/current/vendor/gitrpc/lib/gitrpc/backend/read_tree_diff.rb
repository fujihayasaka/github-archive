# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Backend
    def parse_diff_status(status)
      case status
      when "A" then "added"
      when "C" then "copied"
      when "D" then "deleted"
      when "M" then "modified"
      when "R" then "renamed"
      when "T" then "typechange"
      when "U" then "untracked"
      when "X" then "unknown"
      end
    end

    rpc_reader :read_tree_diff
    def read_tree_diff(commit1_oid, commit2_oid = nil, paths: [], diff_trees: false)
      if (commit1_oid.nil? || commit1_oid == NULL_OID) &&
          (commit2_oid.nil? || commit2_oid == NULL_OID)
        return []
      end

      commit1, commit2 = select_commits(commit1_oid, commit2_oid).map do |commit|
        if commit.nil? || commit == NULL_OID
          EMPTY_TREE_OID
        else
          "#{commit}^{#{diff_trees ? "tree" : "commit"}}"
        end
      end

      res = spawn_git("diff-tree", ["-z", "-r", commit1, commit2, "--", *paths])
      unless res["ok"]
        if res["err"] =~ /error: ([0-9a-f]+)\^\{.*\}: expected .* type, but the object dereferences to .* type/
          raise GitRPC::InvalidObject, "Invalid commit oid #{$1}"
        else
          raise GitRPC::Failure, res
        end
      end

      deltas = []
      delta = {}, need_src = false, need_dst = false
      res["out"].split("\0").each do |line|
        if !need_src && !need_dst
          match = line.match(/\A:([0-9]{6}) ([0-9]{6}) ([0-9a-f]*) ([0-9a-f]*) ([ACDMRTUX])[0-9]*\z/)
          raise GitRPC::Error, "invalid diff line" unless match

          delta = {
            "status" => parse_diff_status(match[5]),
            "old_file" => {
              "oid" => match[3],
              "mode" => match[1].to_i(8),
            },
            "new_file" => {
              "oid" => match[4],
              "mode" => match[2].to_i(8),
            }
          }

          need_src = true
          need_dst = %w[copied renamed].include?(delta["status"])
        elsif need_src
          delta["old_file"]["path"] = line
          delta["new_file"]["path"] = line unless need_dst
          need_src = false
        else
          delta["new_file"]["path"] = line
          need_dst = false
        end

        deltas << delta unless need_src || need_dst
      end

      deltas
    end
  end
end
