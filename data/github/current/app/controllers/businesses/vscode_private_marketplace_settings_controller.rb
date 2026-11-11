# typed: true
# frozen_string_literal: true

class Businesses::VscodePrivateMarketplaceSettingsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :vscode_private_marketplace_setting_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    only: [:show]

  def show
    render "businesses/settings/vscode_private_marketplace", locals: { business: this_business }
  end

  def update
    begin
      url = params[:vscode_private_marketplace_url]

      if url.present?
        this_business.update_vscode_private_marketplace_url(url, actor: current_user)
      else
        # Clear the URL when empty value is submitted
        this_business.reset_vscode_private_marketplace_url(actor: current_user)
      end

      redirect_to settings_vscode_private_marketplace_enterprise_path(this_business),
        notice: "VS Code Marketplace URL has been updated."
    rescue Configurable::VscodePrivateMarketplaceUrl::VscodePrivateMarketplaceUrlError => error
      flash[:error] = error.message
      redirect_to settings_vscode_private_marketplace_enterprise_path(this_business)
    end
  end

  private

  def vscode_private_marketplace_setting_required
    render_404 unless FeatureFlag.vexi.enabled?("vscode_private_marketplace_setting", this_business, default: false)
  end
end
