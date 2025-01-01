# typed: true
# frozen_string_literal: true

class Sponsors::ExploreFundingStatsController < ApplicationController
  include Sponsors::SharedDependenciesControllerMethods

  before_action :sponsors_required
  before_action :login_required
  before_action :require_allowed_filter_org_if_given

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    only: [:index]

  def index
    respond_to do |format|
      format.html do
        render "sponsors/explore_funding_stats/index", locals: {
          direct_dependencies_only: direct_dependencies_only?,
          filter_org: filter_org,
        }, layout: false
      end
    end
  end
end
