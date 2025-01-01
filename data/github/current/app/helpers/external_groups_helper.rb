# typed: false
# frozen_string_literal: true

module ExternalGroupsHelper
  def load_external_groups(limit: nil)
    groups = []
    group_ids_with_guest_collaborator = []
    ActiveRecord::Base.connected_to(role: :reading) do
      groups = this_organization.business.external_provider
        .external_groups
        .not_deleted

      # Check is the query was passed in and add a scope to filter on a display_name
      if params[:q].present?
        groups = groups.like_display_name(params[:q])
      elsif user_feature_enabled?(:primer_experimental_selectpanel_external_identities) && user_feature_enabled?(:primer_select_panel_use_experimental_non_local_form) && limit
        groups = groups.limit(limit)
      end
      if this_organization.enterprise_managed_user_enabled?
        group_ids_with_guest_collaborator = ExternalGroup.external_group_ids_with_guest_collaborator(groups.pluck(:id))
      end
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "orgs/team_sync/external_groups/idp_external_group_suggestions", formats: :html, locals: {
          team: this_team,
          groups: groups,
          group_ids_with_guest_collaborator: group_ids_with_guest_collaborator
        }
      end
    end
  end

  def groups_suggestions_path(**kwargs)
    return group_suggestions_path(**kwargs) if this_organization.enterprise_server_scim_enabled?

    external_group_suggestions_path(**kwargs)
  end

  def instrument_external_group_delete(external_identity_ids, external_group_id)
    return unless external_group_id
    return unless external_identity_ids.any?

    users = ExternalIdentity.includes(:user).where(id: external_identity_ids).map(&:user).compact
    return unless users.any?

    external_group = ExternalGroup.find_by(id: external_group_id)
    return unless external_group

    users.each do |user|
      external_group.instrument_event(:remove_member, nil, user: user)
    end
  end

  def instrument_external_identity_delete(external_group_ids, external_identity_id)
    return unless external_identity_id
    return unless external_group_ids.any?

    external_groups = ExternalGroup.where(id: external_group_ids)
    return unless external_groups.any?

    user = ExternalIdentity.includes(:user).find_by(id: external_identity_id)&.user
    return unless user

    external_groups.each do |external_group|
      external_group.instrument_event(:remove_member, nil, user: user)
    end
  end
end
