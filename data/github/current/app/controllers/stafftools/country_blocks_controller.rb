# typed: true
# frozen_string_literal: true

class Stafftools::CountryBlocksController < StafftoolsController
  before_action :dotcom_required
  before_action :ensure_repo_exists

  def create
    country = params["country_block"]
    url = params["country_block_url"]
    reason = params["country_block_reason"]

    if current_repository.access.country_block(
      current_user,
      country,
      url,
      reason,
      tos_reason: params["tos_reason"],
      content_formats: params["content_formats"],
      source: params["source"],
    )
      flash[:notice] = "Country block processed. This may take up to ten minutes to take effect."
    else
      flash[:error] = @current_repository.errors[:base].to_sentence
    end

    redirect_to :back
  end

  def destroy
    country = params["country_block"]

    if !current_repository.access.country_block_setup?(country)
      flash[:notice] = "Given country block not registered"
    elsif current_repository.access.remove_country_block(current_user, country)
      flash[:notice] = "Country block removed. This may take up to ten minutes to take effect."
    else
      flash[:error] = "Failed to remove country block"
    end

    redirect_to :back
  end
end
