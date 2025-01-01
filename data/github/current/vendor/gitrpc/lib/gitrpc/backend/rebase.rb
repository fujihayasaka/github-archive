# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "fileutils"
require "gitrpc/experiment"

module GitRPC
  class Backend
    HAS_CONFLICTS_EXIT_STATUS = 1
    TOO_MANY_COMMITS_EXIT_STATUS = 157

    class RebaseTimeout < Timeout
    end

    rpc_writer :rebase_tmp_objdir_experiment
    def rebase_tmp_objdir_experiment(commit_oid, upstream_commit_oid, committer, options = {})
      options = options.merge(dogstats: true)
      options[:use_tmp_objdir_mode] = "migrate-on-success" if options[:use_tmp_objdir_mode].nil?

      result = self.rebase(commit_oid, upstream_commit_oid, committer, options)
      [result, options[:dogstats]]
    end

    rpc_writer :rebase
    def rebase(commit_oid, upstream_commit_oid, committer, options = {})
      tmpdir = create_custom_tmpdir(self.path, "objects/tmp_objdir-rebase-")

      env = {}
      env["GIT_COMMITTER_NAME"] = committer["name"]
      env["GIT_COMMITTER_EMAIL"] = committer["email"]
      env["GIT_COMMITTER_DATE"] = committer["time"]

      extra_git_options = []
      extra_git_options.push("-c", "pack.tmpObjDir.showStats=true") if options[:dogstats]

      too_many_commits = 100
      extra_options = []
      extra_options.push("--use-tmp-objdir=#{options[:use_tmp_objdir_mode]}") if options[:use_tmp_objdir_mode]
      extra_options.push("--tmp-objdir-location=#{tmpdir}")
      extra_options.push("--short-circuit-up-to-date") if options[:up_to_date_short_circuit]
      extra_options.push("--short-circuit-bloated-rebases=#{too_many_commits}") if options[:short_circuit_bloated_rebases]

      diff_algorithm = options[:use_histogram_diff] ? [] : ["--diff-algorithm=default"]
      result = spawn_git(
        "replay", [
          "--legacy-commit-order", # Switch to `true` after the libgit2/replay Scientist experiment
          "--no-conflict-on-mode-change", # Switch to `true` after the libgit2/replay Scientist experiment
          "--show-oid-mappings-only",
          "--linearize",
          "--skip-empty-commits",
          *diff_algorithm,
          "--onto",
          upstream_commit_oid,
          *extra_options,
          "#{upstream_commit_oid}..#{commit_oid}"
        ],
        nil,
        env,
        nil,
        options[:timeout],
        [
          "-c", "merge.directoryrenames=false", # Switch to `true` after the libgit2/replay Scientist experiment
          "-c", "rerere.enabled=false",
          *extra_git_options,
        ]
      )

      if options[:dogstats]
        options[:dogstats] = []
        stderr = result["err"].force_encoding("UTF-8")
        tags = { tags: [result["ok"] ? "status:success" : "status:failure"] }
        before = stderr.match(/before: loose objects: count = (\d+), total size = (\d+); packfiles: count = (\d+), total size = (\d+)/)
        after = stderr.match(/after: loose objects: count = (\d+), total size = (\d+); packfiles: count = (\d+), total size = (\d+)/)
        if before.nil? || after.nil?
          options[:dogstats].push(["rebase.dogstats.failure", 1, tags])
        else
          looseCount = Integer(after[1])
          options[:dogstats].push(["rebase.loose_objects_count", looseCount, tags])
          options[:dogstats].push(["rebase.loose_objects_count_delta", looseCount - Integer(before[1]), tags])
          looseSize = Integer(after[2])
          options[:dogstats].push(["rebase.loose_objects_size", looseSize, tags])
          options[:dogstats].push(["rebase.loose_objects_size_delta", looseSize - Integer(before[2]), tags])
          packCount = Integer(after[3])
          options[:dogstats].push(["rebase.packfiles_count", packCount, tags])
          options[:dogstats].push(["rebase.packfiles_count_delta", packCount - Integer(before[3]), tags])
          packSize = Integer(after[4])
          options[:dogstats].push(["rebase.packfiles_size", packSize, tags])
          options[:dogstats].push(["rebase.packfiles_size_delta", packSize - Integer(before[4]), tags])
        end
      end

      if result["ok"]
        if result["out"].empty?
          # no output means nothing needed to be rebased, output is "onto"
          output = upstream_commit_oid
        else
          # Ideally, we would detect the line with the `commit_oid` mapping here, i.e.
          # `result["out"].split("\n").detect{|line| line.starts_with?(commit_oid)}`
          # However, `commit_oid` might point at a merge commit that is skipped during the
          # rebase...
          last_line = result["out"].split("\n").last
          output = last_line.split[1].force_encoding("UTF-8")
        end
        ensure_valid_full_oid(output)
        output
      else
        raise RebaseTimeout if result["err"] =~ /(^|\n)fatal: Too many objects/
        raise GitRPC::CommandFailed.new(result) if result["status"] != HAS_CONFLICTS_EXIT_STATUS && result["status"] != TOO_MANY_COMMITS_EXIT_STATUS
        nil
      end
    rescue GitRPC::Timeout
      fail RebaseTimeout
    ensure
      FileUtils.rm_rf(tmpdir) if tmpdir && File.exist?(tmpdir)
    end
  end
end
