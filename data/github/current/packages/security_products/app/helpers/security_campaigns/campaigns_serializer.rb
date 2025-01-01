# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  module CampaignsSerializer
    extend T::Helpers

    include UrlHelpers

    sig { params(security_campaign: SecurityCampaign, owner_display_login: String, current_user: User, visible_teams: T.nilable(T::Array[Team])).returns(T::Hash[Symbol, T.untyped]) }
    def serialized_campaign(security_campaign:, owner_display_login:, current_user:, visible_teams: nil)
      campaign_managers = security_campaign.user_manager_users.compact.map { |user| serialized_campaign_user(user:) }
      current_user_visible_team = visible_teams.nil? ? security_campaign.organization&.visible_teams_for(current_user).to_a : []

      {
        id: security_campaign.id,
        number: security_campaign.number,
        name: security_campaign.name,
        description: security_campaign.description,
        alertType: security_campaign.alert_type,
        endsAt: security_campaign.ends_at,
        closedAt: security_campaign.closed_at,
        managers: campaign_managers,
        teamManagers: filtered_team_managers(security_campaign:, visible_teams: current_user_visible_team),
        contactLink: security_campaign.contact_link,
        createdAt: security_campaign.created_at,
        creationQuery: security_campaign.creation_query,
        publishedAt: security_campaign.published_at,
      }
    end

    sig { params(campaign_with_counts: SecurityCampaigns::CampaignWithCounts, owner_display_login: String, current_user: User, visible_teams: T::Array[Team]).returns(T::Hash[Symbol, T.untyped]) }
    def serialized_campaign_with_counts(campaign_with_counts:, owner_display_login:, current_user:, visible_teams:)
      serialized_campaign(security_campaign: campaign_with_counts.security_campaign, owner_display_login:, current_user:, visible_teams:).merge({
        openCount: campaign_with_counts.open_count,
        closedCount: campaign_with_counts.closed_count,
        openWithLinksCount: campaign_with_counts.open_with_links_count,
      })
    end

    sig { params(user: User).returns(T::Hash[Symbol, T.untyped]) }
    def serialized_campaign_user(user:)
      {
        id: user.id,
        login: user.display_login,
        name: user.profile_name,
        avatarUrl: user.primary_avatar_url,
      }
    end

    sig { params(team: Team).returns(T::Hash[Symbol, T.untyped]) }
    def serialized_campaign_team(team:)
      {
        id: team.id,
        name: team.name,
        slug: team.slug,
        avatarUrl: team.primary_avatar_url,
        organizationLogin: T.must(team.organization).display_login,
      }
    end

    sig { params(security_campaign: SecurityCampaign, visible_teams: T::Array[Team]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def filtered_team_managers(security_campaign:, visible_teams:)
      security_campaign.team_manager_teams.compact.filter_map do |team_manager|
        serialized_campaign_team(team: team_manager) if visible_teams.include?(team_manager)
      end
    end
  end
end
