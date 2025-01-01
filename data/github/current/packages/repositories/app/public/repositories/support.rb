# typed: strict
# frozen_string_literal: true

# This class is intended to help the Customer Support team fix commonly found problems with repositories
# If you find yourself giving a ruby script to the Support team to fix a problem, it should probably
# be codified in here!
module Repositories
  class Support
    sig { returns(T::Array[T.untyped]) }
    def self.find_broken_repos
      broken = []

      if enumerator = RepositoryNetwork.in_batches(of: 100)
        enumerator.each do |batch|
          batch.each do |network|
            network.active_and_deleted_repositories.each do |repo|
              unless repo.exists_on_disk?
                broken << { id: repo.id, network_id: repo.network_id, active: repo.active?, name: repo.name_with_display_owner }
              end
            end
          end
        end
      end
      broken
    end

    sig { void }
    def self.delete_orphaned_networks
      if enumerator = RepositoryNetwork.in_batches(of: 100)
        enumerator.each do |batch|
          batch.each do |network|
            if network.active_and_deleted_repositories.count == 0
              GitHub.logger.info("deleting orphaned network #{network.id}")
              network.destroy
            end
          end
        end
      end
    end

    # id: network id
    # returns true if errors were found, false otherwise
    sig do
      params(id: Integer).returns(T::Boolean)
    end
    def self.fix_network(id:)
      network = RepositoryNetwork.find(id)
      found_errors = false

      # if this network has no repositories, then delete it
      if network.active_and_deleted_repositories.count == 0
        GitHub.logger.info("network #{network.id} has no repos. Destroying the network.")
        network.destroy
        return true
      end

      # is the root missing?
      if network.root.nil?
        found_errors = true
        old_root_id = network.root_id
        GitHub.logger.info("network root #{old_root_id} does not exist.")
        pick_new_root(network)
      end

      # is the root in a foreign network?
      if network.root.source_id != id
        GitHub.logger.info("the network root #{network.root.source_id} belongs to a different network!")
        found_errors = true
        pick_new_root(network)
      end

      # are there circular references or missing parents?
      if enumerator = network.reload.active_and_deleted_repositories.order(id: :asc).in_batches(of: 100)
        enumerator.each do |batch|
          batch.each do |repo|
            found_errors = true if validate_ancestry(repo, network)
          end
        end
      end

      # nothing to do here
      GitHub.logger.info("network #{id} looks good!") if !found_errors
      found_errors
    end

    sig do
      params(repo: Repository, network: RepositoryNetwork).returns(T::Boolean)
    end
    def self.validate_ancestry(repo, network)
      return false if T.must(repo.network).id != network.id
      root = T.must(network.root)

      children = {}
      loop do
        return false if repo.id == root.id

        if repo.parent.nil?
          GitHub.logger.info("fork #{repo.id} has nil parent")
          reparent_fork(repo, root)
          return true
        elsif children[repo.id]
          GitHub.logger.info("fork #{repo.id} has circular reference")
          reparent_fork(repo, root)
          return true
        elsif T.cast(T.must(repo.parent), Repository).source_id != network.id # rubocop:todo GitHub/AvoidCast
          GitHub.logger.info("fork #{repo.id} has parent in different network")
          reparent_fork(repo, root)
          return true
        end

        # loop back and inspect the fork's parent
        children[repo.id] = repo.parent&.id
        repo = T.cast(repo.reload.parent, Repository) # rubocop:todo GitHub/AvoidCast
      end
    end

    sig do
      params(repo: Repository, parent: Repository).void
    end
    def self.reparent_fork(repo, parent)
      return if repo.id == parent.id
      GitHub.logger.info("fork #{repo.id} new parent is #{parent.id} #{parent.name_with_display_owner}")

      repo.update_column(:parent_id, parent.id)
      parent.update_organization
    end

    sig do
      params(network: RepositoryNetwork).void
    end
    def self.pick_new_root(network)
      # prefer an active repo for the root, but pick a deleted repo if necessary
      new_root = network.repositories.order(id: :asc).first || network.deleted_repositories.order(id: :asc).first

      GitHub.logger.info("picked #{new_root.id} #{new_root.name_with_display_owner} to be the new network root")
      network.make_root!(new_root)
    end
  end
end
