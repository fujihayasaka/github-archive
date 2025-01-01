# typed: true
# frozen_string_literal: true

module GitHub
  module Spokes
    class Client
      # Spokes client implementation that uses local DGit and ActiveRecord.
      # This is generally the "legacy" implementation of a spokes operation.
      class DGit
        def client_name
          "dgit"
        end

        def available?(repository)
          repository.present? && \
              repository.route && \
              repository.shard_path && \
              GitHub::DGit::Util::is_online?(repository.route)
        rescue GitHub::DGit::UnroutedError
          false
        end

        def pick_fileservers
          # Since we use `dgit_default_copies` here, read-heavy networks are not properly supported!
          fileservers = GitHub::DGit::pick_fileservers(GitHub.dgit_default_copies, [])

          # Deal with hosts.empty? now, but defer checking if hosts.length < quorum
          # until we know if the rpc op is a read or a write.
          raise GitHub::DGit::UnroutedError, "no hosts found for placement" if fileservers.empty?

          unless GitHub.dgit_non_voting_copies.nil?
            non_voting_fileservers = GitHub::DGit.pick_non_voting_fileservers(GitHub.dgit_non_voting_copies, [])
            Failbot.push delegate_non_voting_hosts: non_voting_fileservers.map(&:name).inspect
            fileservers += non_voting_fileservers
          end

          fileservers
        end

        def all_replicas(network_id, repo_id, repo_type)
          case repo_type
          when GitHub::DGit::RepoType::REPO, GitHub::DGit::RepoType::WIKI
            db = GitHub::DGit::DB.for_network_id(network_id)

            GitHub::DGit::Routing.all_repo_replicas_in_db(network_id, repo_id, repo_type, db)
          when GitHub::DGit::RepoType::GIST
            GitHub::DGit::Routing.all_gist_replicas_for_many([repo_id])[repo_id]
          when GitHub::DGit::RepoType::NETWORK
            GitHub::DGit::Routing.all_network_replicas_for_many([network_id])[network_id]
          end
        end

        def write_nwo_file(repository, nwo)
          repository.update_nwo_file(nwo)
        end
      end
    end
  end
end
