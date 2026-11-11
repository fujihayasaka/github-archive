# typed: true
# frozen_string_literal: true

class Sponsors::ExploreExportsController < ApplicationController
  include Sponsors::SharedDependenciesControllerMethods

  before_action :sponsors_required
  before_action :login_required
  before_action :require_verified_email

  def create
    ExportSponsorableMaintainersJob.perform_later(
      viewer: current_user,
      sort_by: params[:sort_by],
      org: filter_org,
      ecosystems: ecosystem_filters,
      direct_only: direct_dependencies_only?,
    )
    whose_results = filter_org ? "#{filter_org}'s" : "your"
    flash[:notice] = "We'll email you a CSV file of #{whose_results} Explore Sponsors results soon!"
    redirect_to sponsors_explore_index_path(filter_set.query_args)
  end

  private

  def require_verified_email
    if current_user.no_verified_emails?
      flash[:error] = "You need a verified email address before we can export your Explore Sponsors results."
      redirect_to sponsors_explore_index_path(filter_set.query_args)
    end
  end
end
