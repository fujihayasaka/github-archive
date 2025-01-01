# typed: true
# frozen_string_literal: true

# This controller is only reachable in GHES installations.
class DotcomCodesearchController < CodesearchController
  before_action :require_dotcom_connection_enabled
  before_action :ensure_dotcom_search_enabled

  javascript_bundle :search

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  def index
    respond_to do |format|
      format.html do

        return render_404 if page > 100

        # for the view
        @language = language
        @search   = sanitized_query
        @state    = params[:state]
        @package_type = params[:package_type]
        @sort     = get_sort
        @order    = get_order

        if @search.present?
          @type = params[:type] = queries.search_type

          if get_query.include? "environment:local"
            return redirect_to search_url(q: @search)
          end

          GitHub.dogstats.increment("search", tags: ["client:mobile"]) if mobile?
          render "dotcom_codesearch/results", locals: { scope: :global }
        else
          @type = type
          render "codesearch/index"
        end
      end
    end
  end

  private

  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  def queries
    # @queries is used in search results view models and views :/
    @queries ||= Search::QueryHelper.new(
      sanitized_query,
      type,
      current_user: current_user,
      remote_ip: request&.remote_ip,
      page: page,
      per_page: per_page,
      user_session: user_session,
      cap_filter: cap_filter,
    )
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization

  def page
    current_page(:p)
  end
end
