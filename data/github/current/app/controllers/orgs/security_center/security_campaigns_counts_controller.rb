# typed: strict
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignsCountsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper

  before_action :organization_read_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:index]

  sig { void }
  def index
    response = ActiveRecord::Base.connected_to(role: :reading) do
      allowed_repo_ids, _repo_limit_exceeded = allowed_repo_ids_and_limit_exceeded

      query_service = CodeScanning::AlertQueryService.for_organization(
        user: current_user,
        user_session: user_session,
        organization: this_organization,
        allowed_repository_ids: allowed_repo_ids,
      )

      open_campaigns = SecurityCampaigns::SecurityCampaign.open.where(organization: this_organization).order(:id).to_a
      campaigns_with_counts = SecurityCampaigns::CampaignWithCounts.load(security_campaigns: open_campaigns, query_service:, user: current_user)

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
