# typed: true
# frozen_string_literal: true

class ReposPicker::RepositoriesController < ApplicationController
  include ReposPicker::CurrentOrganizationDependency
  include ReposPicker::RepositoriesPayloadDependency

  depends_on_clusters \
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories

  layout false

  before_action :login_required

  MAX_ITEMS = 100
  DEFAULT_SORT = %w(updated desc)

  sig { void }
  def index
    # we cannot run an empty query; this is a quick solution, but we may rather show the user recent repos
    search_query = if params[:q].blank? && current_organization.blank?
      "visibility:public"
    else
      params[:q]
    end

    query = Search::Queries::RepoQuery.new(
      current_user: current_user,
      cap_filter: cap_filter,
      user_session: user_session,
      remote_ip: remote_ip,
      phrase: search_query,
      include_forks: true,
      per_page: MAX_ITEMS,
      page: 1,
      sort: DEFAULT_SORT
    )
    query.qualifiers[:org].clear.must T.must(current_organization).display_login if current_organization

    results = query.execute

    render json: {
      repositories: repositories_payload(results.results.map { |r| r["_model"] }),
      repositoryCount: results.total,
    }
  end
end
