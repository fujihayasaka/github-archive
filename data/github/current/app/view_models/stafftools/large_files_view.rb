# typed: true
# frozen_string_literal: true

module Stafftools
  class LargeFilesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    module PreviewTogglerHelper
      def can_enable_lfs?
        return false unless GitHub.git_lfs_config_enabled?
        if !git_lfs_configurable.network_root? && git_lfs_configurable.root
          return false unless git_lfs_configurable.root.git_lfs_enabled?
        end
        if git_lfs_configurable.owner
          return false unless T.must(git_lfs_configurable.owner).git_lfs_enabled?
        end
        true
      end

      def git_lfs_button_banner_text
        if !GitHub.git_lfs_config_enabled?
          "Git LFS is globally disabled for this GitHub Enterprise appliance."
        elsif !git_lfs_configurable.network_root? &&
              git_lfs_configurable.root &&
              !git_lfs_configurable.root.git_lfs_enabled?
          "Git LFS is disabled for the root repository in the network."
        elsif git_lfs_configurable.owner &&
              !T.must(git_lfs_configurable.owner).git_lfs_enabled?
          "Git LFS is disabled for the owner of this repository."
        end
      end

      def git_lfs_button_text
        git_lfs_configurable.git_lfs_enabled? ? "Disable" : "Enable"
      end
    end

    include PreviewTogglerHelper

    attr_reader :repository
    attr_reader :oid
    attr_reader :start      # The oid after which the current page shows blobs
    attr_reader :prev       # The oid after which the previous page shows blobs

    def large_files
      @large_files ||= if @oid.present?
        [Media::Blob.fetch(@repository, @oid)].compact
      else
        Media::Blob.page(@repository, oid: @start)
      end
    end

    def destroy_url_for(file)
      if file.archived?
        urls.gh_unarchive_stafftools_repository_large_file_path(@repository, file.id)
      else
        urls.gh_archive_stafftools_repository_large_file_path(@repository, file.id)
      end
    end

    def storage_blob_url_for(file)
      if GitHub.storage_cluster_enabled?
        urls.stafftools_storage_blob_path(file.oid)
      else
        urls.stafftools_asset_path(file.oid)
      end
    end

    def destroy_button_text_for(file)
      file.archived? ? "Restore" : "Delete"
    end

    def large_file_state(blob)
      case blob.state
      when "verified" then "Available"
      when "archived" then "Archived"
      when "deleted" then "Deleted"
      else "Never uploaded successfully"
      end
    end

    def lfs_timeout_choices
      [
        ["5s", 5],
        ["10s", 10],
        ["25s", 25],
        ["Default", 0],
      ]
    end

    def lfs_timeout_text(value)
      return "Default" if value == 0
      "#{value}s"
    end

    def oid?
      @oid.present?
    end

    def paging?
      prev_page? || next_page?
    end

    def start_over?
      !paging? && Media::Blob.in_network?(@repository.network)
    end

    # Is there a previous page of blobs?
    def prev_page?
      @start.present?
    end

    # Is there a next page of blobs?
    def next_page?
      large_files.size >= 50
    end

    def git_lfs_configurable
      @repository
    end

    def after_initialize
      @page = [@page.to_i, 1].min
    end

    def disable_restore_lfs_objects_button?
      Media::Blob.for_repository_network(repository.network).restorable.empty?
    end

    def disable_purge_lfs_objects_button?
      Media::Blob.for_repository_network(repository.network).purgeable.empty?
    end
  end
end
