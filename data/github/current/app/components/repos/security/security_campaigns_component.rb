# typed: strict
# frozen_string_literal: true

class Repos::Security::SecurityCampaignsComponent < ApplicationComponent
  sig { params(campaigns_with_counts: T::Array[SecurityCampaigns::CampaignWithCounts], repository: Repository, system_arguments: Primer::SystemArgumentsValue).void }
  def initialize(campaigns_with_counts:, repository:, **system_arguments)
    @campaigns_with_counts = campaigns_with_counts
    @repository = repository
    @system_arguments = system_arguments
  end

  sig { params(campaign: SecurityCampaigns::CampaignWithCounts).returns(String) }
  def days_left_display(campaign)
    now = Time.zone.now
    # If the campaign ends in the current year, we don't want to display the year
    formatted_date = if campaign.security_campaign.ends_at.year == now.year
      campaign.security_campaign.ends_at.strftime("%b %-d")
    else
      campaign.security_campaign.ends_at.strftime("%b %-d, %Y")
    end

    "#{campaign.days_left < 0 ? 'overdue' : 'due'} #{formatted_date}"
  end
end
