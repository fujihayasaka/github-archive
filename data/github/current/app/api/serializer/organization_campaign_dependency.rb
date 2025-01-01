# typed: true
# frozen_string_literal: true

module Api::Serializer::OrganizationCampaignDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::UserDependency }

  def organization_campaign_hash(data, options = {})
    options = Api::SerializerOptions.from(options)

    campaign = T.let(data[:campaign], SecurityCampaigns::SecurityCampaign)
    campaign_with_counts = T.let(data[:campaign_with_counts], T.nilable(SecurityCampaigns::CampaignWithCounts))

    hash = {
      number: campaign.number,
      created_at: time(campaign.created_at),
      updated_at: time(campaign.updated_at),
      description: campaign.description,
      name: campaign.name,
      managers: [simple_user_hash(campaign.manager, options)],
      ends_at: time(campaign.ends_at),
      closed_at: time(campaign.closed_at),
      state: campaign.closed? ? "closed" : "open",
    }

    if campaign_with_counts && campaign_with_counts.total_count > 0
      hash[:alert_stats] = {
        open_count: campaign_with_counts.open_count,
        closed_count: campaign_with_counts.closed_count,
        in_progress_count: campaign_with_counts.open_with_links_count,
      }
    end

    hash.compact
  end

  def organization_campaigns_hash(data, options = {})
    options = Api::SerializerOptions.from(options)

    campaigns = T.let(data[:campaigns], T::Array[SecurityCampaigns::SecurityCampaign])
    campaigns_with_counts = T.let(data[:campaigns_with_counts] || [], T::Array[SecurityCampaigns::CampaignWithCounts])
    campaigns_with_counts = T.let(campaigns_with_counts.index_by { |c| c.security_campaign.id }, T::Hash[Integer, SecurityCampaigns::CampaignWithCounts])

    campaigns.map do |campaign|
      organization_campaign_hash({ campaign: campaign, campaign_with_counts: campaigns_with_counts[T.must(campaign.id)] }, options)
    end
  end
end
