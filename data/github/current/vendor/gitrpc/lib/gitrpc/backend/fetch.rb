# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    rpc_writer :fetch
    def fetch(src_path, options = {})
      argv = []
      argv << "--quiet" if options[:quiet]
      argv << "--no-tags" if options[:no_tags]
      argv << "--force" if options[:force]
      argv << "--prune" if options[:prune]
      argv << "--no-recurse-submodules" if options[:no_recurse_submodules]
      argv += ["--", src_path]
      argv << options[:refspec] if options[:refspec]

      env = {}
      env["DGIT_DISABLED"] = "1" if options[:dgit_disabled]
      env["GIT_COMMITTER_DATE"] = options[:committer_date] if options[:committer_date]

      res = spawn_git("fetch", argv, nil, env)
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      {"out" => res["out"], "err" => res["err"]}
    end

    rpc_writer :fetch_commits
    def fetch_commits(repo, commit_oid)
      ensure_valid_full_oid(commit_oid)

      res = spawn_git("fetch-commits", [repo, commit_oid])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      nil
    end

    rpc_writer :nw_clone
    def nw_clone(branch, template, newid, one_branch: false)
      argv = ["--quiet", "--branch=#{branch}", "--template="]
      argv += ["--single-branch", "--no-tags"] if one_branch
      argv += [newid.to_s]

      res = spawn_git("nw-clone", argv, nil)
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      nil
    end

    rpc_writer :bare_clone, no_git_repo: true
    def bare_clone(src, dest)
      res = spawn_git("clone", ["-q", "--bare", "--template=", "--", src, dest])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      nil
    end
  end
end
