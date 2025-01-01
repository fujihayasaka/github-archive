# typed: strict
# frozen_string_literal: true

class Orgs::CopilotSettings::SeatManagementController < Orgs::Controller
  include ApplicationHelper
  include ApplicationController::VerifiedFetchDependency
  include AvatarHelper
  include Copilot::Errors
  include ApplicationController::JsonDependency
  include Site::MicrosoftAnalyticsDependency


  allow_verified_fetch only: [
    :seats,
    :update_copilot_seat_permissions_json,
    :update_copilot_seat_permissions,
    :create_users,
    :destroy,
    :destroy_invitation,
    :create_teams,
    :confirm_csv_users,
    :save_csv_users,
    :destroy_team,
    :bulk_update,
    :generate_csv,
    :generate_activity_csv,
    :create_seats,
    :send_invitation,
    :send_invitations,
  ]

  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_not_legacy_plan
  before_action :check_copilot_available
  before_action :parse_json_params, only: [
    :seats,
    :create_users,
    :create_teams,
    :save_csv_users,
    :bulk_update,
    :update_copilot_seat_permissions_json,
    :create_seats,
    :send_invitation,
    :send_invitations
  ]
  before_action :enable_microsoft_analytics, only: [:index]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:index]
  skip_before_action :cap_pagination, only: [:index, :seats]
  around_action :instrument_permissions_change, only: [:update_copilot_seat_permissions, :update_copilot_seat_permissions_json]

  javascript_bundle :settings
  javascript_bundle :copilot

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index, :suggestions, :team_suggestions]

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-for-business"
  end

  PER_PAGE = 25

  sig { void }
  def index
    organization_id = params[:organization_id]
    seat_assignment_type = :some

    if copilot_organization.seat_management_enabled_for_all?
      show_modal = true
      seat_assignment_type = :all
    elsif copilot_organization.seat_management_disabled?
      show_modal = Copilot::Seat.for_organization(copilot_organization.organization_object).exists?
      seat_assignment_type = :none
    end

    if FeatureFlag.vexi.enabled?(:cfb_package_data_router, current_user, default: false)
      respond_with_react(
        payload: Copilot::Organizations::SeatManagement::Payload.new(organization: this_organization, params: params, current_user: current_user),
        title: "GitHub Copilot",
        layout: "layouts/settings/copilot_org_react",
        app_payload_generator: -> {
          {
            enabled_features: {
              copilot_metrics_access_page_updates: metrics_view_enabled?,
              copilot_access_page_disable_update_on_policy_change: this_organization.feature_flag_enabled?(:copilot_access_page_disable_update_on_policy_change, default: true)
            }
          }
        }
      )
    else
      payload = Copilot::Organizations::SeatManagement::Payload.new(organization: this_organization, params: params, current_user: current_user).call

      render_react_app(
        payload: payload,
        title: "GitHub Copilot",
        layout: "layouts/settings/copilot_org_react",
        disable_ssr: true, # attempts to fix mismatch in date rendering on client and server
        app_payload_generator: -> {
          {
            enabled_features: {
              copilot_metrics_access_page_updates: metrics_view_enabled?,
              copilot_access_page_disable_update_on_policy_change: this_organization.feature_flag_enabled?(:copilot_access_page_disable_update_on_policy_change, default: true)
            }
          }
        }
      )
    end
  end

  sig { void }
  def seats # rubocop:todo GitHub/UseRestfulActions
    render_index_json
  end

  sig { void }
  def create_users # rubocop:todo GitHub/UseRestfulActions
    result = add_users

    if result.error
      render json: { error: result.error }, status: :unprocessable_entity
    else
      render_index_json(status: 201)
    end
  end

  sig { void }
  def create_seats # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        if current_user.feature_flag_enabled?(:copilot_assign_as_selected_members, default: false)
          # I would expect params[:policy] to be enabled_for_selected, if not settings might get into strange state
          if params[:policy] == "enabled_for_selected"
            copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: params[:keep].present?)
          else
            GitHub.logger.info("Invalid seat management setting: #{params[:policy]}, for organization: #{current_organization.id}, user: #{current_user.id}")
            return render json: { error: "Invalid setting" }, status: :unprocessable_entity
          end
        end

        result = add_new_members

        if result.error
          render json: { error: result.error }, status: :unprocessable_entity
        else
          current_organization.reload
          render_index_json(status: 201)
        end
      end
    end
  end

  sig { void }
  def destroy
    user = User.find(params[:user_id])
    copilot_organization.unassign([user], current_user)

    render_index_json
  end

  sig { void }
  def destroy_team # rubocop:todo GitHub/UseRestfulActions
    team = Team.find(params[:team_id])
    copilot_organization.unassign([team], current_user)

    render_index_json
  end

  sig { void }
  def bulk_update # rubocop:todo GitHub/UseRestfulActions
    invitations = []
    if params[:invites].present?
      params[:invites].each do |invite|
        invitations << OrganizationInvitation.find(invite)
      end
    end

    if invitations.any?
      unassign_invitations(invitations)
    end

    users_and_teams = []
    if params[:users]&.filter_map(&:presence).present?
      params[:users].each do |user|
        users_and_teams << User.find(user)
      end
    end

    if params[:teams]&.filter_map(&:presence).present?
      params[:teams].each do |team|
        users_and_teams << Team.find(team)
      end
    end

    if users_and_teams.any?
      copilot_organization.unassign(users_and_teams, current_user)
    end

    render_index_json
  end

  sig { void }
  def destroy_invitation # rubocop:todo GitHub/UseRestfulActions
    invitation = OrganizationInvitation.find(params[:invitation_id])

    unassign_invitations([invitation])

    render_index_json
  end

  sig { void }
  def create_team # rubocop:todo GitHub/UseRestfulActions
    team = Team.find_by(name: params[:team], organization: this_organization)
    if team
      result = copilot_organization.assign([team], current_user)
      if result.error
        error = result.error
      end
    else
      error = "Team not found"
    end

    render_index_json
  end

  sig { void }
  def create_teams # rubocop:todo GitHub/UseRestfulActions
    teams = params[:teams]&.filter_map(&:presence).map do |team|
      org_team = Team.find_by(name: team, organization: this_organization)

      if !org_team
        error = "Team (#{team}) not found"
        render json: { error: error }, status: :unprocessable_entity and return
      else
        org_team
      end
    end

    error = T.let(nil, T.nilable(T::Props::Error))
    teams.each do |team|
      result = copilot_organization.assign([team], current_user)
      if result.error
        error = result.error
      end
    end

    if error
      render json: { error: error }, status: :unprocessable_entity and return
    end
    render_index_json(status: 201)
  end

  sig { void }
  def seat_usage # rubocop:todo GitHub/UseRestfulActions
    render partial: "settings/organization/copilot/seat_usage_details", locals: { carried_over: "🦈", new: "🦈", removed: "🦈" }
  end

  sig { void }
  def suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      view = create_view_model(Copilot::SeatManagement::UserSuggestionsView,
        organization: current_organization,
        team: this_team,
        query: params[:q],
        include_teams: false
      )

      format.html_fragment do
        render partial: "copilot/user_suggestions", formats: :html, locals: { view: view, is_trial: copilot_organization.on_free_trial? }
      end

      format.html do
        render partial: "copilot/user_suggestions", locals: { view: view, is_trial: copilot_organization.on_free_trial? }
      end

      format.json do
        results = {
          users: view.suggestions.map do |result|
            should_include = copilot_organization.on_free_trial? ? view.org_member?(result) : true
            if should_include && result.is_a?(User)
              {
                avatar: avatar_url_for(result, 24),
                display_login: result.display_login,
                profile_name: result.profile_name,
                org_member: view.org_member?(result),
                is_user: true,
              }
            end
          end,
        }
        if results[:users].empty? && User.valid_email?(params[:q]) && !copilot_organization.on_free_trial?
          results[:users] << {
            display_login: params[:q],
            org_member: false,
            is_user: false,
          }
        end

        results[:users].compact!
        render json: results.as_json
      end
    end
  end

  sig { void }
  def team_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render(Copilot::SeatManagement::TeamSuggestionsComponent.new(
          organization: current_organization,
          query: params[:q],
        ), layout: false)
      end

      format.json do
        team_view = Copilot::SeatManagement::TeamSuggestionsComponent.new(
          organization: current_organization,
          query: params[:q],
        )
        results = {
          teams: team_view.teams.map do |team|
            {
              avatar: avatar_url_for(team, 24),
              name: team.name,
              slug: team.combined_slug,
              members_count: team.members_count
            }
          end
        }
        render json: results.as_json
      end

    end
  end

  sig { void }
  def confirm_csv_users #rubocop:todo GitHub/UseRestfulActions
    uploaded_csv = params[:file_csv]

    if uploaded_csv.nil? || uploaded_csv.content_type != "text/csv" || uploaded_csv.size > 2.megabytes
      flash[:error] = "Invalid CSV file"
      head 422 and return
    end

    output = Copilot::SeatManagement::Csv.parse_as_json(current_organization, uploaded_csv)
    render json: { ok: true, users: output }
  end

  sig { void }
  def generate_csv # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment "copilot.seat_management.generate_csv"
    GitHub.logger.info("Generating CSV", "gh.org.id" => current_organization.id, "gh.user.id" => current_user&.id)
    send_data copilot_organization.to_csv, filename: "#{current_organization.display_login.parameterize}-seat-usage-#{Time.current.to_i}.csv"
  end

  sig { void }
  def generate_activity_csv # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment "copilot.seat_management.generate_activity_csv"
    GitHub.logger.info("Generating Activity CSV", "gh.org.id" => current_organization.id, "gh.user.id" => current_user&.id)

    Copilot::ActivityReportJob.perform_later(
      entity_id: current_organization.id,
      entity_type: "organization",
      actor_id: current_user.id,
    )

    render json: { ok: true }, status: 202 and return
  end

  sig { void }
  def save_csv_users #rubocop:todo GitHub/UseRestfulActions
    github_users = params[:github_users] || []
    email_users = params[:email_users] || []

    Copilot::SeatManagement::Csv.save(
      copilot_organization,
      T.cast(github_users, T::Array[String]),
      T.cast(email_users, T::Array[String]),
      T.cast(current_user, ::User),
    )

    render_index_json
  end

  sig { void }
  def update_copilot_seat_permissions # rubocop:todo GitHub/UseRestfulActions
    case params[:copilot_permissions]
    when "disabled"
      copilot_organization.seat_management_disable!(current_user)
    when "enabled_for_all"
      copilot_organization.seat_management_allow_all!(current_user)
      if params[:return_to]
        return safe_redirect_to params[:return_to]
      else
        return redirect_to settings_org_copilot_seat_management_path(current_organization), flash: { notice: "Saved" }
      end
    when "enabled_for_selected"
      copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: params[:keep].present?)
    end

    if params[:return_to]
      return safe_redirect_to params[:return_to]
    end

    redirect_to settings_org_copilot_seat_management_path(current_organization), flash: { notice: "Saved" }
  end

  sig { void }
  def update_copilot_seat_permissions_json # rubocop:todo GitHub/UseRestfulActions
    case params[:copilot_permissions]
    when "disabled"
      copilot_organization.seat_management_disable!(current_user)
      render_index_json
    when "enabled_for_all"
      copilot_organization.seat_management_allow_all!(current_user)
      render_index_json
    when "enabled_for_selected"
      copilot_organization.seat_management_selected_teams_and_users!(keep_assignments: params[:keep].present?)
      render_index_json
    else
      render json: { ok: false }, status: 422
    end
  end

  sig { void }
  def send_invitation # rubocop:todo GitHub/UseRestfulActions
    params[:invitation_ids] = [params[:invitation_id]]
    send_invitations
  end

  sig { void }
  def send_invitations # rubocop:todo GitHub/UseRestfulActions
    invitation_ids = params[:invitation_ids]
    if invitation_ids.present?
      invitations = OrganizationInvitation.where(id: invitation_ids)
      invitations.each do |invitation|
        invitation&.send_invitation_email
      end
    end
    render_index_json
  end


  private

  sig { void }
  def check_not_legacy_plan
    render_404 if current_organization.plan.legacy?
  end

  sig { void }
  def check_copilot_available
    render_404 unless copilot_available?
  end

  sig { returns(T::Boolean) }
  def copilot_available?
    return false unless user = current_user
    return true if copilot_organization.can_enable_org_to_assign_seats?(user)
    return true if copilot_organization.can_request_copilot_from_enterprise?(user)

    copilot_organization.has_copilot_for_business? || copilot_organization.has_trial?
  end

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    T.must_because(current_copilot_organization) { "#org_admins_only ensures non-nil" }
  end

  sig { returns(Copilot::SeatManagement::SeatQuery) }
  def query_params
    query = Copilot::SeatManagement::SeatQuery.new
    if params[:query]
      query.query = params[:query]
    end

    if params[:type]
      query.type = params[:type].to_sym
    end

    if params[:sort]
      case params[:sort]
      when "name_asc"
        query.sort = :sortable_name
        query.direction = :asc
      when "name_desc"
        query.sort = :sortable_name
        query.direction = :desc
      when "use_asc"
        query.sort = :last_activity_at
        query.direction = :asc
      when "use_desc"
        query.sort = :last_activity_at
        query.direction = :desc
      end
    end

    query
  end

  sig { returns(Integer) }
  memoize def page
    (params[:page] || 1).to_i
  end

  sig { returns(GitHub::Result) }
  def add_user
    user = User.find_by_login(params[:user])
    if user
      result = copilot_organization.assign([user], current_user)
    else
      result = copilot_organization.assign([params[:user]], current_user)
    end

    result
  end

  sig { returns(GitHub::Result) }
  def add_users
    persisted_users = User.where(login: params[:users]).index_by(&:display_login)
    users = params[:users].map do |str|
      if persisted_users.key?(str)
        persisted_users[str]
      else
        str
      end
    end
    copilot_organization.assign(users, current_user)
  end

  sig { returns(GitHub::Result) }
  def add_new_members
    persisted_users = User.where(login: params[:users]).index_by(&:display_login)
    users = params[:users].map do |str|
      if persisted_users.key?(str)
        persisted_users[str]
      else
        str
      end
    end

    teams = (params[:teams]&.filter_map(&:presence) || []).inject([]) do |teams, team|
      org_team = Team.find_by(name: team, organization: this_organization)

      if !org_team
        return GitHub::Result.new do
          raise SeatAssignmentError, "Team #{team} does not exist in your organization."
        end
      end

      teams << org_team
      teams
    end

    copilot_organization.assign(teams + users, current_user)
  end

  sig { params(invitations: T::Array[::OrganizationInvitation]).void }
  def unassign_invitations(invitations)
    invitations.each do |invitation|
      copilot_organization.unassign([invitation], current_user)

      # let's make sure there aren't any failed invitations we also need to unassign
      this_organization.failed_invitations.where(email: invitation.email).map do |failed_invite|
        copilot_organization.unassign([failed_invite], current_user)
      end
    end
  end

  sig { params(status: Integer).void }
  def render_index_json(status: 200)
    payload = Copilot::Organizations::SeatManagement::Payload.new(organization: this_organization, params: params, current_user: current_user).call
    render json: payload, status: status
  end

  sig { params(block: T.proc.void).void }
  def instrument_permissions_change(&block)
    old_value = copilot_organization.seat_management_setting
    yield
    new_value = params[:copilot_permissions]

    # this shouldn't be possible because we can only select the value via a dropdown, but let's make sure
    return unless Copilot::Configuration.seat_managements.keys.include?(new_value)

    keep_assignments = if params[:keep].present?
      true
    elsif params[:copilot_permissions] == "enabled_for_selected"
      false
    else
      nil
    end

    Copilot::Instrumenter.instrument_copilot_for_business_seat_management_changed(
      current_user,
      copilot_organization.organization_object,
      old_value,
      new_value,
      keep_assignments: keep_assignments
    )
  end

  sig { returns(T::Boolean) }
  def metrics_view_enabled?
    if FeatureFlag.vexi.enabled?(:enforce_copilot_insights_policy, this_organization, default: false) ||
      FeatureFlag.vexi.enabled?(:enforce_copilot_insights_policy, this_organization.business, default: false) ||
      FeatureFlag.vexi.enabled?(:enforce_copilot_insights_policy, current_user, default: false)
      return false unless copilot_organization.insights_enabled?
    end

    return true if FeatureFlag.vexi.enabled?(:copilot_metrics_access_page_updates, current_user, default: false)
    return true if this_organization.feature_flag_enabled?(:copilot_metrics_access_page_updates, default: false)
    return true if this_organization.business&.feature_flag_enabled?(:copilot_metrics_access_page_updates, default: false)

    false
  end
end
