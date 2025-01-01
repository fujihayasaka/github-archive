# typed: true
# frozen_string_literal: true

class Orgs::TeamsController < Orgs::Controller
  include ExternalGroupsHelper
  include Orgs::TeamsHelper
  include UrlHelpers

  skip_before_action :cap_pagination, only: [:index]
  before_action :login_required
  before_action :organization_read_required, except: [:index, :teams, :child_teams]
  before_action :organization_admin_required, except: [:index, :teams, :child_teams, :new, :create, :check_name, :goto, :leave, :ldap_group_suggestions, :destroy, :destroy_team_teams, :edit, :update, :dismiss_org_teams_banner, :migrate_legacy_admin_team, :members_toolbar_actions, :repositories_toolbar_actions, :team_teams_toolbar_actions, :parent_search, :child_search, :important_changes_summary, :team_breadcrumbs, :move_child_team, :review_assignment, :update_review_assignment, :migrate_discussions]
  before_action :admin_on_team_required, except: [:index, :teams, :child_teams, :new, :goto, :create,  :check_name, :leave, :ldap_group_suggestions, :dismiss_org_teams_banner, :owners_team, :destroy_owners_team, :rename_owners_team, :set_visibility, :teams_toolbar_actions, :destroy_teams, :parent_search, :important_changes_summary, :team_breadcrumbs, :migrate_discussions, :repositories_toolbar_actions]
  before_action :this_team_required, except: [:index, :child_teams, :teams, :new, :goto, :create,  :check_name, :ldap_group_suggestions, :dismiss_org_teams_banner, :owners_team, :destroy_owners_team, :rename_owners_team, :set_visibility, :teams_toolbar_actions, :destroy_teams, :parent_search, :important_changes_summary]
  before_action :set_team_context_crumb, only: [:teams]
  before_action :organization_team_creation_required, only: [:new, :create]
  before_action :mask_analytics_data
  before_action :admin_on_team_or_organization_team_creation_enabled, only: [:check_name]
  before_action only: %i(create update destroy destroy_teams new edit set_visibility) do
    T.bind(self, T.any(Orgs::TeamMembersController, Orgs::TeamsController))
    ensure_trade_restrictions_allows_org_member_management(fallback_location: teams_url(this_organization))
  end

  javascript_bundle :settings
  stylesheet_bundle :orgs
  stylesheet_bundle :settings

  # check whether organization invitations have been rate limited; but do not
  # enforce rate limiting in this controller.
  include Orgs::Invitations::RateLimiting

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:team_breadcrumbs]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:child_search]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    only: [:child_teams]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:goto]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:important_changes_summary]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:teams]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:owners_team]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    only: [:parent_search]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:members_toolbar_actions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:repositories_toolbar_actions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:team_teams_toolbar_actions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:teams_toolbar_actions]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:ldap_group_suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :teams, :new, :team_breadcrumbs, :edit, :owners_team, :teams_toolbar_actions,
      :important_changes_summary, :team_teams_toolbar_actions],
    optional: true

  def index
    return render_404 unless this_organization

    unless this_organization.direct_member?(current_user)
      return render_404 if request.xhr?
      flash[:notice] = "You’re not a member of any teams in this organization."
      return redirect_to user_path(this_organization)
    end

    if this_organization.team_sync_failed?
      failed_teams = this_organization.team_sync_failed_teams.order(:name).pluck(:name).join(", ")
      flash.now[:error] = <<~MESSAGE
        We are having trouble syncing some of your teams right now.
        Please ensure they are correctly mapped to accessible groups,
        and open a support ticket if the problem persists.
        Affected teams: #{failed_teams}.
      MESSAGE
    end

    teams = paginated_teams(
      this_organization.team_search_for_user(
        TeamSearchQuery.new(params[:query]),
        current_user,
        immediate_only: !params[:query].present?,
        order_by_name_asc: true,
        with_business_teams: supports_business_teams?
      )
    )

    data = {
      organization: this_organization,
      query: params[:query],
      teams: teams
    }

    view = create_view_model(Orgs::Teams::IndexPageView, data)

    if request.xhr?
      respond_to do |format|
        format.html do
          render partial: "orgs/teams/list", locals: { view: view }
        end
      end
    elsif this_organization.has_sdn_new_org_with_free_plan_restriction?
      render "orgs/restricted_org_notice", locals: {
        target: this_organization,
        header_view: create_view_model(Orgs::HeaderView, organization: this_organization),
        selected_nav_item: :teams
      }
    else
      render "orgs/teams/index", locals: { view: view }
    end
  end

  def teams # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_organization
    return render_404 unless this_organization.direct_member?(current_user)
    return render_404 unless this_team
    return render_404 unless this_team.locally_managed?

    teams = paginated_teams(this_team.team_search_for_user(TeamSearchQuery.new(params[:query]), current_user, immediate_only: !params[:query].present?, order_by_name_asc: true))

    data = {
      query: params[:query],
      team: this_team,
      organization: this_organization,
      teams: teams
    }

    if request.xhr?
      respond_to do |format|
        format.html do
          render partial: "orgs/teams/list", locals: {
            view: create_view_model(Orgs::Teams::TeamsPageView, data)
          }
        end
      end
    else
      view = create_view_model(
        Orgs::Teams::TeamsPageView,
        data,
      )
      render "orgs/teams/teams", locals: {
        selected_nav_item: :teams,
        view: view
      },
      layout: "team"
    end
  end

  PAGE_SIZE = 10

  def child_teams # rubocop:todo GitHub/UseRestfulActions
    return redirect_to teams_path(this_organization) unless request.xhr?

    return head 404 unless params[:parent_team_slug].present?
    team = this_organization.teams.find_by_slug(params[:parent_team_slug])
    return head 404 unless team.visible_to?(current_user)

    teams = team.async_descendants(immediate_only: true)
      .sync
      .simple_paginate(
        page: params[:page].to_i,
        per_page: PAGE_SIZE,
      )
    member_ids_for_teams = Team.member_ids_indexed_by_team_ids(teams.pluck(:id))

    respond_to do |format|
      format.html do
        render partial: "orgs/teams/child_teams", locals: {
          parent_team_slug: team.slug,
          parent_indent: params[:parent_indent].to_i,
          show_bulk_actions: this_organization.adminable_by?(current_user),
          member_ids_for_teams: member_ids_for_teams,
          organization: this_organization,
          child_teams: teams,
          child_indent: [params[:parent_indent].to_i + 1, 15].min,
        }
      end
    end
  end

  def new
    @organization = this_organization

    parent_team_param = if params[:parent_team].present?
      parent_team = this_organization.teams.find_by_slug(params[:parent_team])

      if parent_team && parent_team.adminable_by?(current_user) && parent_team.closed?
        { "id" => parent_team.global_relay_id, "name" => parent_team.name }
      end
    end

    parameters = { "privacy" => "CLOSED", "parentTeam" => parent_team_param, "name" => params[:name] }
    render "orgs/teams/new", locals: { team_params: parameters }
  end

  def move_child_team # rubocop:todo GitHub/UseRestfulActions
    attributes = params.require(:child_team).permit(:id)
    child_team = this_organization.teams.find(attributes[:id])

    if child_team.adminable_by?(current_user)
      success, error = child_team.request_update_on_behalf_of(current_user,
        {},
        { parent_team: this_team })
      if success
        flash[:notice] = "You’ve successfully moved the team."
      else
        flash[:error] = error[:message]
      end
    else
      success, error = create_team_change_parent_request(child_team, this_team)

      if success
        flash[:notice] = "A request has been made to move this team."
      else
        flash[:error] = error
      end
    end

    redirect_to team_teams_path(this_team)
  end

  def child_search # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render partial: "orgs/teams/child_team_search", formats: :html, locals: {
          organization: this_organization,
          team: this_team,
          potential_child_teams: this_team.async_potential_child_teams(viewer: current_user, query: params[:q]).sync,
          query: params[:q],
        }
      end
    end
  end

  def edit
    if @team = this_team
      @organization = this_organization

      render(
        "orgs/teams/edit",
        locals: {
          selected_nav_item: :settings,
          team_entity: @team,
        },
        layout: "team")
    else
      render_404
    end
  end

  def review_assignment # rubocop:todo GitHub/UseRestfulActions
    unless this_team
      render_404
      return
    end
    @organization = this_organization
    render Organizations::Teams::ReviewAssignmentComponent.new(team: this_team), layout: "team"
  end

  def update_review_assignment # rubocop:todo GitHub/UseRestfulActions
    errors = []
    unless this_team
      render_404
      return
    end
    unless this_team.updatable_by?(current_user)
      flash[:error] = "#{current_user} does not have permission to update this team."
      redirect_to edit_team_review_assignment_path(this_organization, this_team) and return
    end

    this_team.review_request_delegation_notify_team = !params[:disable_notify_team]
    auto_assign_enabled = !!params[:review_assignment]

    excluded_member_ids = params[:excluded_members] || []
    ReviewRequestDelegationExcludedMember.update_excluded_team_members(
      team: this_team,
      excluded_member_ids: excluded_member_ids,
      exclude_team_members: !!params[:exclude_team_members]
    )

    if auto_assign_enabled
      unless !!params[:algorithm] && !!params[:team_member_count]
        flash[:error] = "Algorithm and team member count needed when enabling."
        redirect_to edit_team_review_assignment_path(this_organization, this_team) and return
      end

      this_team.review_request_delegation_enabled = true
      this_team.review_request_delegation_algorithm = params[:algorithm]
      this_team.review_request_delegation_member_count = params[:team_member_count].to_i
      this_team.review_request_delegation_remove_team_request = !!params[:remove_team_request]
      this_team.review_request_delegation_include_child_team_members = !!params[:include_child_team_members]
      this_team.review_request_delegation_count_members_already_requested = !!params[:count_members_already_requested]
    else
      this_team.review_request_delegation_enabled = false
    end

    if this_team.save
      flash[:notice] = "You've successfully updated the team's code review settings."
      render Organizations::Teams::ReviewAssignmentComponent.new(team: this_team), layout: "team"
    else
      flash[:error] = errors.first
      redirect_to edit_team_review_assignment_path(this_organization, this_team)
    end
  end

  def create
    attributes = team_params

    unless this_organization.can_create_team?(current_user)
      error_message = "#{current_user} does not have permission to create teams on this organization."
      render_teams_new_with_error(error_message, attributes)
      return
    end

    privacy = attributes[:privacy] == "secret" ? "secret" : "closed"
    notification_setting = attributes[:notification_setting] || Team::NOTIFICATIONS_ENABLED

    # Tracks teams created with notifications enabled vs disabled.
    case notification_setting
    when Team::NOTIFICATIONS_ENABLED
      GitHub.dogstats.increment("team.notification_setting.count", tags: ["action:create", "setting:enabled"])
    when Team::NOTIFICATIONS_DISABLED
      GitHub.dogstats.increment("team.notification_setting.count", tags: ["action:create", "setting:disabled"])
    end

    parent_team_id = if attributes[:parent_team_id].present?
      Platform::Helpers::NodeIdentification.from_global_id(attributes[:parent_team_id])[1]
    end

    group_mappings = if this_organization.scim_managed_enterprise?
      transform_scim_group_mapping_inputs(attributes[:external_group_team])
    else
      transform_team_sync_mapping_inputs(attributes[:group_mappings])
    end

    team = this_organization.create_team(
      creator: current_user,
      ldap_dn: attributes[:ldap_dn],
      maintainers: [current_user],
      group_mappings: group_mappings,
      attrs: {
        name: attributes[:name],
        description: attributes[:description],
        privacy: privacy,
        notification_setting: notification_setting,
        parent_team_id: parent_team_id
      }
    )

    if team.errors.any?
      render_teams_new_with_error(team.errors.full_messages.first, attributes)
      return
    end

    if notification_setting == Team::NOTIFICATIONS_DISABLED
      GlobalInstrumenter.instrument(
        "team.notification.setting",
        team_id: team.id,
        organization_id: team.organization.id,
        org_plan: team.organization.plan.name,
        business_id: team.organization.business&.id,
        business_type: team.organization.business&.business_type,
        notification_setting: notification_setting
      )
    end

    requested_parent_team = if team.pending_change_parent_requests.any?
      team.pending_change_parent_requests.first.parent_team
    end

    if ldap_group_import?
      respond_to do |f|
        f.html do
          render partial: "organizations/import_group",
            locals: { team: team }
        end
      end
    elsif requested_parent_team && !requested_parent_team.adminable_by?(current_user)
      flash[:notice] = "Team was successfully created. The requested parent team will be reflected pending approval."

      redirect_to team_path(team)
    else
      redirect_to team_path(team)
    end
  end

  def update
    attributes = team_params

    requested_parent_team_id = params.dig("team", "parent_team_id")
    new_parent_requested = requested_parent_team_id &&
                          (this_team.parent_team.nil? ||
                          requested_parent_team_id != this_team.parent_team.global_relay_id)

    if new_parent_requested
      requests_to_cancel = this_team.pending_change_parent_requests(direction: "outbound_child_initiated")

      requests_to_cancel.each do |req|
        unless req.parent_team.global_relay_id == requested_parent_team_id
          cancel_team_change_parent_request(req)
        end
      end
    end

    variables = attributes.slice(:name, :description, :ldap_dn, :privacy, :notification_setting)
                  .permit(:name, :description, :ldap_dn, :privacy, :notification_setting)
                  .to_h
                  .symbolize_keys

    # Tracks how many teams are updated to have notifications disabled (previously enabled) vs. notifications enabled (previously disabled).
    case attributes[:notification_setting]
    when Team::NOTIFICATIONS_ENABLED
      if this_team.notification_setting != Team::NOTIFICATIONS_ENABLED
        GitHub.dogstats.increment("team.notification_setting.count", tags: ["action:update", "setting:enabled"])
      end
    when Team::NOTIFICATIONS_DISABLED
      if this_team.notification_setting != Team::NOTIFICATIONS_DISABLED
        GitHub.dogstats.increment("team.notification_setting.count", tags: ["action:update", "setting:disabled"])

        GlobalInstrumenter.instrument(
          "team.notification.setting",
          team_id: this_team.id,
          organization_id: this_team.organization.id,
          org_plan: this_team.organization.plan.name,
          business_id: this_team.organization.business&.id,
          business_type: this_team.organization.business&.business_type,
          notification_setting: Team::NOTIFICATIONS_DISABLED
        )
      end
    end

    group_mappings = if this_team.scim_managed_enterprise?
      transform_scim_group_mapping_inputs(attributes[:external_group_team])
    else
      transform_team_sync_mapping_inputs(attributes[:group_mappings])
    end

    # Pass parentTeamId only if received since a `nil` parentTeamId indicates
    # the parent should be removed
    parent_team_input = if attributes.key?(:parent_team_id)
      if attributes[:parent_team_id].present?
        id = Platform::Helpers::NodeIdentification.from_global_id(attributes[:parent_team_id])[1]
        { parent_team: Team.find(id) }
      else
        { parent_team: nil }
      end
    else
      {}
    end

    success, error = this_team.request_update_on_behalf_of(current_user,
      variables,
      parent_team_input,
      group_mappings: group_mappings)

    error = error[:message] unless success

    if request.xhr?
      if ldap_group_import?
        respond_to do |f|
          f.html do
            render partial: "organizations/import_group",
              locals: { team: this_team }
          end
        end
      else
        head :ok
      end
    else
      if error
        @organization = this_organization
        @team = this_team

        flash.now[:error] = error

        variables["parentTeam"] = { "id" => attributes[:parent_team_id], "name" => attributes[:parent_team_name] }
        render(
          "orgs/teams/edit",
          locals: {
            selected_nav_item: :settings,
            team_params: variables,
            team_entity: @team,
          },
          layout: "team")
      else
        requested_parent_team = if this_team.pending_change_parent_requests.any?
          this_team.pending_change_parent_requests.first.parent_team
        end

        if requested_parent_team && !requested_parent_team.adminable_by?(current_user)
          flash[:notice] = "Team was successfully updated. The requested parent team will be reflected pending approval."
          redirect_to team_path(this_team)
        else
          flash[:notice] = "You’ve successfully updated the team."
          redirect_to team_path(this_team)
        end
      end
    end
  end

  def destroy
    destroyed = destroy_these_teams([this_team])

    if request.xhr?
      if ldap_group_import?
        head 204
      else
        head 200
      end
    else
      if destroyed != [this_team]
        @organization = this_organization
        @team = this_team

        if this_team.has_child_teams? && !this_team.organization.adminable_by?(current_user)
          flash.now[:error] = "Only organization admins can delete parent teams."
        elsif this_team.errors.any?
          flash.now[:error] = this_team.errors.full_messages.join(", ")
        else
          flash.now[:error] = "Sorry, something went wrong. Please try again."
        end

        render(
          "orgs/teams/edit",
          locals: {
            selected_nav_item: :settings,
            team_entity: @team,
          },
          layout: "team")
      else
        flash[:notice] = "You’ve successfully deleted the team. Updated permissions may take a few minutes to take effect."
        redirect_to teams_path(this_organization)
      end
    end
  end

  def destroy_teams # rubocop:todo GitHub/UseRestfulActions
    teams_to_remove = this_organization.teams.where(id: params[:team_ids]).limit(20).to_a
    destroyed_teams = destroy_these_teams(teams_to_remove)

    case destroyed_teams.size
    when 1
      flash[:notice] = "You removed the #{destroyed_teams.first.name} team. Updated permissions may take a few minutes to take effect."
    else
      flash[:notice] = "You removed #{destroyed_teams.size} teams. Updated permissions may take a few minutes to take effect."
    end

    redirect_to teams_path(this_organization)
  end

  def destroy_team_teams # rubocop:todo GitHub/UseRestfulActions
    child_teams_to_remove = this_team.descendants.where(id: params[:team_ids]).limit(20).to_a

    async_admin_status_by_team = child_teams_to_remove.map { |t| t.async_adminable_by?(current_user) }

    async_teams_to_remove = Promise.all(async_admin_status_by_team).then do |admin_statuses|
      child_teams_to_remove.zip(admin_statuses).reduce([]) do |result, (team, current_user_is_admin)|
        result << team if current_user_is_admin
        result
      end
    end

    destroyed_teams = destroy_these_teams(async_teams_to_remove.sync)

    case destroyed_teams.size
    when 0
      flash[:notice] = "No teams were removed. You may not have sufficient permissions."
    when 1
      flash[:notice] = "You removed the #{destroyed_teams.first.name} team. Updated permissions may take a few minutes to take effect."
    else
      flash[:notice] = "You removed #{destroyed_teams.size} teams. Updated permissions may take a few minutes to take effect."
    end

    redirect_to team_teams_path(this_team)
  end

  private def destroy_these_teams(teams_to_remove)
    destroyed_teams = []

    teams_to_remove.each do |team|
      next if team.has_child_teams? && !this_organization.adminable_by?(current_user)
      next if team.enterprise_team_managed?
      if team.legacy_owners?
        DestroyTeamJob.perform_later(team.id)

        this_organization.update_attribute(:destroy_owners_team_attempted_at, Time.now)
      else
        team.destroy
      end
      destroyed_teams << team
    end
    destroyed_teams
  end

  def leave # rubocop:todo GitHub/UseRestfulActions
    if this_team.scim_managed_enterprise? && this_team.externally_managed?
      flash[:notice] = "You cannot leave an externally managed team.  Please ask your Identity Provider administrator to be removed from the group linked to this team."
      redirect_to :back
    elsif this_team.enterprise_team_managed?
      flash[:notice] = "You cannot leave an externally managed team.  Please ask your enterprise administrator to be removed from the enterprise team linked to this team."
      redirect_to :back
    else
      this_team.remove_member(current_user, send_notification: false)

      if viewer_is_member_of_this_org?
        flash[:message] = "You’ve successfully left the team."

        if params[:return_to].present?
          safe_redirect_to params[:return_to]
        else
          redirect_to :back
        end
      else
        flash[:message] = "You’ve successfully left the organization."
        redirect_to user_path(this_organization)
      end
    end
  end

  def parent_search # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render partial: "orgs/teams/parent_search", formats: :html, locals: {
          organization: this_organization,
          team: this_team,
          query: params[:q]
        }
      end
    end
  end

  def set_visibility # rubocop:todo GitHub/UseRestfulActions
    team_ids = params[:team_ids]
    privacy = params[:privacy]
    privacy = privacy ? privacy.to_sym : :closed
    result = this_organization.bulk_update_privacy(team_ids, privacy)
    updates = result[:updates]
    failures = result[:failures]
    failures_string = ""
    team_name = ""

    if this_organization.feature_enabled?(:teams_can_not_become_secret_with_pending_reviews)
      failures_string = "#{failures.any? ? " However, these teams failed to update: #{failures.join(", ")}" : ""}"
      team_name = updates[0] if updates.size == 1
    else
      team_name = Team.find(updates[0]).name if updates.size == 1
    end

    flash[:notice] = if updates.size == 1
      "You've made #{team_name} #{privacy_text(privacy)}.#{failures_string}"
    else
      "You've made #{updates.size} teams #{privacy_text(privacy)}.#{failures_string}"
    end

    redirect_to :back
  end

  def goto # rubocop:todo GitHub/UseRestfulActions
    team = this_organization.teams.find_by_slug(params[:team_name])

    if team
      redirect_to team_path(team)
    else
      flash[:error] = "Team not found."
      redirect_to teams_path(this_organization)
    end
  end

  def check_name # rubocop:todo GitHub/UseRestfulActions
    name = params[:value]
    return head 400 if name.blank?
    slug = name.parameterize

    # Name has an emoji
    unless GitHub::UTF8.valid_unicode3?(name)
      respond_to do |format|
        format.html_fragment do
          return render partial: "orgs/teams/name_message", formats: :html, status: 422, locals: { is_invalid: true, exists: false }
        end
      end
    end

    # Name is unchanged for the team.
    if this_team.present? && this_team.slug == slug
      return head 200
    end

    # Name is already used.
    if this_organization.teams.find_by_name(name) || this_organization.teams.find_by_slug(slug)
      respond_to do |format|
        format.html_fragment do
          return render partial: "orgs/teams/name_message", formats: :html, status: 422, locals: { exists: true, is_invalid: false }
        end
      end
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "orgs/teams/name_message", formats: :html, locals: {
          is_invalid: false,
          exists: false,
          slug: slug,
          org: this_organization,
        }
      end
    end
  end

  def ldap_group_suggestions # rubocop:todo GitHub/UseRestfulActions
    if this_organization.enterprise_server_scim_enabled?
      load_external_groups
    else #LDAP groups
      groups = GitHub::LDAP.search.find_groups(params[:q])
      respond_to do |format|
        format.html_fragment do
          render partial: "orgs/teams/ldap_group_suggestions", formats: :html, locals: { groups: groups }
        end
        format.html do
          params[:dn]
          render partial: "orgs/teams/ldap_group_suggestions", locals: { groups: groups }
        end
      end
    end

  end

  def dismiss_org_teams_banner # rubocop:todo GitHub/UseRestfulActions
    current_user.dismiss_notice("org_teams_banner")

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  def owners_team # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless legacy_owners_team = this_organization.legacy_owners_team

    render(
      "orgs/teams/owners_team",
      locals: { organization: this_organization, team: legacy_owners_team },
      layout: "application")
  end

  def rename_owners_team # rubocop:todo GitHub/UseRestfulActions
    if legacy_owners_team = this_organization.legacy_owners_team
      legacy_owners_team.name = params[:name]

      unless legacy_owners_team.save
        flash.now[:error] = legacy_owners_team.errors.full_messages.to_sentence
        return render "orgs/teams/index"
      end

      redirect_to team_path(legacy_owners_team)
    else
      render_404
    end
  end

  def destroy_owners_team # rubocop:todo GitHub/UseRestfulActions
    if legacy_owners_team = this_organization.legacy_owners_team
      DestroyTeamJob.perform_later(legacy_owners_team.id)

      this_organization.update_attribute(:destroy_owners_team_attempted_at, Time.now)
      GitHub.dogstats.increment("team", tags: ["action:destroy", "type:organization_legacy_owners"])

      flash[:notice] = "Deleting the Owners team. This may take a few minutes to complete."
    end

    redirect_to teams_path(this_organization)
  end

  def migrate_legacy_admin_team # rubocop:todo GitHub/UseRestfulActions
    this_team.migrate_legacy_admin
    flash[:notice] = "You've successfully migrated the team."

    redirect_to team_path(this_team)
  end

  PARENT_SUMMARY_REPOSITORY_LIMIT = 30

  def important_changes_summary # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    new_parent_has_all_repo_role = false

    if params[:parent_team].present?
      if new_parent = Team.with_org_name_and_slug(org_login_param, params[:parent_team])
        roles = new_parent.action_or_role_over_repositories(PARENT_SUMMARY_REPOSITORY_LIMIT)
        repo_ids = roles.keys

        # This only checks if the parent has direct abilities to some repos.
        repos = new_parent.visible_repositories_for(current_user)

        # Check if the team has an all repo role assigned:
        new_parent_has_all_repo_role = this_organization.all_repo_role_for_actor("Team", new_parent.id).any?

        total_repo_count = repos.count
        repositories = repos
          .filter  { |r| repo_ids.index(r.id) }
          .sort_by { |r| repo_ids.index(r.id) }
      end
    end

    visibility_changed = params[:visibility_changed] == "true"
    parent_changed = params[:parent_changed] == "true"

    respond_to do |format|
      format.html do
        render "orgs/teams/important_changes_summary", layout: false, locals: {
          edit_team_form: params[:edit_team].present?,
          new_parent: new_parent,
          repositories: repositories,
          roles: roles,
          total_repo_count: total_repo_count,
          visibility_changed: visibility_changed,
          parent_changed: parent_changed,
          new_parent_has_all_repo_role: new_parent_has_all_repo_role,
        }
      end
    end
  end

  def teams_toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "orgs/teams/teams_toolbar_actions",
          locals: {
            view: create_view_model(Orgs::Teams::ToolbarActionsView,
              organization: this_organization,
              destroy_teams_path: org_destroy_teams_path(this_organization),
              adminable_by_user: this_organization.adminable_by?(current_user),
              selected_teams: this_organization.teams.where(slug: params[:team_slugs] || [])
            )
          }
      end
    end
  end

  def team_teams_toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "orgs/teams/teams_toolbar_actions",
          locals: {
            view: create_view_model(Orgs::Teams::ToolbarActionsView,
              organization: this_organization,
              destroy_teams_path: destroy_team_teams_path(this_team),
              adminable_by_user: this_team.adminable_by?(current_user),
              selected_teams: this_organization.teams.where(slug: params[:team_slugs] || []),
              is_child_team: true
            )
          }
      end
    end
  end

  def members_toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "orgs/teams/members_toolbar_actions", locals: {
          this_team: this_team,
          selected_team_members: this_team.members.where(login: params[:member_logins] || []),
        }
      end
    end
  end

  def repositories_toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    viewer_can_administer_repos = supports_business_teams? ? this_team.can_add_repositories?(current_user) : this_team.adminable_by?(current_user)
    return render_404 unless viewer_can_administer_repos

    repository_names = Array.wrap(params[:repository_names])
    repositories = this_team.repositories_scope(affiliation: :immediate).where(name: repository_names)

    respond_to do |format|
      format.html do
        render partial: "orgs/teams/repositories_toolbar_actions", locals: {
          team_name: this_team.name,
          viewer_can_administer: viewer_can_administer_repos,
          selected_repository_names: repository_names,
          selected_repositories: repositories,
        }
      end
    end
  end

  # The maximum number of ancestors to select for a given team when rendering a
  # team's breadcrumb hierarchy. Chosen based [platform data's nested team
  # ADR][1] but should be revised for usability and/or performance reasons
  # based on real-world usage.
  #
  # [1]: https://github.com/github/platform-data/blob/88d91bd670c843e2c3bb213ad7b95918e7fe0fc1/docs/abilities/adr_nested_teams.md#path-encoding
  TEAM_BREADCRUMBS_MAX_DEPTH = 85

  def team_breadcrumbs # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_organization.direct_member?(current_user)
    ancestors = this_team.ancestors.limit(TEAM_BREADCRUMBS_MAX_DEPTH + 1)
    ancestor_count = ancestors.count

    if ancestor_count > TEAM_BREADCRUMBS_MAX_DEPTH
      GitHub.dogstats.increment "team.breadcrumb_exceeding_max_depth"
      GitHub.logger.info(
        "Team breadcrumb navigation cannot render full navigation links.",
        "gh.catalog_service": "github/teams",
        "gh.org": this_organization,
        "gh.team.id": this_team.id,
        "gh.team.ancestor_count": ancestor_count,
      )
    end

    respond_to do |format|
      format.html do
        render partial: "orgs/teams/team_breadcrumbs", locals: { ancestors: ancestors }
      end
    end
  end

  def migrate_discussions # rubocop:todo GitHub/UseRestfulActions
    unless repository = Repository.find_by(id: params[:repo_id].to_i)
      return redirect_to :back, flash: { error: "Repository not found" }
    end

    if repository.owner != this_team.organization || !repository.readable_by?(current_user)
      return redirect_to :back, flash: { error: "Repository not found" }
    end

    unless repository.discussions_active?
      if repository.can_toggle_discussions_setting?(current_user)
        repository.turn_on_discussions(actor: current_user)
      else
        return redirect_to :back, flash: { error: "Discussions are not enabled for this repository" }
      end
    end

    if incompatable_team_post_category_exists?(repository)
      return redirect_to :back, flash: { error: "An incompatible \"Team Posts\" discussions category already exists for the repository selected. Ensure it does not support Announcements, Polls, or Question/Answer formats and try again." }
    end

    private_posts = params[:include_private_posts] == "1"

    this_team.repository_id = repository.id
    this_team.migration_complete = false
    this_team.private_posts_migrated = private_posts

    if this_team.save
      ConvertTeamDiscussionsToDiscussionsJob.perform_later(
        actor: current_user,
        team: this_team,
        repository: repository,
        include_private: private_posts
      )

      GlobalInstrumenter.instrument "team.migrate_team_discussions_submitted", actor: current_user, team: this_team, repository: repository, include_private: private_posts
    else
      return redirect_to :back, flash: { error: "Unable to migrate posts to new repository" }
    end

    redirect_to discussions_path(user_id: repository.owner_display_login, repository: repository.name), flash: { notice: "Team posts are now being transferred, this may take a couple minutes" }
  end

  private

  TEAM_PAGE_SIZE = 20

  def team_params
    return ActionController::Parameters.new if params[:team].blank?

    params.require(:team).permit %i[
      name
      description
      permission
      ldap_dn
      privacy
      notification_setting
      parent_team_id
      parent_team_name
    ].concat [group_mappings: {}, external_group_team: {}]
  end

  def paginated_teams(teams)
    total_entries = teams.size

    teams = teams.paginate(
      page: params[:page] || 1,
      per_page: TEAM_PAGE_SIZE,
    )

    if supports_business_teams?
      BusinessTeam.set_organization_context_for_business_teams(teams, this_organization)
    end

    collection = WillPaginate::Collection.create(params[:page] || 1, TEAM_PAGE_SIZE) do |pager|
      pager.replace(teams)
      pager.total_entries = total_entries
    end
  end

  # Internal: Differentiate XHR requests for LDAP Group import.
  def ldap_group_import?
    return false unless GitHub.ldap_sync_enabled?
    request.headers["X-Context"] == "import"
  end

  def privacy_text(privacy)
    privacy == :closed ? "visible" : "secret"
  end

  def mask_analytics_data
    url = if this_team
      "/orgs/<org-login>/teams/<team-name>/#{action_name}"
    else
      "/orgs/<org-login>/teams/#{action_name}"
    end
    override_analytics_location url
    strip_analytics_query_string
  end

  def create_team_change_parent_request(child_team, parent_team)
    success, error = child_team.can_be_child_of?(parent_team)
    return [false, error] unless success

    request = ::TeamChangeParentRequest.create_initiated_by_parent!(
      parent_team: parent_team,
      child_team: child_team,
      requester: current_user,
    )

    [true, nil]

  rescue ActiveRecord::RecordInvalid => e
    [false, e.message]
  end

  def cancel_team_change_parent_request(request)
    request.cancel(actor: current_user)
    true
  rescue ::TeamChangeParentRequest::AlreadyApprovedError
    false
  end

  def render_teams_new_with_error(error_message, attributes)
    if request.xhr? && ldap_group_import?
      render status: 422, plain: error_message
      return
    end

    @organization = this_organization

    flash.now[:error] = error_message

    attributes["parentTeam"] = { "id" => attributes[:parent_team_id], "name" => attributes[:parent_team_name] }
    render "orgs/teams/new", locals: { team_params: attributes }
  end

  def transform_team_sync_mapping_inputs(attrs)
    return if !params.key?(:manage_group_mappings) && attrs.blank?
    return [] if params.key?(:manage_group_mappings) && attrs.blank?

    attrs.to_h.map do |group_id, attrs|
      {
        group_id: group_id,
        group_name: attrs[:name],
        group_description: attrs[:description],
      }
    end
  end

  def transform_scim_group_mapping_inputs(attrs)
    return if !params.key?(:manage_external_group) && attrs.blank?
    return [] if params.key?(:manage_external_group) && attrs.blank?

    if GitHub.flipper[:primer_experimental_selectpanel_external_identities].enabled?(current_user) && GitHub.flipper[:primer_select_panel_use_experimental_non_local_form].enabled?(current_user)
      attrs.to_h.each_with_object([]) do |(group_id, attrs), memo|
        if group_id != "-1"
          memo << {
            group_id: group_id,
            group_name: attrs[:display_name],
            group_description: attrs[:external_id],
          }
        end
      end
    else
      attrs.to_h.map do |group_id, attrs|
        {
          group_id: group_id,
          group_name: attrs[:display_name],
          group_description: attrs[:external_id],
        }
      end
    end
  end

  def incompatable_team_post_category_exists?(repository)
    existing_category = repository.discussion_categories.find_by(slug: DiscussionCategory::COMPATIBLE_EXISTING_TEAM_POST_MIGRATION_CATEGORY[:slug])
    existing_category.present? && !existing_category.compatible_for_team_posts_transfer?
  end

  def admin_on_team_or_organization_team_creation_enabled
    # if org-level policy allows team creation for this user, return.
    if this_organization.can_create_team?(current_user)
      return
    end

    # if not, check whether the user is a maintainer of that team.
    if this_team&.adminable_by?(current_user)
      return
    end

    render_404
  end

  sig { override.returns(T::Boolean) }
  memoize def supports_business_teams?
    !!this_organization.business&.erp_feature_enabled?(:enterprise_teams_org_assignment)
  end
end
