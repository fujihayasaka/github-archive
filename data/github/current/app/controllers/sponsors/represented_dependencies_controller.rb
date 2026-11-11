# typed: true
# frozen_string_literal: true

class Sponsors::RepresentedDependenciesController < ApplicationController
  include Sponsors::SharedControllerMethods
  include Sponsors::SharedDependenciesControllerMethods

  before_action :login_required
  before_action :sponsors_required
  before_action :sponsorable_required
  before_action :non_waitlisted_sponsors_listing_required
  before_action :non_spammy_user_required
  before_action :require_allowed_filter_org_if_given
  before_action :require_supported_ecosystem

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    only: [:index]

  def index
    return head(:bad_request) unless request.xhr?

    account_filter = filter_org
    account_filter ||= current_user

    explore_loader = SponsorsExploreLoader.new(filter_set: filter_set, viewer: current_user, org: filter_org)
    sponsorable_id = sponsorable&.id
    paginated_repos = if sponsorable_id
      explore_loader.paginated_dependencies_represented_by_sponsorable(sponsorable_id)
    else
      []
    end
    repos_json = paginated_repos.map do |dep|
      {
        id: dep.id,
        name: dep.to_s,
        fullRepoName: dep.name_with_display_owner,
      }
    end

    respond_to do |format|
      format.html do
        render Sponsors::Explore::RepresentedDependencies::ListComponent.new(
          paginated_repositories: paginated_repos,
          potential_sponsor: account_filter,
          sponsorable: sponsorable,
          filter_set: filter_set,
        ), layout: false
      end
      format.json do
        render json: repos_json
      end
    end
  end
end
