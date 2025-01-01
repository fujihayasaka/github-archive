# typed: false
# frozen_string_literal: true

# A handful of utility functions for the scripts that import repositories into Spokes

require "github/background_child"
require "github/config/mysql"
require "github/config/gitrpc"
require "github/dgit/repo_types"
require "github/dgit/states"
require "github/dgit/routing"
require "github/dgit/enterprise"
require "github/dgit/constants"
require "application_record"
require "gitrpc"
require "time"

module GitHub
  class DGit
    class Import
      MAX_SQL_ROWS = 100

      # Call `git dgit-state init` using the given RPC handle and then
      # return the result of GitRPC::Client.read_dgit_checksum. If
      # initialization fails or no valid checksum can be obtained,
      # logs an error and returns nil.
      def self.dgit_state_init(logger, desc, rpc)
        begin
          init_out = rpc.dgit_state_init(DGit::DGIT_CURRENT_CHECKSUM_VERSION)
        rescue GitRPC::DGitStateInitError, GitRPC::InvalidRepository => e
          logger.info "#{desc} could not initialize DGit state: #{e}"
          return nil
        end

        if init_out !~ /^(\d+:)?[0-9a-f]{40}$/
          logger.info "#{desc} for repo ID #{repo_id} on #{host} initialized a bogus checksum: #{init_out.inspect}"
          return nil
        end

        init_out
      end

      # Call `git dgit-state init` in each repo, on each host.  For normal
      # repositories this includes all forks and wikis, if present.
      # Returns a hash keyed by GitHub::DGit::RepoTypes with checksum values.
      # Aborts if any repo initialization produces a mismatched checksum.
      def self.git_dgit_state_init(logger, source_host, hosts, repo_type, id, shard_path, include_archived: false, include_deleted: false)
        raise "`include_archived` is an enterprise-only option" if include_archived && !GitHub.enterprise?
        case repo_type
        when GitHub::DGit::RepoType::REPO
          repo_git_dgit_state_init(logger, source_host, hosts, id, shard_path, include_archived, include_deleted)
        when GitHub::DGit::RepoType::GIST
          gist_git_dgit_state_init(logger, source_host, hosts, id, shard_path)
        else
          desc = GitHub::DGit::RepoType::REPO_TYPES[repo_type]
          raise StandardError, "unhandled repo_type: #{repo_type} #{desc}"
        end
      end

      # Call `git dgit-state init` in each fork, on each host.
      # Returns two hashes, { repo_id => checksum }, { wiki_id => checksum }.
      # Aborts if any of the forks produces mismatched checksums.
      def self.repo_git_dgit_state_init(logger, source_host, hosts, network_id, shard_path, include_archived, include_deleted)
        repo_result = {}
        wiki_result = {}
        logger.info "Initializing DGit checksums"
        forks = GitHub::DGit::Util.repo_ids_for(network_id, include_deleted: include_deleted, include_archived: include_archived)

        forks.each_with_index do |repo_id, idx|
          logger.info "[#{idx + 1}/#{forks.size}] Checksum for #{repo_id}" if (idx + 1) % 100 == 0
          repo_sums = []
          wiki_sums = []
          hosts.each do |host|
            premove = ".premove" unless GitHub::AppEnvironment.development? || GitHub.enterprise?
            premove = "" if host == source_host

            wiki_path = "#{shard_path}#{premove}/#{repo_id}.wiki.git"
            wiki_rpc = GitHub::DGit::rpc_for_host_path(host, wiki_path)

            fork_path = "#{shard_path}#{premove}/#{repo_id}.git"
            fork_rpc = GitHub::DGit::rpc_for_host_path(host, fork_path)

            [
              ["Wiki", wiki_rpc, false, wiki_sums],
              ["Repo", fork_rpc,  true, repo_sums],
            ].each do |desc, rpc, must_exist, checksum_results|
              if !must_exist && !rpc.exist?
                checksum_results << nil
                next
              end

              result = dgit_state_init(logger, "#{desc} for repo ID #{repo_id} on host #{host}", rpc)
              return if result.nil?
              checksum_results << result
            end
          end

          [
            ["Wiki", wiki_sums],
            ["Repo", repo_sums],
          ].each do |desc, checksum_results|
            if checksum_results.uniq.length != 1
              logger.info "#{desc} #{repo_id} produced mismatched checksums: #{checksum_results.inspect}"
              return
            end
          end

          repo_result[repo_id] = repo_sums.first
          wiki_result[repo_id] = wiki_sums.first
        end

        {
          GitHub::DGit::RepoType::REPO => repo_result,
          GitHub::DGit::RepoType::WIKI => wiki_result,
        }
      end

      # Call `git dgit-state init` in each gist replica, on each host.
      # Returns a string checksum.
      # Aborts if any of the replicas produces mismatched checksums.
      def self.gist_git_dgit_state_init(logger, source_host, hosts, gist_id, shard_path)
        result = {}
        checksum_results = []

        hosts.each do |host|
          premove = ".premove" unless GitHub::AppEnvironment.development? || GitHub.enterprise?
          premove = "" if host == source_host
          gist_path = "#{shard_path}#{premove}"
          gist_rpc = GitHub::DGit::rpc_for_host_path(host, gist_path)

          result = dgit_state_init(logger, "Gist #{gist_id} on host #{host}", gist_rpc)
          return if result.nil?
          checksum_results << result
        end

        if checksum_results.uniq.length != 1
          logger.info "Gist #{gist_id} produced mismatched checksums: #{checksum_results.inspect}"
          return
        end

        { GitHub::DGit::RepoType::GIST => checksum_results.first }
      end

      def self.set_moving(logger, network_id, value)
        logger.debug "marking network #{network_id} as moving=#{value}"
        sql = Arel.sql(<<-SQL, network_id: network_id, moving: value)
          UPDATE repository_networks SET moving=:moving WHERE id=:network_id
        SQL
        ApplicationRecord::Domain::Repositories.connection.update(sql)
      end

      # Spawn several background children, log their results, and return
      # handles to them.
      #   - logger: where to log the output
      #   - arr: an array of keys
      # Block:
      #   code to map each key to a command to run
      # Returns:
      #   a hash of { key => child, key => child, ... }
      # Example:
      #   kids = parallelize(logger, hosts) { |h| "ssh #{h} echo hi" }
      #   raise "oops" if kids.find { |h, x| x.status.exitstatus != 0 }
      def self.parallelize(logger, arr)
        kids = Hash[arr.map do |key|
          cmd = yield key
          kid = GitHub::BackgroundChild.new(*cmd)
          [key, kid]
        end]

        GitHub::BackgroundChild.group_drain(kids.values)

        kids.each do |h, kid|
          if kid.status.exitstatus != 0
            logger.info "#{h} ended with status #{kid.status.exitstatus}"
            logger.info "#{h} cmd:\n#{kid.cmd}"
            logger.info "#{h} output:\n#{kid.out}" if !kid.out.empty?
            logger.info "#{h} error:\n#{kid.err}" if !kid.err.empty?
          else
            logger.debug "#{h} ended with status #{kid.status.exitstatus}"
            logger.debug "#{h} cmd:\n#{kid.cmd}"
            logger.debug "#{h} output:\n#{kid.out}" if !kid.out.empty?
            logger.debug "#{h} error:\n#{kid.err}" if !kid.err.empty?
          end
        end

        kids
      end

    end # Import
  end # DGit
end # GitHub
