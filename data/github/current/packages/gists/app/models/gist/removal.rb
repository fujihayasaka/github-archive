# typed: false
# frozen_string_literal: true

require "github/dgit/enterprise"
require "github/git_repository/maintenance_client"

module Gist::Removal
  extend ActiveSupport::Concern

  included do
    scope :deleted, -> { where(delete_flag: true) }
    scope :active,   -> { where(delete_flag: false) }
    scope :deleted_before,  -> (date, batch_size) { deleted.where("updated_at < ?", date).limit(batch_size) }
  end

  module ClassMethods
    # Public: Restores a gist and its dependents from the archive table.
    # If the gist has not been archived, just returns that gist.
    #
    # When restoring the gist some cleanup actions are performed:
    # - Unhides the gist so that it may be displayed.
    #
    # id - Integer ID of the gist to restore
    #
    # Returns the restored Gist.
    def restore(id)
      if existing_gist = find_by(id: id)
        if existing_gist.delete_flag
          existing_gist.unhide
        end
        existing_gist
      end
    end
  end

  # purge a soft-deleted gist
  def purge
    raise Gist::Removal::GistPurgeError, "Gist is not deleted" unless delete_flag

    rpc.fs_delete(".") if exists_on_disk?

    # We no longer create backups, so it would be great if we no longer had to delete them either.
    if !GitHub.enterprise?
      begin
        delete_backup
      rescue GitBackups::DeleteError, Faraday::ConnectionFailed => e
        GitHub.logger.error(
          "Soft deleted purge failed",
          {
            :exception => e,
            "code.namespace" => "Gist::Removal",
            "code.function" => "purge",
            "gh.spokes.spec" => repository_spec,
          }
        )
      end
    end

    remove_from_disk(self)
    destroy
  end

  class GistPurgeError < StandardError; end
  class GistRestoreError < StandardError; end
  class RepositoryNotFound < StandardError; end

  def restore_to_disk
    restore_from_backup
    unhide
  end

  # restore the gist contents from backup
  def restore_from_backup
    fileservers = fileservers_for_restore
    dest_fs, remaining_fs = fileservers[0], fileservers[1..-1]

    GitHub.logger.info(
      "Restore from backup failed",
      "code.namespace" => "Gist::Removal",
      "code.function" => "restore_from_backup",
      "gh.gist.restore.dest_fs" => dest_fs.name,
      "gh.gist.id" => self.id
    )

    # Enterprise expects the data to have been left on disk.
    restore_to_dgit_from_backup(dest_fs) unless GitHub.enterprise?

    # Create new DB records such that this restored replica can be used to
    # populate other new replicas.
    GitHub::DGit::Maintenance.insert_restore_placeholder_gist_replica_and_checksum(self.id, dest_fs)

    GitHub::DGit::Maintenance.recompute_gist_checksums(self, :vote, fileservers: [dest_fs])

    ctx = GitHub::DGit::Maintenance::GistMaintenanceContext.new
    remaining_fs.each do |fs|
      ctx.enqueue_create_replica(self.id, fs.name)
    end
  end

  def remove(async: true)
    hide
    self
  end

  def remove_from_disk(gist)
    return if GitHub.enterprise?
    return unless gist.exists_on_disk?

    backup_ng! if backups_enabled?
    gist.rpc.fs_delete(".")
  end

  # TODO: Make these private. Public interface should focus on remove/restore.
  # Public: soft-deletes the gist.
  def hide
    transaction do
      touch_parent
      update!(delete_flag: true)
    end

    instrument :destroy
  end

  def unhide
    transaction do
      touch_parent
      update!(delete_flag: false)
    end
  end

  def active?
    !delete_flag
  end

  def deleted?
    delete_flag
  end

  private

  # Picks fileservers to be the target for restoring
  def fileservers_for_restore
    existing_fileserver = nil

    begin
      new_fileservers = GitHub::Spokes.client.pick_fileservers(actor: user)
    rescue GitHub::DGit::HostSelectionError
      # Be satisified as long as we have *a* fileserver to restore to
      # This is really only something that can happen in enterprise.
      raise Gist::Removal::GistRestoreError, "No available file servers found" unless existing_fileserver
      new_fileservers = []
    end

    if existing_fileserver.nil?
      fileservers = new_fileservers
    else
      needed_copies = new_fileservers.size

      # Enterprise is tricky because we're relying on using a previous
      # replica where we assume the gist will still have data. But we also need
      # a full compliment of replicas. What we don't know is whether the
      # previous replica would have been selected for a brand-new placement.
      new_fileservers.select! do |fs|
        fs.name != existing_fileserver.name
      end

      fileservers = [existing_fileserver] + new_fileservers[0...(needed_copies - 1)]
    end

    fileservers
  end

  def restore_to_dgit_from_backup(dest_fs)
    Failbot.push "gh.gist.repo_name": repo_name,
                 "gh.gist.original_shard_path": original_shard_path,
                 "gh.gist.dest_fs": dest_fs.name

    dest_path = if Rails.env.development? || Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      GitHub::DGit.dev_route(original_shard_path, dest_fs.name)
    else
      original_shard_path
    end

    dest_parent_path = File.dirname(dest_path)
    dest_clone_dir   = File.basename(dest_path)

    Failbot.push "gh.gist.dest_parent_path": dest_parent_path,
                 "gh.gist.dest_clone_dir": dest_clone_dir

    # RPC handle for cloning from the parent directory.
    parent_rpc = dest_fs.build_maint_rpc(File.dirname(original_shard_path))

    #
    # Sanity check: it is assumed that the last 5 directory components leading
    # up to a gist's location will be the same between the parent RPC handle
    # and the original shard path.
    #
    dest_last_five = dest_parent_path.split("/").last(5)
    parent_last_five = parent_rpc.backend.path.split("/").last(5)
    if dest_last_five != parent_last_five
      raise GistRestoreError.new(original_shard_path),
            "failed path check, aborting " \
            "(#{dest_last_five.inspect} != #{parent_last_five.inspect})"
    end

    # Move anything that might be there to a backup directory.  Any
    # exception here is ignored for the case that there are no such
    # contents already there.
    backup_dir = "gist-repair-backup-#{dest_clone_dir}-#{Time.now.to_i}"
    begin
      parent_rpc.fs_move(dest_clone_dir, backup_dir)
    rescue GitRPC::SystemError
    end

    begin
      parent_rpc.ensure_dir(dest_parent_path)
    rescue GitRPC::CommandFailed => e
      raise GistRestoreError, "failed to create directory: #{e}"
    end

    if Rails.env.development? || Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      development_restore(dest_fs)
    else
      restore_from_gitbackups(parent_rpc, dest_parent_path)
    end

    # Sanity check again.
    gist_rpc = dest_fs.build_maint_rpc(original_shard_path)
    unless gist_rpc.exist?
      raise GistRestoreError.new(gist_rpc), "failed after clone, aborting"
    end
  end

  def restore_from_gitbackups(parent_rpc, dest_clone_dir)
    result = parent_rpc.gitbackups_restore(repository_spec, dest_clone_dir)
    raise RepositoryNotFound if result == :not_found
    raise GistRestoreError.new({ out: result[0], err: result[1] }) if result.is_a?(Array)
  rescue GitRPC::CommandFailed => e
    raise GistRestoreError.new(e), "gist restore failed"
  end

  # There is no backup support in development so we just create an empty repository.
  def development_restore(dest_fs)
    maint_client = GitHub::GitRepository::MaintenanceClient.new self, dest_fs.build_maint_rpc(original_shard_path)
    maint_client.rpc.ensure_initialized
  end
end
