# typed: true
# frozen_string_literal: true

class Businesses::IdentityProviderController < Businesses::BusinessController
  include BusinessesHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:external_group_members]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:external_group_teams]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:external_groups]

  before_action :read_enterprise_scim_required
  before_action :idp_managed_business_required

  def external_groups # rubocop:todo GitHub/UseRestfulActions
    query_args = parse_query_string(query_param, filter_map: BusinessesHelper::EXTERNAL_GROUPS_QUERY_FILTERS)
    sort_by = params[:sort_by] || "asc"

    external_groups = if this_business.enterprise_server_scim_enabled?
      ExternalGroup.not_deleted
    else # must be EMU
      this_business.external_provider&.external_groups&.not_deleted
    end

    if external_groups && query_args.any?
      query = ActiveRecord::Base.sanitize_sql_like(query_args[:query].to_s.strip.downcase)
      external_groups = external_groups.like_display_name(query) if query.present?
    end

    # Filter the external groups based on the sync_status.
    if external_groups && query_args[:sync_status].present?
      external_groups = filter_groups_by_sync_status(query_args[:sync_status], external_groups)
    end

    external_groups = if external_groups
      if sort_by == "asc"
        external_groups.order_by_display_name_asc.paginate(page: current_page)
      else
        # only other sort option is desc or bogus value and can default to desc
        external_groups.order_by_display_name_desc.paginate(page: current_page)
      end
    else
      []
    end

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/external_groups/external_groups_list", locals: {
            query: query_param,
            external_groups: external_groups,
          }
        else
          render "businesses/external_groups/external_groups", locals: {
            query: query_param,
            external_groups: external_groups,
          }
        end
      end
    end
  end

  def external_group_members # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_business.external_provider

    external_group = this_business.external_provider.external_groups
      .find_by_id(params[:id])
    return render_404 unless external_group

    query_args = parse_query_string(query_param)

    user_ids = ExternalIdentity.joins(:external_identity_group_memberships)
      .where(external_identity_group_memberships: { external_group_id: external_group.id })
      .is_active
      .pluck(:user_id)

    batched_scope = if query_args.present?
      User.batched_scope(:id, values: user_ids) { |scope| scope.like_login_or_profile_name(query_args[:query]) }
    else
      User.batched_scope(:id, values: user_ids)
    end

    members = batched_scope.order(:login).paginate(page: current_page, per_page: page_size)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/external_groups/external_group_members_list", locals: {
            query: query_param,
            members: members,
            external_group: external_group
          }
        else
          render "businesses/external_groups/external_group_members", locals: {
            query: query_param,
            members: members,
            external_group: external_group
          }
        end
      end
    end
  end

  def external_group_teams # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_business.external_provider

    external_group = this_business.external_provider.external_groups
      .find_by_id(params[:id])
    return render_404 unless external_group

    query_args = parse_query_string(query_param, filter_map: BusinessesHelper::EXTERNAL_GROUPS_QUERY_FILTERS)

    team_ids = external_group
      .external_group_teams
      .pluck(:team_id)

    teams = if this_business.erp_feature_enabled?(:enterprise_teams_crud)
      Team.with_business_teams.where(id: team_ids)
    else
      Team.where(id: team_ids)
    end

    if query_args.present?
      query = ActiveRecord::Base.sanitize_sql_like(query_args[:query].to_s.strip.downcase)
      teams = teams.like_name(query) if query.present?
    end

    # Filter the teams based on the sync_status
    if teams.any? && query_args[:sync_status].present?
      teams = filter_teams_by_sync_status(query_args[:sync_status], teams)
    end

    teams = teams.order_by_name_asc.paginate(page: current_page, per_page: page_size)

    respond_to do |format|
      format.html do
        if request.xhr?
          headers["Cache-Control"] = "no-cache, no-store"
          render partial: "businesses/external_groups/external_group_teams_list", locals: {
            query: query_param,
            teams: teams,
            external_group: external_group
          }
        else
          render "businesses/external_groups/external_group_teams", locals: {
            query: query_param,
            teams: teams,
            external_group: external_group
          }
        end
      end
    end
  end

  private

  # Public: The current page size for pagination.
  #
  # Returns an Integer
  def page_size
    PAGE_SIZE
  end

  # Filter the external groups based on the sync_status.
  # Returns the filtered external groups as an ActiveRecord::Relation.
  # Params: sync_status - The sync_status to filter by. One of "success", "failure", "no_status"
  #         external_groups - An ActiveRecord::Relation of ExternalGroup objects to filter.
  def filter_groups_by_sync_status(sync_status, external_groups)
    return external_groups unless BusinessesHelper::EXTERNAL_GROUP_SYNC_STATUS.values.include?(sync_status)

    case sync_status
    when BusinessesHelper::EXTERNAL_GROUP_SYNC_STATUS["SYNCED"]
      # All external groups that have external group teams, all of which are in a synced status.
      external_groups
        .where(<<~SQL, sync_status: ExternalGroupTeam.sync_statuses["in_sync"])
          external_groups.id IN (
            SELECT external_group_id
            FROM external_group_teams
            GROUP BY external_group_id HAVING SUM(
              case when sync_status = :sync_status then 1 else 0 end
            ) = count(*)
          )
        SQL
    when BusinessesHelper::EXTERNAL_GROUP_SYNC_STATUS["NOT_SYNCED"]
      # All external groups that have at least one external group team that is not in-sync.
      # Distinct is required since there might be multiple external group teams when filtering out of sync, but we only
      # need the unique external groups. Without it, we'd get 1 external group per joined external group team that's out
      # of sync because of the join.
      external_groups
        .distinct
        .joins("LEFT JOIN external_group_teams ON external_group_teams.external_group_id = external_groups.id")
        .where("external_group_teams.sync_status <> ?", ExternalGroupTeam.sync_statuses["in_sync"])
    when BusinessesHelper::EXTERNAL_GROUP_SYNC_STATUS["NO_STATUS"]
      # All external groups without any corresponding external group teams.
      external_groups
        .joins("LEFT JOIN external_group_teams ON external_group_teams.external_group_id = external_groups.id")
        .where(external_group_teams: { external_group_id: nil })
    end
  end

  def filter_teams_by_sync_status(sync_status, teams)
    return teams unless BusinessesHelper::EXTERNAL_GROUP_SYNC_STATUS.values.include?(sync_status)
    # this status is not relevant to teams in this context since at least one link has to exist for this page to show anything
    return teams if sync_status == BusinessesHelper::EXTERNAL_GROUP_SYNC_STATUS["NO_STATUS"]

    # external group teams are either in-sync or out-of-sync
    case sync_status
    when BusinessesHelper::EXTERNAL_GROUP_SYNC_STATUS["SYNCED"]
      teams
        .joins(:external_group_team)
        .where(external_group_teams: { sync_status: ExternalGroupTeam.sync_statuses["in_sync"] })
    when BusinessesHelper::EXTERNAL_GROUP_SYNC_STATUS["NOT_SYNCED"]
      teams
        .joins(:external_group_team)
        .where("external_group_teams.sync_status <> ?", ExternalGroupTeam.sync_statuses["in_sync"])
    end
  end
end
