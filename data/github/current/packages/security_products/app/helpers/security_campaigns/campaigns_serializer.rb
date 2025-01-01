# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module CampaignsSerializer
    extend T::Helpers
    extend T::Sig

    include UrlHelpers

    sig { params(security_campaign: SecurityCampaign, owner_display_login: String).returns(T::Hash[Symbol, T.untyped]) }
    def serialized_campaign(security_campaign:, owner_display_login:)
      campaign_manager = if security_campaign.manager.present?
        manager = T.must(security_campaign.manager)

        {
          id: manager.id,
          login: manager.display_login,
          avatarUrl: manager.primary_avatar_url,
        }
      end

      {
        name: security_campaign.name,
        description: security_campaign.description,
        endsAt: security_campaign.ends_at,
        manager: campaign_manager,
        createdAt: security_campaign.created_at,
        updatePath: security_center_update_security_campaign_path(org: owner_display_login, number: security_campaign.number),
        deletePath: security_center_destroy_security_campaign_path(org: owner_display_login, number: security_campaign.number),
        closePath: security_center_security_campaign_close_path(org: owner_display_login, number: security_campaign.number),
        reopenPath: security_center_security_campaign_reopen_path(org: owner_display_login, number: security_campaign.number),
      }
    end
  end
end
