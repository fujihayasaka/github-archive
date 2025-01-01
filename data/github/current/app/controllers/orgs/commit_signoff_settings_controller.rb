# typed: true
# frozen_string_literal: true

class Orgs::CommitSignoffSettingsController < Orgs::Controller
  before_action :org_admins_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

  VALID_OPTIONS = %w[
    all-repos
    no-policy
  ]

  def update
    if VALID_OPTIONS.include? params[:policy]
      updated = update_settings(current_organization, params[:policy], current_user)
      flash[:notice] = "Commit signoff settings were updated." if updated
    else
      flash[:error] = "Sorry, there was an issue updating commit signoff settings."
    end

    redirect_to settings_org_repo_defaults_path(current_organization)
  end

  private

  def update_settings(entity, policy, actor)
    case policy
    when "all-repos"
      entity.enable_dco_signoff_for_all(actor: actor)
    when "no-policy"
      entity.reset_dco_signoff_for_all(actor: actor)
    end
  end
end
