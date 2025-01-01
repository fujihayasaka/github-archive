# typed: strict
# frozen_string_literal: true

class Sponsors::ExploreController < ApplicationController
  include ResilienceHelper
  include Sponsors::SharedDependenciesControllerMethods

  # :site bundle dependency should be transitioned to only :explore
  stylesheet_bundle :site
  stylesheet_bundle :explore

  before_action :sponsors_required
  before_action :require_supported_ecosystem
  before_action :require_valid_sort_option

  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index
    context_region_preset :explore

    explore_loader = if logged_in?
      SponsorsExploreLoader.new(filter_set: filter_set, viewer: current_user, org: filter_org)
    end

    respond_to do |format|
      format.html do
        if requesting_sponsorable_dependency_results?
          return head(:bad_request) unless logged_in?

          render partial: "sponsors/explore/sponsorable_dependencies", locals: {
            explore_loader: explore_loader,
            filter_set: filter_set,
            # Only need to override the default if we're not filtering to the viewer's own sponsorable dependencies:
            login_to_sponsor_as: filter_org&.login,
          }
        else
          render "sponsors/explore/index", locals: {
            filter_organizations: filter_organizations,
            explore_loader: explore_loader,
            filter_set: filter_set,
          }
        end
      end
    end
  end

  private

  # Private: Is this request for getting the list of sponsorable dependencies?
  #
  # The initial page load renders the explore page "shell", then we make an async/xhr request to get the results.
  sig { returns T::Boolean }
  def requesting_sponsorable_dependency_results?
    pjax? || request.xhr? || turbo_frame_request?
  end

  sig { void }
  def require_valid_sort_option
    return if params[:sort_by].blank?

    valid_sorts = SponsorsHelper::MAINTAINER_SORT_OPTIONS.keys
    unless valid_sorts.include?(params[:sort_by])
      redirect_to sponsors_explore_index_path(filter_set.with(sort_by: nil).query_args)
    end
  end

  sig { returns T::Array[Organization] }
  memoize def filter_organizations
    return [] unless logged_in?

    orgs = with_database_error_fallback(fallback: []) do
      T.unsafe(Organization).ranked_for(current_user, scope: current_user.member_or_billing_manager_organizations)
        .limit(50).to_a
    end

    # We need to add the currently selected org to the start of the list if it isn't already, so that it shows
    # on the page and isn't hidden in the overflow menu:
    filter_org_index = filter_org ? orgs.index(filter_org) : -1
    filter_org_should_be_moved = filter_org_index &&
      filter_org_index >= Sponsors::Explore::AccountFilterComponent::TOTAL_ORGS_TO_DISPLAY
    orgs.delete_at(filter_org_index) if filter_org_should_be_moved
    if filter_org && (filter_org_should_be_moved || filter_org_index.nil?)
      orgs.unshift(filter_org)
    end

    orgs
  end
end
