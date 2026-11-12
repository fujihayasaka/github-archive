# frozen_string_literal: true

class CampaignsController < InboxController
  def index; end

  def show
    render locals: { campaign: Campaign.find(params[:id]) }
  end

  def new
    render locals: {
      campaign: Campaign.new,
      cve_or_ghsa_ids: "",
    }
  end

  def create
    campaign = Campaign.new(campaign_params)

    begin
      campaign.reviews_from_ids(params[:cve_or_ghsa_ids].split(/\R|\n|,\s|,|\s/).compact_blank)
    rescue ArgumentError => error
      flash.now[:alert] = "Review campaign #{campaign.name} could not be created because it contains the following unknown ids: #{error}!"
      render action: :new, status: :unprocessable_entity, locals: {
        campaign: campaign,
        cve_or_ghsa_ids: params[:cve_or_ghsa_ids],
      }
      return
    end

    if campaign.valid?
      Campaign.transaction do
        campaign.save!
        campaign.advisory_reviews.each do |advisory_review|
          if advisory_review.in_review? || advisory_review.approved_to_publish? || advisory_review.approved_to_withdraw?
            # Do nothing. The advisory review is already in review.
          elsif advisory_review.open?
            advisory_review.start_review!
          elsif advisory_review.may_restart_review?
            advisory_review.restart_review!
          elsif advisory_review.may_revisit?
            advisory_review.revisit!
          end
        end
      end

      redirect_to campaign,
        notice: "Review campaign #{campaign.name} was created successfully!"
    else
      render action: :new, status: :unprocessable_entity, locals: {
        campaign: campaign,
        cve_or_ghsa_ids: params[:cve_or_ghsa_ids],
      }
    end
  end

  def destroy
    campaign = Campaign.find(params[:id])
    name = campaign.name
    campaign.destroy!

    redirect_to campaigns_path,
      notice: "Review campaign #{name} was deleted successfully!"
  end

  private

  def campaign_params
    params.require(:campaign).permit(:name)
  end
end
