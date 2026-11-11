# typed: false
# frozen_string_literal: true

class Stafftools::ExternalGroupsController < StafftoolsController
  include BusinessesHelper

  before_action :scim_managed_enterprise_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show], optional: true

  EXTERNAL_GROUPS_PAGE_SIZE = 20
  MEMBERS_PAGE_SIZE = 20
  TEAMS_PAGE_SIZE = 20
  ENTERPRISE_TEAMS_PAGE_SIZE = 20
  EXTERNAL_GROUP_SORT_LABELS = {
    "alphanumerically" => "display_name ASC",
    "newest"           => "created_at DESC",
    "oldest"           => "created_at ASC",
  }
  EXTERNAL_GROUP_SEARCH_LABELS = {
    "display name" => "display_name LIKE ?",
    "group external id" => "external_id LIKE ?",
    "scim group id" => "guid LIKE ?",
  }
  TEAM_SEARCH_LABELS = {
    "team name" => "teams.name LIKE ?",
  }
  USER_SORT_LABELS = {
    "alphanumerically" => "login ASC",
    "newest"           => "created_at DESC",
    "oldest"           => "created_at ASC",
  }
  TEAMS_SORT_LABELS = {
    "alphanumerically" => "name ASC",
    "newest"           => "created_at DESC",
    "oldest"           => "created_at ASC",
  }
  ENTERPRISE_TEAMS_SORT_LABELS = {
    "alphanumerically" => "name ASC",
    "newest"           => "created_at DESC",
    "oldest"           => "created_at ASC",
  }

  # set the layout for the dotcom EMU case here
  if !GitHub.enterprise?
    layout "layouts/stafftools/business"
  end

  def index
    external_groups = this_business.external_provider&.external_groups || ExternalGroup.none

    if params[:query].present? && external_group_search
      external_groups = external_groups.where(external_group_search, "%#{params[:query]}%")
    end

    if params[:query].present? && external_team_search
      external_groups = external_groups.joins(external_group_teams: [:team])
        .where(external_team_search, "%#{params[:query]}%")
    end

    external_groups = external_groups.not_deleted.order(external_group_query)

    if this_business.external_provider.nil?
      flash[:notice] = "SSO is not configured for this enterprise"
    end

    render "stafftools/external_groups/index",
        locals: { external_groups: external_groups.paginate(page: current_page, per_page: EXTERNAL_GROUPS_PAGE_SIZE) }
  end

  def show
    external_group = ExternalGroup.find_by_id(params[:id])
    return render_404 unless external_group

    user_ids = external_group.active_user_ids
    team_ids = external_group
      .external_group_teams
      .pluck(:team_id)

    teams = Team.where(id: team_ids).order(team_query)
    members = User.batched_scope(:id, values: user_ids).order(user_query)
    members_page = params[:members_page] ? params[:members_page].to_i : 1

    enterprise_teams = external_group.enterprise_teams.order(enterprise_team_query)
    enterprise_teams = BusinessTeam.where(id: team_ids) + enterprise_teams

    # Needed to break this out into it's own variable because while the paginate method works on still works when we
    # combine the two relations, it doesn't work when we try to call count on the combined relation. It only returns
    # the count of items in that page
    enterprise_teams_total_count = enterprise_teams.count

    render "stafftools/external_groups/show",
      locals: {
        members: members.paginate(page: members_page, per_page: MEMBERS_PAGE_SIZE, order: user_query),
        teams: teams.paginate(page: params[:teams_page], per_page: TEAMS_PAGE_SIZE),
        enterprise_teams: enterprise_teams.paginate(page: params[:enterprise_teams_page], per_page: ENTERPRISE_TEAMS_PAGE_SIZE),
        enterprise_teams_total_count: enterprise_teams_total_count,
        external_group: external_group
      }
  end

  def destroy
    external_group = this_business.external_provider&.external_groups&.find_by_id(params[:id])
    return render_404 unless external_group

    show_path = if GitHub.single_business_environment?
      stafftools_external_group_members_path(external_group)
    else
      external_group_members_stafftools_enterprise_path(this_business.slug, external_group)
    end

    if external_group.active_members_count.positive?
      flash[:error] = "Cannot delete external group with active members. Remove all members first."
      redirect_to show_path
      return
    end

    if external_group.external_group_teams.any? || external_group.enterprise_team_group_mappings.any?
      flash[:error] = "Cannot delete external group with linked teams. Unlink all teams first."
      redirect_to show_path
      return
    end

    group_data = external_group.scim_group_data(include_members: false)
    provisioner = Platform::Provisioning::EnterpriseManagedGroupProvisioner

    result = provisioner.deprovision(
      target: this_business,
      group_data: group_data,
      mapper: Platform::Provisioning::SCIMGroupMapper,
      group_guid: external_group.guid,
      group: external_group
    )

    if result.success?
      flash[:notice] = "External group '#{external_group.display_name}' successfully deleted."
    else
      flash[:error] = "Failed to delete external group '#{external_group.display_name}'."
    end

    if GitHub.single_business_environment?
      redirect_to stafftools_path + "/external_groups"
    else
      redirect_to external_groups_stafftools_enterprise_path(this_business.slug)
    end
  end

  def external_group_query # rubocop:todo GitHub/UseRestfulActions
    external_group_sort_labels[external_group_sort_order] || "created_at DESC"
  end

  memoize def external_group_sort_order # rubocop:todo GitHub/UseRestfulActions
    if external_group_sort_labels.keys.include?(params[:sort])
      params[:sort]
    else
      external_group_sort_labels.keys.first
    end
  end
  helper_method :external_group_sort_order

  def external_group_sort_labels # rubocop:todo GitHub/UseRestfulActions
    EXTERNAL_GROUP_SORT_LABELS
  end
  helper_method :external_group_sort_labels

  def external_group_search # rubocop:todo GitHub/UseRestfulActions
    EXTERNAL_GROUP_SEARCH_LABELS[external_group_search_by]
  end

  def external_team_search # rubocop:todo GitHub/UseRestfulActions
    TEAM_SEARCH_LABELS[external_group_search_by]
  end

  memoize def external_group_search_by # rubocop:todo GitHub/UseRestfulActions
    if external_group_search_labels.include?(params[:search])
      params[:search]
    else
      external_group_search_labels.first
    end
  end
  helper_method :external_group_search_by

  def external_group_search_labels # rubocop:todo GitHub/UseRestfulActions
    EXTERNAL_GROUP_SEARCH_LABELS.keys + TEAM_SEARCH_LABELS.keys
  end
  helper_method :external_group_search_labels

  def user_query # rubocop:todo GitHub/UseRestfulActions
    users_sort_labels[user_sort_order] || "created_at DESC"
  end

  def members_page # rubocop:todo GitHub/UseRestfulActions
    return nil unless params[:members_page]
    "members_page=#{params[:members_page]}&"
  end
  helper_method :members_page

  memoize def user_sort_order # rubocop:todo GitHub/UseRestfulActions
    if users_sort_labels.keys.include?(params[:member_sort])
      params[:member_sort]
    else
      users_sort_labels.keys.first
    end
  end
  helper_method :user_sort_order

  def users_sort_labels # rubocop:todo GitHub/UseRestfulActions
    USER_SORT_LABELS
  end
  helper_method :users_sort_labels

  def team_query # rubocop:todo GitHub/UseRestfulActions
    teams_sort_labels[team_sort_order] || "created_at DESC"
  end

  def teams_page # rubocop:todo GitHub/UseRestfulActions
    return nil unless params[:teams_page]
    "teams_page=#{params[:teams_page]}&"
  end
  helper_method :teams_page

  memoize def team_sort_order # rubocop:todo GitHub/UseRestfulActions
    if teams_sort_labels.keys.include?(params[:team_sort])
      params[:team_sort]
    else
      teams_sort_labels.keys.first
    end
  end
  helper_method :team_sort_order

  def teams_sort_labels # rubocop:todo GitHub/UseRestfulActions
    TEAMS_SORT_LABELS
  end
  helper_method :teams_sort_labels

  def enterprise_team_query # rubocop:todo GitHub/UseRestfulActions
    enterprise_teams_sort_labels[enterprise_team_sort_order] || "created_at DESC"
  end

  def enterprise_teams_page # rubocop:todo GitHub/UseRestfulActions
    return nil unless params[:enterprise_teams_page]
    "enterprise_teams_page=#{params[:enterprise_teams_page]}&"
  end
  helper_method :enterprise_teams_page

  memoize def enterprise_team_sort_order # rubocop:todo GitHub/UseRestfulActions
    if enterprise_teams_sort_labels.keys.include?(params[:team_sort])
      params[:enterprise_team_sort]
    else
      enterprise_teams_sort_labels.keys.first
    end
  end
  helper_method :enterprise_team_sort_order

  def enterprise_teams_sort_labels # rubocop:todo GitHub/UseRestfulActions
    ENTERPRISE_TEAMS_SORT_LABELS
  end
  helper_method :enterprise_teams_sort_labels

  memoize def this_business # rubocop:todo GitHub/UseRestfulActions
    if GitHub.single_business_environment?
      GitHub.global_business
    else
      ::Business.find_by(slug: params[:slug])
    end
  end
  helper_method :this_business

  def scim_managed_enterprise_required # rubocop:todo GitHub/UseRestfulActions
    render_404 unless scim_managed_enterprise?(this_business)
  end
end
