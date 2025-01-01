# typed: true
# frozen_string_literal: true

class Businesses::LinkedAccountsController < Businesses::BusinessController
  before_action :emu_business_required
  before_action :business_owner_required
  before_action :feature_flags_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render "businesses/settings/linked_accounts"
  end

  def update
    if params[:enable_emu_contributions_sharing] == "on"
      this_business.enable_emu_contributions_sharing(actor: current_user)
      flash[:notice] = "Contributions sharing enabled."
    else
      this_business.disable_emu_contributions_sharing(actor: current_user)
      flash[:notice] = "Contributions sharing disabled."
      remove_contribution_sharing_from_users
    end
    redirect_to settings_linked_accounts_enterprise_path(this_business)
  end

  private

  def feature_flags_required
    render_404 unless GitHub.flipper[:enterprise_linked_accounts].enabled?(this_business)
  end

  def remove_contribution_sharing_from_users
    this_business.nullify_shares_contributions_with_user_setting
  end
end
