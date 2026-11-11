# typed: true
# frozen_string_literal: true

class Orgs::OrgRulesRelaxedRenameController < Orgs::Controller
  before_action :org_admins_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

  def update
    if !FeatureFlag.vexi.enabled?(:org_rules_relaxed_rename, current_organization, default: false)
      redirect_to :back
      return
    end

    if %w[0 1].include?(params[:org_rules_relaxed_rename])
      notice = if params[:org_rules_relaxed_rename] == "1"
        current_organization.enable_org_rules_relaxed_rename(actor: current_user)
        "Branch rename settings were updated."
      else
        current_organization.disable_org_rules_relaxed_rename(actor: current_user)
        "Branch rename settings were updated."
      end

      redirect_to :back, notice: notice
    else
      flash[:error] = "Sorry, there was an issue updating branch rename settings."
      redirect_to :back
    end
  end
end
