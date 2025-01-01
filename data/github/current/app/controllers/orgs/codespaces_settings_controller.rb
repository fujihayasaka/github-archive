# typed: true
# frozen_string_literal: true

class Orgs::CodespacesSettingsController < Orgs::Controller
  before_action :dotcom_required
  before_action :org_admins_only
  before_action :check_not_legacy_plan
  before_action :check_feature_enabled, except: [:index, :update_codespaces_user_limit, :update_ownership_setting, :suggestions, :grant_access, :revoke_access]

  include ::Codespaces::OrganizationsDependency
  include ReactHelper

  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:update_ownership_setting]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:suggestions]

  def index
    unless org_policy.allow_org_setting? || org_policy.must_contact_support_to_enable? || org_policy.must_upgrade_to_use_codespaces?
      render_404 and return
    end
    render "settings/organization/codespaces/index", locals: {
      users: users_with_access,
      teams: teams_with_access,
      trusted_repositories: current_org_trusted_repositories,
    }
  end

  def update_codespaces_user_limit # rubocop:todo GitHub/UseRestfulActions
    previous_limit = current_organization.organization_codespaces_user_limit
    show_spending_limit_modal = false

    limit = params[:organization][:organization_codespaces_user_limit]

    begin
      result = Codespaces::ProcessOrganizationEnablementChange.new(
        organization: current_organization,
        actor: T.must(current_user),
        enablement: limit,
      ).call

      if should_show_spending_limit_modal?
        # we'll presume it's a spending limit thing
        show_spending_limit_modal = true
      end
    rescue Codespaces::ProcessOrganizationEnablementChange::RevokeFailedError => e
      flash[:error] = "An error occurred when trying to revoke access, please try again later."
    end

    if T.must(request).xhr?
      render partial: "settings/organization/codespaces/index_section",
        locals: {
          users: users_with_access,
          teams: teams_with_access,
          trusted_repositories: current_org_trusted_repositories,
          flash_error: flash_error,
          show_spending_limit_modal: show_spending_limit_modal,
          show_check: true,
        },
        formats: :html
    else
      flash[:notice] = "Codespaces access updated" unless flash[:error].present?
      redirect_to action: "index"
    end
  end

  def update_codespaces_spending_limit # rubocop:todo GitHub/UseRestfulActions
    owner = current_organization_for_member_or_billing

    return render(
      json: {
        error: "Setting the spending limit is not allowed for this organization"
      },
      status: :unprocessable_entity
    ) unless Billing::Budget.configurable?(owner)

    return render(
      json: {
        error: "You can’t increase the spending limits until you set up a valid payment method"
      },
      status: :precondition_failed
    ) unless Codespaces::BillingPolicy.valid_organization_payment_method_configured?(owner)

    budget = owner.budget_for(group: :codespaces)
    budget.configure(
      enforce_spending_limit: enforce_spending_limit?,
      limit: params[:spending_limit],
    )

    return render(
      json: {
        error: budget.errors.full_messages.to_sentence
      },
      status: :unprocessable_entity
    ) if budget.errors.any?


    render(
      json: {
        message: "Spending limit configuration has been updated"
      },
      status: :ok
    )
  end

  def update_trusted_repositories_access # rubocop:todo GitHub/UseRestfulActions
    access = params.dig(:organization, :codespace_trusted_repositories_access)

    begin
      Codespaces::UpdateTrustedRepositoryAccess.call(
        actor: current_user,
        target: current_organization,
        trusted_repo_setting: access,
        repo: params[:repo],
        entry_point: :orgs_codespaces_settings_controller_update_trusted_repositories_access
      )
    rescue Configurable::CodespaceTrustedRepositories::InvalidRepoAccessArgumentError
      flash_error = "Sorry, that trusted repositories setting isn't valid."
    rescue Codespaces::UpdateTrustedRepositoryAccess::RepositoryNotOwned
      flash_error = "Unable to mark the repository as trusted."
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "settings/organization/codespaces/trusted_repositories_access", locals: { show_check: true, flash_error: flash_error, trusted_repositories: current_org_trusted_repositories }, formats: :html
      end
      format.html do
        flash[:error] = flash_error
        redirect_to action: "index"
      end
    end
  end

  def grant_access # rubocop:todo GitHub/UseRestfulActions
    identifier = (params[:identifier] ||= "").strip

    user = current_organization.members.find_by(login: identifier) ||
                    current_organization.outside_collaborators.find_by(login: identifier)

    team = current_organization.teams.find_by(slug: identifier.split("/").last) unless user

    status = :ok

    # 'app/assets/modules/github/orgs/codespaces.ts' only renders response HTML to the DOM for a set of known status codes.
    # If you add a new 'status' value to this controller action action, add it to the 'knownServerStatusCodes' array in 'codespaces.ts' too.
    grantee = user || team
    if grantee.nil?
      flash[:error] = "Could not allow #{identifier} to use Codespaces."
      status = :bad_request
    else
      begin
        Codespaces::OrgPolicy.grant_billing_permission!(grantee, current_organization)
        GlobalInstrumenter.instrument("codespaces.org_enabled", { organization: current_organization })

        if grantee.is_a?(User)
          Codespaces::OrgSettingsChangedJob.perform_later(context: grantee.id, event_type: Codespaces::Events::ORG_CODESPACES_ENABLED_USER, actor_id: T.must(current_user).id)
          current_organization.instrument :codespaces_user_access_allowed, actor: current_user, user:
        elsif grantee.is_a?(Team)
          Codespaces::OrgSettingsChangedJob.perform_later(context: grantee.id, event_type: Codespaces::Events::ORG_CODESPACES_ENABLED_TEAM, actor_id: T.must(current_user).id)
          current_organization.instrument :codespaces_team_access_allowed, actor: current_user, team:
        end
      rescue Codespaces::OrgPolicy::RoleGranterError
        flash[:error] = "An error occurred when trying to grant access, please try again later."
        status = :internal_server_error
      end
    end


    respond_to do |format|
      format.html_fragment do
        render Organizations::Settings::CodespacesUserPermissionsComponent.new(organization: current_organization, users: users_with_access, teams: teams_with_access, flash_error: flash_error), status: status, layout: false, formats: :html
      end
      format.html do
        redirect_to action: "index"
      end
    end
  end

  def revoke_access # rubocop:todo GitHub/UseRestfulActions
    identifier = (params[:identifier] ||= "").strip

    user = users_with_access.find_by(login: identifier)
    team = teams_with_access.find_by(slug: identifier.split("/").last) unless user

    status = :ok

    grantee = user || team
    if grantee.nil?
      flash[:error] = "An error occurred when trying to revoke access for #{identifier}."
      status = :bad_request
    else
      begin
        Codespaces::OrgPolicy.revoke_billing_permission!(grantee, current_organization)
        if grantee.is_a?(User)
          Codespaces::OrgSettingsChangedJob.perform_later(context: grantee.id, event_type: Codespaces::Events::ORG_CODESPACES_DISABLED_USER, actor_id: T.must(current_user).id)
          current_organization.instrument :codespaces_user_access_revoked, actor: current_user, user:
        elsif grantee.is_a?(Team)
          Codespaces::OrgSettingsChangedJob.perform_later(context: grantee.id, event_type: Codespaces::Events::ORG_CODESPACES_DISABLED_TEAM, actor_id: T.must(current_user).id)
          current_organization.instrument :codespaces_team_access_revoked, actor: current_user, team:
        end
      rescue Codespaces::OrgPolicy::RoleGranterError
        flash[:error] = "An error occurred when trying to revoke access, please try again later."
        status = :internal_server_error
      end
    end

    respond_to do |format|
      format.html_fragment do
        render Organizations::Settings::CodespacesUserPermissionsComponent.new(organization: current_organization, users: users_with_access, teams: teams_with_access, flash_error: flash_error), status: status, layout: false, formats: :html
      end
      format.html do
        redirect_to action: "index"
      end
    end
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    headers["Cache-Control"] = "no-cache, no-store"
    respond_to do |format|
      format.html_fragment do
        render partial: "settings/organization/codespaces/suggestions",
          formats: :html,
          locals: {
            view: create_view_model(Orgs::Codespaces::SuggestionsView,
              org_members_only: true,
              include_teams: true,
              organization: current_organization,
              query: params[:q],
              user_logins_with_access: users_with_access.pluck(:display_login),
              team_slugs_with_access: teams_with_access.pluck(:slug),
              include_outside_collaborators: true,
            )
          }
      end
    end
  end

  def update_ownership_setting # rubocop:todo GitHub/UseRestfulActions
    ownership = params.dig(:codespaces_org_ownership_setting)

    begin
      current_organization.update_organization_codespaces_ownership_setting(
        ownership,
        actor: current_user
      )
    rescue ArgumentError => e
      error = e.message
    end

    respond_to do |format|
      format.json do
        if error
          render json: { error: error }, status: :unprocessable_entity
        else
          render json: { success: true }, status: 202
        end
      end
    end
  end

  private

  def check_feature_enabled
    render_404 unless org_policy.allow_org_setting?
  end

  def check_not_legacy_plan
    if current_organization.plan.legacy?
      render_404
    end
  end

  def current_org_trusted_repositories
    current_organization.integration_installations.find_by(integration: Apps::Privileged.integration(:codespaces_production))&.repositories || []
  end

  def enforce_spending_limit?
    return true if ["true", "TRUE", true].include?(params[:enforce_spending_limit])

    false
  end

  def should_show_spending_limit_modal?
    return false if current_organization.organization_codespaces_user_limit == Configurable::OrganizationCodespacesUserLimit::DISABLED
    return false if current_organization.free_codespace_use_enabled?
    return false if Codespaces::AccessChecker.new(current_organization).allowed_by_billing?

    true
  end

  def org_policy # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @org_policy ||= Codespaces::OrgPolicy.new(user: current_user, org: current_organization)
  end

  # When requests originate from JavaScript, JavaScript displays the flash message.
  # Clear `flash[:error]` so Rails doesn’t _also_ display it.
  def flash_error
    error_message = flash[:error]
    flash[:error] = nil
    error_message
  end
end
