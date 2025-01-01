# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class SecurityView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include AuditLogHelper

      attr_reader :repository

      def page_title
        "#{repository.name_with_owner} - Security"
      end

      def audit_query
        if driftwood_ade_query?(current_user)
          "webevents | where repo_id == #{repository.id}"
        else
          "repo_id:#{repository.id}"
        end
      end

      def unlockable?
        return false if unlocked_by_staffer? || staffers_own_repo?
        current_user.can_unlock_repos?
      end

      def staffers_own_repo?
        repository.owner == current_user
      end

      def active_access_request
        repository.active_staff_access_request
      end

      def active_access_grant
        repository.active_staff_access_grant
      end

      def log_placeholder
        "Include a link/reason to be logged with this request."
      end

      def unlocked_by_staffer?
        current_user.has_unlocked_repository?(repository)
      end

      def time_of_unlock_expire
        RepositoryUnlock.with_staffer_and_repository(current_user, repository).expires_at
      end

      def repo_admin_logins
        repo_admin_ids = repository.user_ids_with_privileged_access(min_action: :admin)
        ::User.where(id: repo_admin_ids).pluck(:login).sort_by(&:downcase)
      end
    end
  end
end
