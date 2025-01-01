# typed: true
# frozen_string_literal: true

# The Repository::StorageAdapter module includes a couple adapter classes for
# dealing with archiving and restoring git repositories because of differences
# on github.com (remote backup shards) and enterprise (local filesystem).
#
# The StorageAdapter module is mixed into the Repository
# class and exposes a storage_adapter method for performing
# operations. Usage is something like:
#
#   repository = Repository.find(1234)
#   repository.storage_adapter.restore
#   repository.storage_adapter.purge
#
# Overview of behavioral differences between github.com and GHE for each stage
# of archive/restore/purge:
#
#  - archive: On github.com repositories removed from their primary disk
#    location. On GHE, repositories are left in place on disk.
#  - restore: On github.com, repositories are fetched from gitbackups. On GHE,
#    the operation is a no-op because repositories were never removed from disk
#    during archive.
#  - purge: On github.com, repositories are permanently deleted from the
#    gitbackups system. On GHE, repositories are permanently deleted from their
#    primary location.
#
module Repository::StorageAdapter
  extend T::Helpers

  requires_ancestor { Repository }

  # Create a storage adapter instance to perform archive, restore, or purge
  # operations on the underlying repository.
  #
  # Returns an instance of one of the storage adapter classes below.
  def storage_adapter
    storage_adapter_class.new(self)
  end

  # Adapter class used for storage operations in the current environment.
  def storage_adapter_class
    if GitHub.enterprise? || Rails.env.development?
      LocalFilesystemStorageAdapter
    else
      RemoteShardedStorageAdapter
    end
  end

  def initialize_replicas_from_network
    repo_network = T.must(network)
    if repo_network.needs_dgit_initialization_after_commit?
      repo_network.initialize_placeholder_network_replicas
    end

    GitHub::DGit::Maintenance.insert_placeholder_replicas_and_checksums(
      GitHub::DGit::RepoType::REPO, self.id, repo_network.id)

    # We've changed the routes in the database so invalidate our cached values
    dgit_reload_routes!
  end

  # Used by the NetworkMaintenance job to "heal" missing repositories when
  # detected. If a repository is found to not exist on disk, it's initialized as
  # an empty repository.
  def setup_missing_git_repository
    return if exists_on_disk?
    create_git_repository_on_disk
    enable_or_disable_shared_storage
  end

  # Create the git repository on disk.
  #
  # default_branch - Optional: String name of a default branch to pass on to the
  #                  repository creator. If specified, overrides the
  #                  owner-specified default branch of a new repo.
  #
  # Returns a Hash mapping { host => checksum, :repo => expected_checksum } when
  # successful, or an empty Hash when no replicas available.
  def create_git_repository_on_disk(default_branch: nil)
    options = {
      public: public?,
      template: GitHub.repository_template,
      nwo: name_with_owner
    }

    repo_owner = owner

    if default_branch
      options[:default_branch] = default_branch
    elsif repo_owner && repo_owner.custom_default_new_repo_branch_name?
      options[:default_branch] = owner_default_new_repo_branch
    end

    GitHub::RepoCreator.new(self, options).init
    GitHub::DGit::Maintenance.recompute_checksums(self, :vote, force_dgit_init: true)
  end

  # Determine if shared storage / network alternates are currently enabled
  # for this repository at the git repo level using the git-nw-linked command.
  #
  # Returns true if network alternates are enabled, false otherwise.
  def shared_storage_enabled?
    rpc.nw_linked?
  end

  # Check if this repository can use alternates to share network.git
  # objects. All repos may use alternates except for private repos that
  # belong to a network with at least one public repo.
  #
  # Returns true if network alternates are allowed for this repository.
  def shared_storage_allowed?
    public? || !T.must(network).repositories.exists?(public: true)
  end

  # Enable or disable shared storage / network alternates for this repository
  # based on whether shared storage is enabled globally and allowed for this
  # repository.
  #
  # Returns true when shared storage is enabled, false when disabled, and nil
  # when no change was made.
  def enable_or_disable_shared_storage
    return if !exists_on_disk?

    enabled = shared_storage_enabled?
    if enabled && !shared_storage_allowed?
      disable_shared_storage
      false
    elsif !enabled && shared_storage_allowed?
      enable_shared_storage
      true
    end
  end

  # Enable network alternates for this repository using the git-nw-link
  # command. All objects are shared with other repositories linked with this
  # network.
  #
  # Note: This is a potentially long-running operation and should not be run
  # from within web requests or other time sensitive environments.
  #
  # Returns nothing.
  # Raises an exception when the repository could not be linked with the
  # network.
  def enable_shared_storage
    if Rails.env.development? && path == "github/github.git"
      # guard against enabling alternates in special development github repo
      return
    elsif !shared_storage_allowed?
      # fail fast if we're not allowed to enable network alternates
      fail "network alternates can't be enabled for this repo"
    end

    rpc.nw_link
  end

  # Turn off network alternates for this repository using the git-nw-unlink
  # command. All shared objects are pull into this repository's pack files.
  # Once complete, the repository is self contained and can be moved to
  # another location.
  #
  # Note: This is a potentially long-running operation and should not be run
  # from within web requests or other time sensitive environments.
  #
  # Returns nothing.
  # Raises an exception when the repository could not be unlinked.
  def disable_shared_storage
    GitHub.dogstats.increment "repository", tags: ["action:disable_shared_storage"]
    rpc.fs_delete("objects/info/http-alternates")
    rpc.nw_unlink
  end

  def dgit_repo_type
    if T.must(name).end_with?(".wiki")
      # There are two legacy repositories whose names end in ".wiki".
      # We treat them like wikis.
      GitHub::DGit::RepoType::WIKI
    else
      GitHub::DGit::RepoType::REPO
    end
  end

  # Remove the repository from disk after unlinking from network.git. This
  # records an entry in the git replication log under GHE.
  #
  # Returns nothing.
  def remove_from_disk
    return unless exists_on_disk?

    rpc = removal_rpc
    rpc.nw_rm

  rescue GitRPC::Protocol::DGit::ResponseError, GitHub::DGit::UnroutedError => e
    GitHub.logger.error(
      :exception => e,
      "code.namespace" => self.class.name,
      "code.function" => __method__
    )
    Failbot.report!(e, "code.function": "Repository::StorageAdapter#remove_from_disk (continue_removal)")
  end

  # Remove the wiki repository from disk. This records an entry in the git
  # replication log under GHE.
  def remove_wiki_from_disk
    begin
      wiki_rpc = GitRPC.new("dgit:/", delegate: GitHub::DGit::Delegate::WikiRemoval.new(network&.id, id, wiki_shard_path, nil))
      return unless wiki_rpc.exist?
    rescue GitHub::DGit::UnroutedError
      return  # no wiki = nothing to remove
    end

    wiki_rpc.fs_delete(".")

  rescue GitRPC::Protocol::DGit::ResponseError => e
    GitHub.logger.error(
      :exception => e,
      "code.namespace" => self.class.name,
      "code.function" => __method__
    )
    Failbot.report!(e, "code.function": "Repository::StorageAdapter#remove_wiki_from_disk (continue_removal)")
  end

  # The RemoteSharded storage adapter is used on github.com and in development
  # in dotcom mode.
  class RemoteShardedStorageAdapter
    # a custom exception class that also carries additonal data from the rpc
    # call
    class MirrorError < StandardError
      attr_reader :data

      def initialize(data)
        @data = data
      end
    end

    class RestoreError < StandardError
      attr_reader :data

      def initialize(data)
        @data = data
      end
    end

    class RepositoryNotFound < StandardError; end

    attr_accessor :repository

    def initialize(repository)
      @repository = repository
    end

    # Called after a repository record is restored in the database but before a
    # new empty git repository is initialized. This method should restore the
    # repository on disk if possible.
    def restore
      gitbackups_restore("repository", repository)
      restore_wiki
    end

    # Restore this repository's wiki from backups if it exists.
    def restore_wiki
      return unless RepositoryWiki.find_by(repository:)
      gitbackups_restore("wiki", repository.unsullied_wiki)
    end

    # Remove the repository from archive storage.
    #
    def purge
      repository.unsullied_wiki.delete_backup
      repository.delete_backup
    rescue Faraday::ConnectionFailed
      # eat and ignore this exception. This happens during tests because gitbackupsd isn't running
    end

    def gitbackups_restore(type, target)
      # TODO: This should be part of GitBackups repository mixin
      destpath = target.original_shard_path
      parent_rpc = target.network.parent_rpc
      parent_rpc.create_network_dir

      begin
        result = parent_rpc.gitbackups_restore(target.repository_spec, File.dirname(destpath))
        raise RepositoryNotFound if result == :not_found
        raise RestoreError.new({ out: result[0], err: result[1] }) if result.is_a?(Array)
      rescue GitRPC::CommandFailed => e
        raise RestoreError.new(e), "#{type} restore failed"
      end

      fixup_dgit(target)
    end

    def fixup_dgit(target)
      if target.is_a?(GitHub::Unsullied::Wiki)
        if GitHub::DGit::Routing.all_repo_replicas(repository.id, true).size == 0
          target.initialize_replicas_from_network
        end
        GitHub::DGit::Maintenance.recompute_checksums(target.repository, :vote, is_wiki: true)
      else
        if GitHub::DGit::Routing.all_repo_replicas(repository.id).size == 0
          target.initialize_replicas_from_network
        end
        GitHub::DGit::Maintenance.recompute_checksums(target, :vote)
      end
    end

    def repo_backup_location
      "#{repository.backup_shard}.backup.github.com:#{repository.original_shard_path}"
    end

    def wiki_backup_location
      "#{repository.backup_shard}.backup.github.com:#{repository.unsullied_wiki.shard_path}"
    end
  end

  # The LocalFilesystem adapter is used under Enterprise and in development in
  # enterprise mode. Git repositories are moved to a special location on the
  # same partition as active repository storage.
  class LocalFilesystemStorageAdapter
    attr_accessor :repository

    def initialize(repository)
      @repository = repository
    end

    # Called after a repository record is restored in the database but before a
    # new empty git repository is initialized. Moves the repository from the backup
    # location to its normal location.
    def restore
    end

    # Permanently remove the repository and wiki repository from disk.
    def purge
      repository.remove_from_disk
      repository.remove_wiki_from_disk
    rescue GitHub::DGit::UnroutedError
      # This is ok, as long as they're gone. This can happen if something failed
      # part-way through.
    end
  end
end
