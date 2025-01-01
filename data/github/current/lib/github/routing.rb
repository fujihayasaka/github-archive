# typed: false
# frozen_string_literal: true
require "github/config/active_record"
require "github/routing/hash"

module GitHub
  # Low level Git repository routing location methods.
  #
  # The lookup_XXX methods are designed for use in environments where the full
  # Rails environment is not available and should not be used when the normal
  # set of models are available.
  module Routing
    extend self

    # Exception raised when a route
    class NoSuchRoute < StandardError
    end

    DPAGES_PARTITIONS_COUNT = 8

    # Look up a repository, gist, or wiki routing location by nwo path ("user/repo").
    # Supports "gist/id" and "user/repo.wiki" style paths.
    #
    # nwo - A "user/repo" path.
    #
    # Returns a [hostname, path] array.
    def lookup_route(nwo)
      owner, name = nwo.split("/", 2)

      case
      when owner == "gist" # gist/:repo_name
        lookup_gist_route(name)
      when owner == "network" # network/:network_id
        lookup_network_route(name.to_i)
      when name.nil? # :repo_name
        lookup_gist_route(owner)
      else # :owner/:name
        lookup_repository_route(owner, name)
      end
    end

    # Look up a network route by network id.
    #
    # Returns [hostname, path] array, where path is the path to the network.git
    # on the fileserver.
    def lookup_network_route(network_id)
      host = GitHub::DGit::Routing.preferred_reader_for_network(network_id)
      raise NoSuchRoute, "No route found for network/#{network_id}" unless host

      network_path = nw_storage_path(network_id: network_id)

      [host, "#{network_path}/network.git"]
    end

    # Look up a repository routing location by owner and repository name.
    #
    # Returns [hostname, path] array.
    def lookup_repository_route(owner, name)
      if name.end_with?(".wiki")
        wiki_suffix = ".wiki"
        name = name.chomp(".wiki")
      end

      owner_id = ApplicationRecord::Domain::Users.connection.select_value(Arel.sql(<<~SQL, owner: owner))
        SELECT users.id
        FROM users
        WHERE users.login = :owner
      SQL
      raise NoSuchRoute, "No user found with login #{owner}" unless owner_id

      query = Arel.sql(<<-SQL, owner_id: owner_id, name: name)
        SELECT repositories.id AS repository_id,
               repository_networks.id AS network_id
        FROM repository_networks
        INNER JOIN repositories
          ON repositories.source_id = repository_networks.id
        WHERE repositories.owner_id = :owner_id
          AND repositories.name = :name
          AND repositories.active = 1
      SQL

      repo_id, network_id = ApplicationRecord::Domain::Repositories.connection.select_rows(query).first
      raise NoSuchRoute, "No repository found for #{owner} with given repository name (redacted)" unless repo_id

      host = GitHub::DGit::Routing.preferred_reader_for_repo(repo_id)
      raise NoSuchRoute, "No host route found for repository id #{repo_id}" unless host

      network_path = nw_storage_path(network_id: network_id)

      [host, "#{network_path}/#{repo_id}#{wiki_suffix}.git"]
    end

    # Look up a gist routing location by owner and repository name.
    #
    # Returns [hostname, path] array.
    def lookup_gist_route(repo_name)
      begin
        gist_id, repo_name = GitHub::DGit::Routing::lookup_gist_by_reponame(repo_name)
      rescue GitHub::DGit::RepoNotFound
        raise NoSuchRoute, "No gist route found for given repository name (redacted)"
      end

      host = GitHub::DGit::Routing::hosts_for_gist(gist_id).first
      raise NoSuchRoute, "No host route found for gist id #{gist_id}" unless host

      [host, gist_storage_path(repo_name: repo_name)]
    end

    # Look up a gist id based on repo name. Used for backup imports.
    #
    # Returns id.
    def lookup_gist_id(repo_name)
      sql = Arel.sql <<-SQL, repo_name: repo_name
        SELECT id FROM gists
        WHERE repo_name = :repo_name
      SQL

      id, = ApplicationRecord::Domain::Gists.connection.select_rows(sql).first
      raise NoSuchRoute, "No gist found for given repository name (redacted)" unless id

      id
    end

    def nw_storage_path(network_id:)
      path_hash = storage_hash(network_id)

      File.join(
        GitHub.repository_root,
        path_hash[0],
        "nw",
        path_hash[0, 2],
        path_hash[2, 2],
        path_hash[4, 2],
        network_id.to_s,
      )
    end

    def gist_storage_path(repo_name:)
      path_hash = storage_hash(repo_name)
      File.join(GitHub.repository_root, path_hash[0], path_hash[0, 2], path_hash[2, 2], path_hash[4, 2], "gist/#{repo_name}.git")
    end

    def dpages_storage_path(page_id, revision:)
      path_hash = storage_hash(page_id)
      partition = dpages_partition(page_id)

      File.join(GitHub.pages_dir, partition, path_hash[0, 2], path_hash[2, 2], path_hash[4, 2], page_id.to_s, revision)
    end

    def dpages_partition(page_id)
      (storage_hash(page_id)[0].chr.hex % DPAGES_PARTITIONS_COUNT).to_s
    end

    # Whether the path is a plausible dpages storage path. Sanity check.
    #
    # Example:
    #   dpages_storage_path?("/data/pages") # => false
    #   dpages_storage_path?("/data/pages/5/5e/19/28/563390/legacy") # => true
    #   dpages_storage_path?(
    #     "/data/pages/5/5e/19/28/563390/d15fcc154823e6670e393ef85810c1a0312c373c"
    #   ) # => true
    def dpages_storage_path?(path)
      path.sub(GitHub.pages_dir, "").split("/").size == 7
    end

    private

    def storage_hash(network_id)
      GitHub::Routing::Hash.route_hash(network_id.to_s)
    end
  end
end
