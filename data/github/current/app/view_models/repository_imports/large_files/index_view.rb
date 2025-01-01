# typed: true
# frozen_string_literal: true

module RepositoryImports
  module LargeFiles
    class IndexView < ::RepositoryImports::ShowView
      attr_reader :page

      delegate :large_files_count, :files, :large_files_size, to: :large_file_details

      # Public: The percentage of large file storage that will be used if the
      # user opts-in.
      #
      # Returns an Integer.
      def percentage_used_with_lfs
        percent = (storage_usage_with_lfs / asset_status.storage_quota).round(2)
        (percent * 100).to_i
      end

      # Public: The total gigabytes of large file storage that will be used
      # if the user opts-in.
      #
      # Returns a Float.
      def storage_usage_with_lfs
        large_files_gigabytes = large_files_size / 1.gigabyte.to_f
        (large_files_gigabytes + asset_status.storage_usage).round(2)
      end

      # Public: The AssetStatus for the user.
      #
      # Returns an Asset::Status.
      def asset_status
        repository.owner.new_or_asset_status
      end

      # Public: The number of large files to show on one page.
      #
      # Returns an Integer.
      def per_page
        50
      end

      # Public: The large file details including total count, total size in
      # bytes, and a list of files (paginated).
      #
      # Returns an RepositorySourceImport::LargeFileDetails.
      def large_file_details
        @large_file_details ||= repository_import.large_file_details({ per_page: per_page, page: page })
      end

      # Public: Does the large file list require pagination?
      #
      # Returns true or false.
      def paginate?
        large_files_count > files.length
      end

      # Public: Is there a page of large files before the current page?
      #
      # Returns true or false.
      def previous_page?
        page > 1
      end

      # Public: The number of the page before the current page.
      #
      # Returns an Integer.
      def previous_page
        page - 1
      end

      # Public: Is there a page of large files after the current page?
      #
      # Returns true or false.
      def next_page?
        (per_page * page) < large_files_count
      end

      # Public: The number of the page after the current page.
      #
      # Returns an Integer.
      def next_page
        page + 1
      end

      # Public: The amount of available large file storage, maxing out at 100%.
      #
      # Returns an Integer.
      def ceiling_percentage
        if asset_status.storage_usage_percentage > 100
          100
        else
          asset_status.storage_usage_percentage
        end
      end
    end
  end
end
