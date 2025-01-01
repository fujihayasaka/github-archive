# typed: true
# frozen_string_literal: true

module Orgs
  module TeamSync
    class GroupMappingsController < ::Orgs::Controller
      include BusinessesHelper
      include AnalyticsScrubberMethods

      before_action :login_required
      before_action :organization_read_required
      before_action :admin_on_team_required
      before_action :this_team_required

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Notify,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql5,
        only: [:list_group_mappings]

      def list_group_mappings # rubocop:todo GitHub/UseRestfulActions
        if scim_managed_enterprise?(this_organization.business)
          group = this_team.external_group_team&.external_group

          mappings = []

          if group.nil?
            status = "unknown"
            synced_at = nil
          else
            group_mapping = Team::GroupMapping.new
            group_mapping.group_id = group.id
            group_mapping.team_id = this_team.id
            group_mapping.team = this_team

            if group.deleted_at.present?
              group_mapping.status = "disabled"
            else
              group_mapping.status = "updated"
            end
            group_mapping.updated_at = group.updated_at
            group_mapping.created_at = group.created_at

            mappings = [group_mapping]

            status = group_mapping.status
            synced_at = group_mapping.updated_at
          end

          respond_to do |format|
            format.html do
              render partial: "orgs/team_sync/team_mappings/group_mappings", locals: {
                mappings: mappings,
                status: status,
                synced_at: synced_at,
                group_id: group&.id,
                display_name: group&.display_name,
                slug: this_organization.business.slug,
                business_owner: this_organization.business.owner?(current_user),
              }
            end
            format.html_fragment do
              render partial: "orgs/team_sync/team_mappings/group_mappings", formats: :html, locals: {
                mappings: mappings,
                status: status,
                synced_at: synced_at,
                group_id: group&.id,
                display_name: group&.display_name,
                slug: this_organization.business.slug,
                business_owner: this_organization.business.owner?(current_user),
              }
            end
          end
        else
          tenant = this_organization.team_sync_tenant
          raise ::TeamSync::Tenant::InvalidStatusError, "Tenant not enabled" unless tenant&.team_sync_enabled?

          mappings = this_team.group_mappings

          if mapping = mappings.first
            status = mapping.status
            synced_at = mapping.synced_at if mapping.synced_at.present?
          end

          respond_to do |format|
            format.html do
              render partial: "orgs/team_sync/team_mappings/group_mappings", locals: {
                mappings: mappings,
                status: status,
                synced_at: synced_at
              }
            end
            format.html_fragment do
              render partial: "orgs/team_sync/team_mappings/group_mappings", formats: :html, locals: {
                mappings: mappings,
                status: status,
                synced_at: synced_at
              }
            end
          end
        end
      end
    end
  end
end
