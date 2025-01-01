# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module CampaignsSerializer
    extend T::Helpers

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
        id: security_campaign.id,
        number: security_campaign.number,
        name: security_campaign.name,
        description: security_campaign.description,
        endsAt: security_campaign.ends_at,
        closedAt: security_campaign.closed_at,
        manager: campaign_manager,
        createdAt: security_campaign.created_at,
        showPath: security_center_security_campaign_path(org: owner_display_login, number: security_campaign.number),
        updatePath: security_center_update_security_campaign_path(org: owner_display_login, number: security_campaign.number),
        deletePath: security_center_destroy_security_campaign_path(org: owner_display_login, number: security_campaign.number),
        closePath: security_center_security_campaign_close_path(org: owner_display_login, number: security_campaign.number),
        reopenPath: security_center_security_campaign_reopen_path(org: owner_display_login, number: security_campaign.number),
      }
    end

    sig { params(campaign_with_counts: SecurityCampaigns::CampaignWithCounts, owner_display_login: String).returns(T::Hash[Symbol, T.untyped]) }
    def serialized_campaign_with_counts(campaign_with_counts:, owner_display_login:)
      serialized_campaign(security_campaign: campaign_with_counts.security_campaign, owner_display_login:).merge({
        openCount: campaign_with_counts.open_count,
        closedCount: campaign_with_counts.closed_count,
        openWithLinksCount: campaign_with_counts.open_with_links_count,
      })
    end
  end
end
