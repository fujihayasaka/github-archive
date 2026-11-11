# typed: true
# frozen_string_literal: true

class Api::VscodePrivateMarketplaces < Api::App
  include FeatureFlagHelper

  get "/user/vscode_private_marketplaces", operation_id: :internal do
    @route_owner = "@github/meao"

    control_access :authenticated_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    unless FeatureFlag.vexi.enabled?(:vscode_private_marketplace_setting, current_user, default: false)
      deliver_error!(404)
    end

    marketplaces = get_vscode_marketplaces_for_user(current_user)

    deliver_raw({ vscode_private_marketplaces: marketplaces })
  end

  def get_vscode_marketplaces_for_user(user)
    marketplaces = []

    business_data = user.businesses.pluck(:id, :slug)
    return marketplaces if business_data.empty?

    business_ids = business_data.map(&:first)
    configs = Configuration::Entry.where(
      target_type: "Business",
      target_id: business_ids,
      name: "vscode_private_marketplace_url"
    )
    config_map = configs.index_by(&:target_id)

    business_data.each do |id, slug|
      url = config_map[id]&.value
      next unless url.present?

      marketplaces << {
        url: url,
        owner: {
          login: slug,
          id: id,
          type: "Business"
        }
      }
    end

    marketplaces
  end
end
