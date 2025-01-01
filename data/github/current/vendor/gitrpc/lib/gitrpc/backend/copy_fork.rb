# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    rpc_writer :estimate_copy_fork
    def estimate_copy_fork(repositories)
      res = spawn_git("copy-fork", ["--estimate-size"] + repositories)
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"].to_i
    end

    rpc_writer :prepare_copy_fork
    def prepare_copy_fork(source_network_url, repositories)
      repos = Array(repositories)
      if repos.empty?
        raise ArgumentError, "prepare_copy_fork requires at least one repository to copy"
      end

      res = spawn_git("copy-fork", ["--prepare", source_network_url] + repos)
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      nil
    end

    rpc_writer :copy_fork
    def copy_fork(source_network_url, repository)
      res = spawn_git("copy-fork", [source_network_url, repository])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      nil
    end

    rpc_writer :unknown_files
    def unknown_files
      res = spawn_git("copy-fork", ["--list-unknown-files"])
      return nil if res["ok"]

      status = res["status"]
      out = res["out"]
      err = res["err"]
      "Command failed [#{status}]: #{out}\n#{err}\n"
    end
  end
end
