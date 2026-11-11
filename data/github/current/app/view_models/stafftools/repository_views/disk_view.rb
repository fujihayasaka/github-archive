# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class DiskView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include Stafftools::StatusChecklist

      attr_reader :repository

      def page_title
        "#{repository.name_with_owner} - Disk"
      end

      def disk_status
        status_li(:error, "Does not exist on disk") unless exists_on_disk?
      end

      def storage_host
        GitHub::DGit::Routing.hosts_for_network(network.id).join(", ")
      end

      def storage_path
        repository.original_shard_path
      end

      def storage_url
        "#{storage_host}:#{storage_path}"
      end

      def shared_storage_enabled?
        network.shared_storage_enabled?
      end

      def shared_storage_path
        network.shared_storage_path
      end

      def is_fscked?
        !fsck_output.blank?
      end

      def fsck_output
        @fsck_output ||= if repository.online?
          fsck_output = repository.fsck
          fsck_output.present? ? fsck_output.dup.force_encoding("utf-8").scrub! : ""
        else
          "repository offline, cannot fsck"
        end
      end

      def fsck_failed?
        is_fscked? && (fsck_output =~ /OK repository passed checks/)
      end

      def exists_on_disk?
        repository.exists_on_disk?
      end

      def can_restore_wiki?
        RepositoryWiki.find_by(repository:) &&
          repository.storage_adapter.respond_to?(:restore_wiki)
      end

      def shard_path
        "#{repository.route}:#{repository.shard_path}"
      end

      def network
        repository.network
      end

      def show_wiki_maintenance?
        !!RepositoryWiki.find_by(repository:)
      end

      def wiki_maintenance_status
        RepositoryWiki.find_by(repository:)&.maintenance_status || "no status recorded"
      end

      def wiki_marked_broken?
        RepositoryWiki.find_by(repository:)&.maintenance_status == "broken"
      end
    end
  end
end
