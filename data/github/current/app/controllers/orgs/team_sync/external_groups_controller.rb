# typed: true
# frozen_string_literal: true

module Orgs
  module TeamSync
    class ExternalGroupsController < ::Orgs::Controller
      include ExternalGroupsHelper
      include AnalyticsScrubberMethods

      before_action :login_required
      before_action :organization_read_required
      before_action :members_can_create_teams_required

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Configurations,
        ApplicationRecord::Notify,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql5,
        only: [:external_group_suggestions]

      def external_group_suggestions # rubocop:todo GitHub/UseRestfulActions
        if this_organization.enterprise_managed_user_enabled?
          load_external_groups(limit: params[:limit]&.to_i)
        else
          tenant = this_organization.team_sync_tenant
          raise ::TeamSync::Tenant::InvalidStatusError, "Tenant not enabled" unless tenant&.team_sync_enabled?
          response = GroupSyncer.client.list_groups(org_id: tenant.organization.global_relay_id, query: params[:q].presence)

          if response.error.present?
            GitHub.dogstats.increment("team_sync.list_groups", tags: ["twirp_service:groups", "error:#{response.error.code}"])
            err = ::TeamSync::ServiceResponseError.new("[#{response.error.code}] #{response.error.msg}: #{response.error.meta}")
            err.set_backtrace(caller)
            Failbot.report!(err)
            render partial: "orgs/team_sync/external_groups/external_group_suggestions_error", formats: :html, status: 500
            return
          end

          groups = response.data.groups

          respond_to do |format|
            format.html_fragment do
              render partial: "orgs/team_sync/external_groups/external_group_suggestions", formats: :html, locals: { groups: groups }
            end
          end
        end
      rescue Faraday::Error => e
        Failbot.report!(e)
        render partial: "orgs/team_sync/external_groups/external_group_suggestions_error", formats: :html, status: 500
      end

      private

      def members_can_create_teams_required
        # Allow users who can create teams at the org level.
        return if this_organization.can_create_team?(current_user)

        # Allow users who are maintainers of any team in the organization
        return if user_is_maintainer_of_any_team?

        render_404
      end

      def user_is_maintainer_of_any_team?
        # Check if the current user is a maintainer of any team in the organization
        team_ids = this_organization.teams.pluck(:id)
        return false if team_ids.empty?

        Ability.where(
          actor_type: "User",
          actor_id: current_user.id,
          subject_type: "Team",
          subject_id: team_ids,
          action: Ability.actions[:admin],
          priority: Ability.priorities[:direct]
        ).exists?
      end
    end
  end
end
