# typed: true
# frozen_string_literal: true

# This controller is only reachable in GHES installations.
class DotcomCodesearchController < CodesearchController
  before_action :require_dotcom_connection_enabled
  before_action :ensure_dotcom_search_enabled

  javascript_bundle :search

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index, :advanced_search]

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

  def advanced_search # rubocop:todo GitHub/UseRestfulActions
    @language = language
    @search   = sanitized_query
    render "dotcom_codesearch/advanced_search", locals: { blackbird_enabled: blackbird_enabled? }
  end

  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  def queries # rubocop:todo GitHub/UseRestfulActions # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @queries ||= Search::QueryHelper.new(sanitized_query, type,
        current_user: current_user,
        remote_ip: request&.remote_ip,
        page: page,
        per_page: per_page,
        user_session: user_session
    )
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization

  private

  def ensure_dotcom_search_enabled
    render_404 unless GitHub::Connect.unified_search_enabled?
  end

  def page
    current_page(:p)
  end
end
