# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class DmcaReposView < ReposView
      include AuditLogHelper

      def has_takedowns?
        Stafftools::DisabledRepositories.dmca_takedowns(user, current_user).count > 1
      end

      def first_takedown_date
        Time.at(first_takedown[:created_at] / 1000)
      end

      def first_takedown_nwo
        first_takedown[:repo]
      end

      def page_title
        "#{user.login} - DMCA Takedowns"
      end

      def no_repos_message
        "This user has no currently DMCA disabled repos"
      end

      def span_symbol(repo)
        repo.fork? ? "repo-forked" : "repo"
      end

      def takedown_query
        if driftwood_ade_query?(current_user)
          "webevents | where user_id == #{user.id} | where data.reason == 'dmca' | where action == 'staff.disable_repo'"
        else
          "user_id:#{user.id} data.reason:dmca action:staff.disable_repo"
        end
      end

      def restore_query
        if driftwood_ade_query?(current_user)
          "webevents | where user_id == #{user.id} | where data.from == 'stafftools/dmca_takedowns#destroy' | where action == 'staff.enable_repo'"
        else
          "user_id:#{user.id} action:staff.enable_repo from:\"stafftools/dmca_takedowns#destroy\""
        end
      end

      def all_events_query
        if driftwood_ade_query?(current_user)
          <<~KQL
            webevents
            | where user_id == #{user.id}
            | where (data.reason == 'dmca' and action == 'staff.disable_repo') or (data.from == 'stafftools/dmca_takedowns#destroy' and action == 'staff.enable_repo')
          KQL
        else
          "(#{takedown_query}) OR (#{restore_query})"
        end
      end

      private

      def repos_of_interest
        user.repositories.where("disabled_at IS NOT NULL AND disabling_reason = 'dmca'").order(:disabled_at)
      end

      def first_takedown
        return @first_takedown if defined? @first_takedown
        @first_takedown = Stafftools::DisabledRepositories.dmca_takedowns(user, current_user).last
      end
    end
  end
end
