# typed: false
# frozen_string_literal: true

module Stafftools
  module User
    class GistView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include AuditLogHelper
      include Stafftools::Sentry
      include Stafftools::StatusChecklist

      attr_reader :gist

      delegate :user_param, :user, :parent, :fork?, to: :gist

      def page_title
        "Overview for Gist #{gist.name_with_owner}"
      end

      def name
        gist.name_with_owner
      end

      def sentry_link
        sentry_query_link "gist_repo_name:#{gist.repo_name}"
      end

      def dmca?
        return false unless dmca_and_country_blocking_enabled?

        gist.access.dmca?
      end

      def country_blocks?
        return false unless dmca_and_country_blocking_enabled?

        gist.country_blocks && gist.country_blocks.any?
      end

      def country_blocks_sentence
        gist.country_blocks.map { |reason, _url| reason }.to_sentence
      end

      def dmca_and_country_blocking_enabled?
        return false if GitHub.enterprise?

        !deleted? && gist.user
      end

      def deleted?
        gist.deleted?
      end

      def status_message
        if deleted?
          "This gist has been deleted."
        elsif !gist.active?
          "This gist is queued for deletion."
        else
          nil
        end
      end

      def link_to_source?
        !deleted?
      end

      def created_at
        gist.created_at.in_time_zone
      end

      def updated_at
        gist.updated_at.in_time_zone
      end

      def last_push
        if gist.pushed_at.nil?
          "No pushes"
        else
          gist.pushed_at.in_time_zone
        end
      end

      def last_maintenance_at
        gist.last_maintenance_at.try(:in_time_zone) || "never"
      end

      def last_maintenance_status
        gist.maintenance_status.to_s
      end

      def marked_broken?
        gist.maintenance_status == "broken"
      end

      def db_state
        git_repo_db_state gist
      end

      def git_state
        git_repo_git_state gist
      end

      def fs_state
        git_repo_fs_state gist
      end

      # Query to find this Gist in the audit log
      def audit_query
        if driftwood_ade_query?(current_user)
          <<~KQL
            webevents
            | where data.gist_repo_name == "#{gist.repo_name}" or data.gist == "#{gist.name_with_owner}"
          KQL
        else
          "data.gist_id:#{gist.id}"
        end
      end
    end
  end
end
