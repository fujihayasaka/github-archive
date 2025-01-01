# typed: true
# frozen_string_literal: true

class Orgs::Settings::Releases::PoliciesController < Orgs::Controller
  before_action :org_admins_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

  def update
    config = Releases::ImmutableOrganizationConfig.new(current_organization)

    if Releases::ImmutableOrganizationConfig::VALUES.include? params[:policy]
      config.set_immutable_releases_policy(params[:policy], actor: current_user)

      # If the policy is set to "none", we have to make sure we unenforce all repositories
      # which may have been previously enforced via the "selected" policy.
      if config.immutable_releases_enabled_for_none?
        config.unenforce_immutable_releases_for_all_repos(actor: current_user)
      end

      flash[:notice] = "Releases settings were updated."
    else
      flash[:error] = "Sorry, there was an issue updating releases settings."
    end

    redirect_to settings_org_repo_defaults_path(current_organization)
  end
end
