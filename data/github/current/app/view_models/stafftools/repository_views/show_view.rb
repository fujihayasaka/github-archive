# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include Stafftools::Features
      include Stafftools::Sentry
      include Stafftools::StatusChecklist
      include ActionView::Helpers::NumberHelper
      include AuditLogHelper

      KILOBYTE = 1_024

      attr_reader :repository

      def page_title
        "#{repository.name_with_owner} - Overview"
      end

      def db_state
        git_repo_db_state repository
      end

      def billing_state
        return unless repository.private? && GitHub.billing_enabled?

        if repository.disabled?
          status_li(:failed, "Billing status: locked")
        else
          status_li(:ok, "Billing status: ok")
        end
      end

      def git_state
        git_repo_git_state repository
      end

      def fs_state
        git_repo_fs_state repository
      end

      def fork_parent_state
        return unless fork?
        if parent_missing?
          status_li(:error, "Parent repository: missing")

        # support public_push repositories
        elsif GitHub.public_push_enabled? && repository.public_push? && !parent.public_push?
          status_li(:error, "Parent repository: Not `public_push`")
        else
          status_li(:ok, "Parent repository: ok")
        end
      end

      # produce error messages for public_push repos
      def fork_sanity
        return unless GitHub.public_push_enabled? && fork?
        if repository.public_push?
          status_li(:error, "Fork allows public push")
        end
      end

      def disabled_state
        repository_access = repository.access
        if repository_access.disabled?
          status_li(:error, "Disabled: #{repository_access.disabling_reason}")
        end
      end

      def disabled_reason_human
        reason = repository.access.disabling_reason
        case reason
        when "dmca"
          "DMCA"
        when "sensitive_data"
          "Sensitive Data"
        when "size"
          "Size"
        when "tos"
          "ToS"
        when "trademark"
          "Trademark"
        else
          reason
        end
      end

      def backup_state
        git_backup_state repository
      end

      def permissions(repo = repository)
        permissions = []
        db = repo.visibility
        permissions << db
        permissions << "public_push" if GitHub.public_push_enabled? && repo.public_push?
        permissions.join(", ")
      end

      def errored_branch_renames
        repository.branch_renames.errored.latest.limit(10)
      end

      def fork?
        repository.fork?
      end

      def parent
        repository.parent
      end

      def parent_missing?
        repository.fork? && parent.nil?
      end

      def root
        repository.root
      end

      def sentry_link
        sentry_query_link(
          [Stafftools::Sentry::DOTCOM_PROJECT_ID],
          "gh.repo.id:#{repository.id}"
        )
      end

      def is_plan_owner?
        return true if GitHub.enterprise? # No billing on ent, so no plan owners
        repository.public? || repository.plan_owner == repository.owner
      end

      def mirror
        repository.mirror
      end

      def mirror?
        !mirror.nil?
      end

      def plan_owner
        repository.plan_owner
      end

      def network_consistent?
        network_errors.empty?
      end

      def network_errors
        @network_errors ||= repository.verify_network_consistency
      end

      def last_push
        if repository.never_pushed_to?
          "No pushes"
        else
          repository.pushed_at.in_time_zone
        end
      end

      def last_star
        return @last_star if defined?(@last_star)
        @last_star = repository.stars.order(id: :desc).first
      end

      def last_starrer
        return unless last_star
        last_star.user || ::User.ghost
      end

      def total_disk_usage
        total = git_disk_bytes +
                release_asset_disk_bytes +
                media_blob_disk_bytes +
                repository_file_disk_bytes
        number_to_human_size(total)
      end

      def git_disk_usage
        number_to_human_size(git_disk_bytes)
      end

      def release_asset_disk_usage
        number_to_human_size(release_asset_disk_bytes)
      end

      def media_blob_disk_usage
        number_to_human_size(media_blob_disk_bytes)
      end

      def repository_file_disk_usage
        number_to_human_size(repository_file_disk_bytes)
      end

      def tiered_reporting_status
        if repository.tiered_reporting_explicitly_enabled?
          "Tiered reporting enabled"
        else
          "Tiered reporting disabled"
        end
      end

      def pages_build_failure_sentry_link
        sentry_query_link(
          [
            Stafftools::RepositoryViews::PagesView::PAGES_PROJECT_ID,
            Stafftools::RepositoryViews::PagesView::PAGES_CERTIFICATES_PROJECT_ID,
            Stafftools::RepositoryViews::PagesView::PAGES_USER_PROJECT_ID,
          ],
          "repo_id:#{repository.id}",
        )
      end

      def audit_log_query
        if driftwood_ade_query?(current_user)
          repository.audit_log_kql_query
        else
          repository.audit_log_query
        end
      end

      def show_custom_properties?
        repository.owner.organization?
      end

      private

      def git_disk_bytes
        @git_disk_bytes ||= repository.disk_usage * KILOBYTE
      end

      def release_asset_disk_bytes
        @release_asset_disk_bytes ||= Releases::Public.storage_interface.storage_disk_usage(repository_id: repository.id)
      end

      def media_blob_disk_bytes
        @media_blob_disk_bytes ||= Media::Blob.storage_disk_usage(repository_network_id: repository.network_id)
      end

      def repository_file_disk_bytes
        @repository_file_disk_bytes ||= RepositoryFile.storage_disk_usage(repository_id: repository.id)
      end

      def route
        @route ||= repository.route || :none
      end
    end
  end
end
