# typed: strict
# frozen_string_literal: true

class EnterpriseTeamsController < Businesses::BusinessController
  include BusinessTeamHandlers
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create, :update, :destroy]

  include GitHub::Memoizer
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    only: [:index, :new, :edit]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :new, :edit], optional: true

  before_action :enterprise_teams_enabled_required
  before_action :business_owner_required, except: [:index]
  before_action only: [:index] do
    T.bind(self, Businesses::Concerns::BusinessAccess)
    business_access_required(allow_members: true)
  end
  before_action :validate_param_team_name, only: [:create, :update]
  before_action :validate_param_idp_group, only: [:create, :update]
  # TODO: Authorization validation on create / destroy routes

  sig { void }
  def index
    if BusinessTeam.enabled_for_enterprise?(business: this_business)
      business_teams_index(current_business: this_business)
    else
      enterprise_teams_index
    end
  end

  sig { void }
  def new
    if BusinessTeam.enabled_for_enterprise?(business: this_business)
      business_teams_new(current_business: this_business)
    else
      enterprise_teams_new
    end
  end

  sig { void }
  def create
    if BusinessTeam.enabled_for_enterprise?(business: this_business)
      business_teams_create(current_business: this_business)
    else
      enterprise_teams_create
    end
  end

  sig { void }
  def edit
    if BusinessTeam.enabled_for_enterprise?(business: this_business)
      business_teams_edit(current_business: this_business)
    else
      enterprise_teams_edit
    end
  end

  sig { void }
  def update
    if BusinessTeam.enabled_for_enterprise?(business: this_business)
      business_teams_update(current_business: this_business)
    else
      enterprise_teams_update
    end
  end

  sig { void }
  def destroy
    if BusinessTeam.enabled_for_enterprise?(business: this_business)
      business_teams_destroy(current_business: this_business, team_slugs: params[:team_slugs])
    else
      enterprise_teams_destroy
    end
  end

  sig { void }
  def check_name # rubocop:todo GitHub/UseRestfulActions
    render_404 unless BusinessTeam.enabled_for_enterprise?(business: this_business)
    name = params[:teamName]
    old_team_slug = params[:teamOldSlug]
    business_team_name_check(name, old_team_slug)
  end

  private

  sig { void }
  def enterprise_teams_index
    if params[:query].present?
      query = ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)
      enterprise_teams = this_business
        .enterprise_teams
        .where("name like ?", "%#{query}%")
        .paginate(page: params[:page], per_page: 20)
    else
      enterprise_teams = this_business.enterprise_teams.paginate(page: params[:page], per_page: 20)
    end

    enterprise_team_list = enterprise_teams.map do |enterprise_team|
      {
        name: enterprise_team.name,
        id: enterprise_team.id,
        members: enterprise_team.member_count,
        slug: enterprise_team.slug,
        external_group_id: enterprise_team.enterprise_team_group_mappings&.first&.external_group_id
      }
    end

    is_owner = this_business.owner?(current_user)
    respond_to do |format|
      format.html do
        render "businesses/people/enterprise_teams", locals: {
          enterprise_teams: enterprise_team_list,
          cannot_create_multiple_teams: GitHub.esm_enabled?,
          readonly: !is_owner,
          can_remove_teams: is_owner && !GitHub.esm_enabled?,
          paginated_teams: enterprise_teams,
          search_param: params[:query],
        }
      end
    end
  end

  sig { void }
  def enterprise_teams_new
    if GitHub.esm_enabled? && this_business.enterprise_teams.exists?
      flash[:error] = "A maximum of one enterprise team can be created"
      redirect_to enterprise_teams_path(slug: current_business.slug)
      return
    end

    T.unsafe(self).class.react_bundle_name = "enterprise-team-management"

    render_react_app(
      payload: generate_team_management_payload,
      title: "Create new enterprise team",
      page_data: { sidebar: :people, selected_link: :create_enterprise_teams },
      layout: "react_business"
    )
  end

  sig { void }
  def enterprise_teams_create
    if GitHub.esm_enabled? && this_business.enterprise_teams.exists?
      render(json: {
        data: {
          error: "A maximum of one enterprise team can be created"
          }
        }, status: :forbidden)
      return
    end

    team_name = params[:teamName]
    idp_group_id = params[:idpGroup]

    begin
      is_security_manager = ActiveRecord::Type::Boolean.new.cast(params[:isSecurityManager]) || false
      enterprise_team = EnterpriseTeams::Factory.create_enterprise_team(
        enterprise: current_business,
        team_name: team_name,
        sync_to_organizations: sync_to_organizations.to_s,
        idp_group_id: idp_group_id,
        is_security_manager: is_security_manager)
    rescue ActiveRecord::RecordInvalid => e
      return render(json: { data: { error: e.record.errors.full_messages.to_sentence } }, status: :bad_request)
    end

    GitHub.logger.info("Successfully created enterprise team.",
      "code.namespace" => self.class.name,
      "code.function" => "create_enterprise_team",
      "gh.actor.id" => T.must(current_user).id,
      "gh.business.id" => current_business.id,
      "gh.external_group_id" => idp_group_id,
      "gh.enterprise_team.id" => enterprise_team.id,
      "gh.enterprise_team.group_mapping.id" => enterprise_team.enterprise_team_group_mapping_ids.first
    )

    render(json: {
      data: {
        redirect: enterprise_team_members_path(slug: current_business.slug, team_slug: enterprise_team.slug)
      }
    }, status: :ok)
  end

  sig { void }
  def enterprise_teams_edit
    enterprise_team = current_business.enterprise_teams.
      active.
      find_by(slug: params[:team_slug])
    if !enterprise_team.present?
      render_404
      return
    end

    T.unsafe(self).class.react_bundle_name = "enterprise-team-management"

    render_react_app(
      payload: generate_team_management_payload(enterprise_team),
      title: "Edit team",
      page_data: { sidebar: :people, selected_link: :edit_enterprise_teams },
      layout: "react_business"
    )
  end

  sig { void }
  def enterprise_teams_update
    team_name = params[:teamName]
    idp_group_id = params[:idpGroup]

    is_security_manager = ActiveRecord::Type::Boolean.new.cast(params[:isSecurityManager]) || false

    begin
      enterprise_team = EnterpriseTeams::Editor.update_team(
        enterprise: current_business,
        team_slug: params[:team_slug],
        team_name: team_name,
        sync_to_organizations: sync_to_organizations.to_s,
        idp_group_id: params[:idpGroup],
        is_security_manager: is_security_manager
      )
    rescue ActiveRecord::RecordInvalid => e
      return render(json: { data: { error: e.record.errors.full_messages.to_sentence } }, status: :bad_request)
    rescue ActiveRecord::RecordNotFound
      return render(json: { data: { error: "Invalid team to edit." } }, status: :not_found)
    end

    GitHub.logger.info("Successfully updated enterprise team.",
      "code.namespace" => self.class.name,
      "code.function" => "update_enterprise_team",
      "gh.actor.id" => T.must(current_user).id,
      "gh.business.id" => current_business.id,
      "gh.external_group.id" => idp_group_id,
      "gh.enterprise_team.id" => enterprise_team.id,
      "gh.enterprise_team.group_mapping.id" => enterprise_team.enterprise_team_group_mapping_ids.first
    )
    render(json: {
      data: {
        redirect: enterprise_team_members_path(slug: current_business.slug, team_slug: enterprise_team.slug)
      }
    }, status: :ok)
  end

  sig { void }
  def enterprise_teams_destroy
    return render_404 if GitHub.esm_enabled?

    selected_teams = current_business.enterprise_teams.active.where(slug: params[:team_slugs])
    return render(json: { data: { error: "No team found." } }, status: :not_found) unless selected_teams.exists?

    enabled_for_orgs = EnterpriseTeam.enabled_for_organizations?(business: current_business)
    team_ids_to_reconcile = []
    EnterpriseTeam.transaction do
      if enabled_for_orgs
        selected_teams.lock.find_each do |enterprise_team|
          if enterprise_team.enterprise_team_organization_mappings.exists?
            enterprise_team.update!(deleted_at: Time.now)
            team_ids_to_reconcile << enterprise_team.id
          else
            enterprise_team.destroy!
          end
        end
      else
        selected_teams.destroy_all
      end
    end

    team_ids_to_reconcile.each do |enterprise_team_id|
      EnterpriseTeamOrganizationMappingJob.perform_later(enterprise_team_id)
    end

    render(json: { data: { redirect: enterprise_teams_url(current_business) } }, status: :ok)
  end

  sig { returns(Symbol) }
  memoize def sync_to_organizations
    sync_to_organizations = if EnterpriseTeam.enabled_for_organizations?(business: current_business)
      ActiveRecord::Type::Boolean.new.cast(params[:syncToOrganizations]) ? :all : :disabled
    else
      :disabled
    end
  end

  sig { params(enterprise_team: EnterpriseTeam).void }
  def configure_security_manager_sync(enterprise_team:)
    return unless EnterpriseTeam.enabled_for_organization_security_manager?(current_business)

    set_security_manager = ActiveRecord::Type::Boolean.new.cast(params[:isSecurityManager])
    eta = EnterpriseTeamAssignment.where(
      enterprise_team: enterprise_team,
      assignment_type: "security_manager"
    ).first_or_initialize

    if enterprise_team.sync_to_organizations == "all" && set_security_manager
      eta.save!
      SecurityProduct::EnterpriseSecurityManagerRole.grant!(enterprise_team)
    elsif enterprise_team.sync_to_organizations == "disabled" || !set_security_manager
      eta.destroy! unless eta.new_record?
      SecurityProduct::EnterpriseSecurityManagerRole.revoke!(enterprise_team)
    end
  end

  sig { returns(T::Array[ExternalGroup]) }
  def get_business_idp_groups
    # Delete when re-enabling idp groups in GHES
    return [] if EnterpriseTeams::Helper.idp_group_disabled?

    return [] unless this_business.enterprise_managed_user_and_external_provider_enabled? ||
      this_business.enterprise_server_scim_enabled?
    this_business.external_provider.external_groups.not_deleted.includes(:external_identity_group_memberships).to_a
  end

  sig { params(enterprise_team: T.nilable(EnterpriseTeam)).returns(T::Hash[Symbol, T.untyped]) }
  def generate_team_management_payload(enterprise_team = nil)
    can_sync_to_organizations = if enterprise_team.nil?
      EnterpriseTeam.can_sync_to_current_organization_count?(current_business)
    else
      enterprise_team.sync_to_organizations != "disabled" || enterprise_team.can_sync_to_organizations?
    end
    payload = {
      enterpriseSlug: current_business.slug,
      idpGroups: get_business_idp_groups.map do |group|
        {
          id: group.id,
          text: group.display_name,
          member_count: group.members.count
        }
      end,
      idpGroupsDisabled: EnterpriseTeams::Helper.idp_group_disabled?,
      enterpriseManaged: current_business.enterprise_managed_user_and_external_provider_enabled? ||
        this_business.enterprise_server_scim_enabled?,
      enabledForOrganizations: EnterpriseTeam.enabled_for_organizations?(business: current_business),
      enabledForOrganizationSecurityManager: EnterpriseTeam.enabled_for_organization_security_manager?(current_business),
      canSyncToOrganizations: can_sync_to_organizations,
      maxSyncOrgs: EnterpriseTeam.max_sync_organizations,
      maxSyncMembers: EnterpriseTeam.max_sync_members,
    }

    if enterprise_team.present?
      payload[:enterpriseTeam] = {
        name: enterprise_team.name,
        slug: enterprise_team.slug,
      }

      if enterprise_team.enterprise_team_group_mapping_ids.present?
        # Only one ETGM per ET for MVP
        etgm = T.must(enterprise_team.enterprise_team_group_mappings.first)
        payload[:enterpriseTeam][:idpGroup] = {
          id: etgm.external_group&.id,
          text: etgm.external_group&.display_name,
        }
      end

      if EnterpriseTeam.enabled_for_organizations?(business: current_business)
        payload[:enterpriseTeam][:syncToOrganizations] = case enterprise_team.sync_to_organizations
        when "all"
          true
        when "disabled"
          false
        end
      end

      if EnterpriseTeam.enabled_for_organization_security_manager?(current_business)
        payload[:enterpriseTeam][:isSecurityManager] = EnterpriseTeamAssignment.find_by(
          enterprise_team: enterprise_team,
          assignment_type: "security_manager"
        ).present?
      end
    end

    payload
  end

  sig { void }
  def validate_param_team_name
    unless params[:teamName].present?
      render(json: { data: { error: "Name cannot be empty." } }, status: :bad_request)
    end
  end

  sig { void }
  def validate_param_idp_group
    begin
      EnterpriseTeams::Helper.validate_idp_group_enterprise(current_business, params[:idpGroup])
    rescue ArgumentError => e
      render(json: { data: { error: e.message } }, status: :bad_request)
    end
  end

  sig { params(enterprise_team: T.nilable(EnterpriseTeam)).returns(T::Boolean) }
  def unique_name_slug_error?(enterprise_team)
    [
      enterprise_team&.errors&.respond_to?(:added?) &&
        enterprise_team&.errors&.added?(:name, EnterpriseTeam::NAME_SLUG_UNIQUE_BY_BUSINESS_ERROR),
      enterprise_team&.errors&.respond_to?(:added?) &&
        enterprise_team&.errors&.added?(:slug, EnterpriseTeam::NAME_SLUG_UNIQUE_BY_BUSINESS_ERROR)
    ].any?
  end

  sig { void }
  def enterprise_teams_enabled_required
    render_404 unless enterprise_teams_enabled?(current_business) || BusinessTeam.enabled_for_enterprise?(business: current_business)
  end
end
