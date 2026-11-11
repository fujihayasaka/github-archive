# typed: true
# frozen_string_literal: true

class Businesses::ValidateVscodePrivateMarketplaceUrlController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :vscode_private_marketplace_setting_required

  def create
    url = params[:value]

    respond_to do |format|
      format.html_fragment do
        return head :ok if url.blank?
        return head :ok if Configurable::VscodePrivateMarketplaceUrl.valid_url?(url)

        render body: Configurable::VscodePrivateMarketplaceUrl::INVALID_URL_ERROR,
          status: :unprocessable_entity,
          content_type: "text/fragment+html"
      end
    end
  end

  private

  def vscode_private_marketplace_setting_required
    render_404 unless FeatureFlag.vexi.enabled?("vscode_private_marketplace_setting", this_business, default: false)
  end
end
