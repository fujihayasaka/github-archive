# typed: true
# frozen_string_literal: true

class Repos::SecurityCampaigns::RepositoryCountsController < Repos::SecurityCampaigns::BaseRepositoryController

  before_action :check_code_scanning_read

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::Spokes,
    only: [:index]

  sig { void }
  def index
    response = ActiveRecord::Base.connected_to(role: :reading) do
      all_campaigns = if current_user.feature_enabled?(:security_campaigns_read_without_alerts_limit)
        SecurityCampaigns::SecurityCampaign.open.where(organization_id: current_repository.owner_id).order(:id).to_a
      else
        SecurityCampaigns::SecurityCampaign.open.for_repo_with_alerts(current_repository).order(:id).to_a
      end
      campaigns_with_counts = SecurityCampaigns::CampaignWithCounts.load(security_campaigns: all_campaigns, repo: current_repository, user: current_user)

      params.require(:items).permit!.to_h.transform_values do |item|
        campaign = campaigns_with_counts.find { |sc| sc.number == item[:number].to_i }

        count = if campaign
          campaign.open_count
        else
          # If the requested specified a security campaign that is not visible to them or does not exist,
          # always return 0 (which will hide the count).
          0
        end

        render_to_string Primer::Beta::Counter.new(count: count, limit: 5_000, hide_if_zero: true)
      end
    end

    render json: response
  end
end
