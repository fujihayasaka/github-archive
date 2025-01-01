# typed: true
# frozen_string_literal: true

module Api::Serializer::OrganizationCampaignDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::UserDependency }
  requires_ancestor { Api::Serializer::OrganizationsDependency }

  def organization_campaign_hash(data, options = {})
    options = Api::SerializerOptions.from(options)
    current_user = T.let(options[:current_user], User)

    campaign = T.let(data[:campaign], SecurityCampaigns::SecurityCampaign)
    campaign_with_counts = T.let(data[:campaign_with_counts], T.nilable(SecurityCampaigns::CampaignWithCounts))
    current_user_visible_teams = if data.key?(:current_user_visible_teams)
      data[:current_user_visible_teams]
    else
      campaign.organization&.visible_teams_for(current_user).to_a
    end

    GitHub::PrefillAssociations.prefill_batch_method(campaign.team_manager_teams, :parent_team)

    hash = {
      number: campaign.number,
      created_at: time(campaign.created_at),
      updated_at: time(campaign.updated_at),
      description: campaign.description,
      name: campaign.name,
      managers: campaign.user_manager_users.compact.map { |user| simple_user_hash(user, options) },
      team_managers: campaign.team_manager_teams.compact.filter_map { |team| team_hash(team, options) if current_user_visible_teams.include?(team) },
      ends_at: time(campaign.ends_at),
      closed_at: time(campaign.closed_at),
      state: campaign.closed? ? "closed" : "open",
      contact_link: campaign.contact_link,
      published_at: time(campaign.published_at),
    }

    if campaign_with_counts && campaign_with_counts.total_count > 0
      hash[:alert_stats] = {
        open_count: campaign_with_counts.open_count,
        closed_count: campaign_with_counts.closed_count,
        in_progress_count: campaign_with_counts.open_with_links_count,
      }
    end

    hash
  end

  def organization_campaigns_hash(data, options = {})
    options = Api::SerializerOptions.from(options)

    campaigns = T.let(data[:campaigns], T::Array[SecurityCampaigns::SecurityCampaign])
    campaigns_with_counts = T.let(data[:campaigns_with_counts] || [], T::Array[SecurityCampaigns::CampaignWithCounts])
    campaigns_with_counts = T.let(campaigns_with_counts.index_by { |c| c.security_campaign.id }, T::Hash[Integer, SecurityCampaigns::CampaignWithCounts])

    organization = campaigns.first&.organization
    current_user = T.let(options[:current_user], User)
    current_user_visible_teams = organization&.visible_teams_for(current_user).to_a || []

    campaigns.map do |campaign|
      organization_campaign_hash({ campaign: campaign, campaign_with_counts: campaigns_with_counts[T.must(campaign.id)], current_user_visible_teams: }, options)
    end
  end
end
