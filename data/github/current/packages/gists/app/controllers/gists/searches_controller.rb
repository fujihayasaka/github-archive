# typed: true
# frozen_string_literal: true

class Gists::SearchesController < Gists::ApplicationController
  before_action :search_query_required, only: :show
  before_action :login_required, except: [:new, :show]
  before_action :require_xhr, only: [:quick]

  helper_method :language, :search_query, :gist_query

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    only: [:quick]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    only: [:show]

  def new
    render "gists/searches/new"
  end

  def show
    return head :not_acceptable if request.xhr?

    results = gist_query.execute
    render "gists/searches/show", locals: { results: results }
  end

  def quick # rubocop:todo GitHub/UseRestfulActions
    results = gist_quicksearch.execute
    gists = results.pluck("_gist")
    owned, starred = gists.partition { |g| g.owner == current_user }

    render "gists/searches/quick", layout: false, locals: { owned: owned, starred: starred }
  end

  private

  def search_query_required
    render "gists/searches/new" unless search_query.present?
  end

  def search_query
    params[:q]
  end

  def current_page
    if params[:p].blank? || !params[:p].respond_to?(:to_i)
      1
    else
      params[:p].to_i.abs
    end
  end

  def sort_field_and_direction
    [
      (params[:sort]      || params[:s] || "created"),
      (params[:direction] || params[:o] || "desc"),
    ]
  end

  memoize def language
    Linguist::Language[params[:l]]
  end

  memoize def gist_query
    Search::Queries::GistQuery.new({
      phrase: search_query,
      current_user: current_user,
      remote_ip: request.remote_ip,
      aggregations: true,
      language: language,
      sort: sort_field_and_direction,
      page: current_page,
      per_page: Search::Query::per_page_default,
    })
  end

  memoize def gist_quicksearch
    Search::Queries::GistQuicksearch.new({
      phrase: search_query,
      current_user: current_user,
      remote_ip: request.remote_ip,
      per_page: Search::Query::per_page_default,
    })
  end
end
