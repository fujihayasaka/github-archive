# frozen_string_literal: true
# typed: true

require "fileutils"
require "gitrpc/merge_tree_conflicts_parser"

# Functions used by other backend RPCs related to merge-tree.
module GitRPC
  class Backend
    ALREADY_MERGED_EXIT_STATUS = 17

    # Merge two trees using `git merge-tree` (merge-ort).
    #
    #  base           - `RuggedTreeLike` that `head` will be merged into.
    #  head           - `RuggedTreeLike` to merge into `base`.
    #  merge_options  - `Hash` of experimental options.
    #  resolutions    - `Hash[String, String]` mapping resolved paths to blob oids
    #
    #  On success (no conflicts), returns [String, nil] with the resulting tree oid.
    #
    #  When conflicts encountered, returns [nil, conflicts, err] with the
    #  conflicted index results.
    def merge_tree(base:, head:, merge_options:, resolutions:)
      tmpdir = create_custom_tmpdir(self.path, "objects/tmp_objdir-merge-tree-")

      extra_git_options = []
      extra_git_options.push("-c", "pack.tmpObjDir.showStats=true") if merge_options[:dogstats]
      extra_git_options.push("-c", "pack.tmpObjDir.keepUnpackedThreshold=#{merge_options[:keep_unpacked_threshold]}") if merge_options[:keep_unpacked_threshold]

      extra_options = []
      if merge_options[:merge_base]
        extra_options.push("--merge-base=#{merge_options[:merge_base].oid}")
      else
        extra_options.push("--find-closest-merge-base")
      end
      extra_options.push("--use-tmp-objdir=#{merge_options[:use_tmp_objdir_mode]}") if merge_options[:use_tmp_objdir_mode]
      extra_options.push("--tmp-objdir-location=#{tmpdir}")

      base_oid = base.oid
      head_oid = head.oid
      input = resolutions.to_a.flatten.join("\0".b)
      result = spawn_git(
        "merge-tree", [
          "--resolve-via-stdin",
          "--allow-unrelated-histories",
          "-z",
          "--exit-with-status-if-already-merged=#{ALREADY_MERGED_EXIT_STATUS}",
          *extra_options,
          base_oid,
          head_oid
        ],
        input,
        {},
        nil,
        nil,
        [
          "-c", "merge.renames=false",
          "-c", "rerere.enabled=false",
          *extra_git_options,
        ]
      )

      dogstats = nil
      if merge_options[:dogstats]
        dogstats = []
        stderr = result["err"].force_encoding("UTF-8")
        tags = { tags: [result["ok"] ? "status:success" : "status:failure"] }
        before = stderr.match(/before: loose objects: count = (\d+), total size = (\d+); packfiles: count = (\d+), total size = (\d+)/)
        after = stderr.match(/after: loose objects: count = (\d+), total size = (\d+); packfiles: count = (\d+), total size = (\d+)/)
        if before.nil? || after.nil?
          dogstats.push(["merge_tree.dogstats.failure", 1, tags])
        else
          looseCount = Integer(after[1])
          dogstats.push(["merge_tree.loose_objects_count", looseCount, tags])
          dogstats.push(["merge_tree.loose_objects_count_delta", looseCount - Integer(before[1]), tags])
          looseSize = Integer(after[2])
          dogstats.push(["merge_tree.loose_objects_size", looseSize, tags])
          dogstats.push(["merge_tree.loose_objects_size_delta", looseSize - Integer(before[2]), tags])
          packCount = Integer(after[3])
          dogstats.push(["merge_tree.packfiles_count", packCount, tags])
          dogstats.push(["merge_tree.packfiles_count_delta", packCount - Integer(before[3]), tags])
          packSize = Integer(after[4])
          dogstats.push(["merge_tree.packfiles_size", packSize, tags])
          dogstats.push(["merge_tree.packfiles_size_delta", packSize - Integer(before[4]), tags])
        end
      end

      if result["ok"]
        output = result["out"].chomp.sub(/\0+$/, "")
        ensure_valid_full_oid(output)
        [output, nil, nil, dogstats]
      elsif result["status"] == ALREADY_MERGED_EXIT_STATUS
        [nil, nil, "already_merged", dogstats]
      else
        begin
          conflicts = GitRPC::MergeTreeConflictsParser.new(result["out"]).parse.map(&:to_h)
        rescue GitRPC::MergeTreeConflictsParser::ParseError
          raise GitRPC::CommandFailed.new(result)
        end
        [nil, sort(conflicts), nil, dogstats]
      end
    ensure
      FileUtils.rm_rf(tmpdir) if tmpdir && File.exist?(tmpdir)
    end

    private

    def sort(conflicts)
      conflicts.sort_by { |ci| ci.values.map { |x| x&.dig(:path) }.compact.sort.uniq }
    end
  end
end
