# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    # Public: Find which branches contain a given commit
    #
    # oid - a String commit oid
    #
    # Returns Array of String branch names (empty if no branches contain the commit)
    rpc_reader :branch_contains
    def branch_contains(oid)
      ensure_valid_oid(oid)

      res = spawn_git("branch", ["--contains", oid])
      handle_missing_or_wrong_object_type(res) unless res["ok"]

      refs = []
      res["out"].each_line do |line|
        refs << line[2..-1].rstrip
      end
      refs
    end

    # Public: Find which tags contain a given commit
    #
    # oid - a String commit oid
    #
    # Returns Array of String tag names (empty if no tags contain the commit)
    rpc_reader :tag_contains
    def tag_contains(oid)
      ensure_valid_oid(oid)

      res = spawn_git("tag", ["--contains", oid])
      handle_missing_or_wrong_object_type(res) unless res["ok"]

      tags = []
      res["out"].each_line do |line|
        tags << line.rstrip
      end
      tags
    end

    # Public: Find whether commits are "visible" (reachable from branches or tags)
    #
    # oids - an Array of String commit oids
    #
    # Returns Hash with String keys and Boolean values,
    #   where the keys are commit oids,
    #   and the values indicate whether the commit is visible
    rpc_reader :commits_visible
    def commits_visible(oids)
      finds  = []
      result = {}
      oids.each do |oid|
        finds << "--find=#{oid}"
        result[oid] = false
      end

      res = spawn_git("rev-list", finds + %w[--branches --tags])

      if !(res["status"] == 0 || res["status"] == 1)  # 0 = found, 1 = not found
        handle_missing_or_wrong_object_type(res)
      end

      res["out"].each_line do |line|
        result[line.rstrip] = true
      end
      result
    end
  end
end
