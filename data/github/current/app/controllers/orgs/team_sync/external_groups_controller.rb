# typed: true
# frozen_string_literal: true

module Orgs
  module TeamSync
    class ExternalGroupsController < ::Orgs::Controller
      include ExternalGroupsHelper
      include AnalyticsScrubberMethods

      before_action :login_required
      before_action :organization_read_required

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Configurations,
        ApplicationRecord::Notify,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql5,
        only: [:external_group_suggestions]

      def external_group_suggestions # rubocop:todo GitHub/UseRestfulActions
        if this_organization.enterprise_managed_user_enabled?
          load_external_groups
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
    end
  end
end
