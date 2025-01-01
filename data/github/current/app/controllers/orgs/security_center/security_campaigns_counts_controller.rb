# typed: strict
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsCountsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  extend T::Sig

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Repositories,
    only: [:index]

  sig { void }
  def index
    response = ActiveRecord::Base.connected_to(role: :reading) do
      open_campaigns = SecurityCampaigns::SecurityCampaign.open.where(organization: this_organization).order(:id).to_a
      campaigns_with_counts = SecurityCampaigns::CampaignWithCounts.load(open_campaigns)

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

  # Unfortunately this method is overwriten in the AbstractSecurityCenterController. We need the initial
  # implementation and have to call the the abstracts parent controller method to do so.
  sig { returns(T.untyped) }
  def params # rubocop:todo GitHub/UseRestfulActions
    Orgs::Controller.instance_method(:params).bind(self).call
  end
end
