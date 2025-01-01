# typed: true
# frozen_string_literal: true

class RepositorySearchController < AbstractRepositoryController
  include GitHub::RateLimitedRequest

  after_action :count_muted_search, only: [:index]

  before_action :limit_search_paging

  javascript_bundle :search
  stylesheet_bundle :search

  layout "repository"

  rate_limit_requests \
    only: :index,
    if: :repository_search_rate_limit_filter,
    key: :repository_search_rate_limit_key,
    log_key: :repository_search_rate_limit_log_key,
    max: :repository_search_rate_limit_max,
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL,
    at_limit: :repository_search_rate_limit_record

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:count]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :count], optional: true

  # Search landing page
  def index
    if blackbird_enabled?
      query = "repo:#{current_repository.name_with_display_owner} #{get_query || ""}"
      if language.present?
        if language.name.include?(" ")
          query << " language:\"#{language.name}\""
        else
          query << " language:#{language.name}"
        end
      end
      return redirect_to search_path(q: query, type: params[:type])
    elsif !logged_in? && type == Search::Types::CODE
      return redirect_to_login(request.original_url)
    end

    setup_params
    queries
    strip_analytics_query_string
    push_service_mapping_context

    render "codesearch/results", locals: {
      scope: :repository,
      current_repository: current_repository,
      originating_request_id: request_id
    }
  end

  def count # rubocop:todo GitHub/UseRestfulActions
    if type == Search::Types::CODE && !logged_in?
      return render partial: "codesearch/logged_out_message"
    elsif type == Search::Types::CODE && GitHub.flipper[:react_code_search_enabled].enabled?
      return render partial: "codesearch/react_enabled_message"
    end


    setup_params
    queries
    push_service_mapping_context
    count = Search::CountView.new(query: type_query, type: @type)
    render html: count.render
  end

  # overrides default in ApplicationController to
  # condition on query type resolved in method scope
  def logical_service # rubocop:todo GitHub/UseRestfulActions
    return super if current_repository.nil?

    case type
    when Search::Types::CODE
      if GitHub.use_elastomer_code_search?
        "#{GitHub::ServiceMapping::SERVICE_PREFIX}/es_code_search"
      else
        "#{GitHub::ServiceMapping::SERVICE_PREFIX}/blackbird"
      end
    when Search::Types::DISCUSSION
      "#{GitHub::ServiceMapping::SERVICE_PREFIX}/discussions"
    when Search::Types::REGISTRY_PACKAGE
      "#{GitHub::ServiceMapping::SERVICE_PREFIX}/package_registry"
    else
      super
    end
  end

  private

  # Returns the selected Query whose results are displayed.
  def type_query
    queries[@type]
  end

  def type
    case params[:type].to_s.downcase
    when "issues"
      Search::Types::ISSUE
    when "code"
      Search::Types::CODE
    when "commits"
      Search::Types::COMMIT
    when "discussions"
      if !GitHub.discussions_available_on_platform?
        default_type
      else
        Search::Types::DISCUSSION
      end
    when "registrypackages"
      Search::Types::REGISTRY_PACKAGE
    when "wikis"
      Search::Types::WIKI
    else
      default_type
    end
  end

  def default_type
    if GitHub.use_elastomer_code_search?
      current_repository.code_is_searchable? ? Search::Types::CODE : Search::Types::ISSUE
    else
      Search::Types::ISSUE
    end
  end

  # Determines the language filter from query parameters.
  #
  # Returns a Linguist::Language or nil if no filter is provided.
  def language
    name = params[:l] if params[:l].present?
    name.kind_of?(String) ? Linguist::Language[name] : nil
  end

  def setup_params
    @limit = 10

    @search          = get_query
    @unscoped_search = get_unscoped_query
    @type            = type
    @order           = params[:o].present? ? params[:o] : "desc"
    @sort            = params[:s]
    @language        = language
    @state           = params[:state]

    @order = "desc" unless %w[asc desc].include? @order
    @sort_order = [@sort, @order] if @sort.present?
  end

  def get_query
    case params[:q]
    when Array;  params[:q].join(" ")
    when String; params[:q]
    end
  end

  def get_unscoped_query
    if get_query.present?
      get_query.split(" ").reject { |word| word =~ /(^|\s)(org|user|repo):\S+/ }.join(" ")
    end
  end

  def page # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @page ||= begin
      page = params[:p]
      params[:p] = page.is_a?(String) ? page.to_i : 1
    end
  end

  def blackbird_enabled? # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @blackbird_enabled if instance_variable_defined?(:@blackbird_enabled)

    @blackbird_enabled = (logged_in? || GitHub.flipper[:anonymous_search_and_codeview].enabled?) && GitHub.flipper[:react_code_search_enabled].enabled?
  end

  # see https://github.com/github/github/issues/14818
  class NoRepositoryForSearch < RuntimeError; end

  def queries # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @queries if defined? @queries

    if current_repository.nil?
      raise NoRepositoryForSearch
    end

    # Include explain output when staff bar is open
    include_explain_output = staff_bar_enabled? && site_admin_performance_stats_mode_enabled?
    @queries = Search::QueryHelper.new(@search, @type,
        current_user: current_user,
        remote_ip: request.remote_ip,
        repo_id: current_repository.id,
        search_scope: :standard,
        aggregations: false,
        highlight: true,
        sort: @sort_order,
        page: page,
        per_page: @limit,
        state: @state,
        language: @language,
        include_explain_output: include_explain_output,
        request_id: request_id,
    )
    @queries.issue_query.aggregations = :state
    @queries.code_query.aggregations = :language_id

    @queries
  end

  def count_muted_search
    if params[:muted]
      GitHub.dogstats.increment "search", tags: ["action:mute"]
    end
  end

  def repository_search_rate_limit_max
    logged_in? ? 30 : 10
  end

  def repository_search_rate_limit_filter
    get_query.present?
  end

  def repository_search_rate_limit_key
    "search_limiter:#{logged_in? ? current_user.id : request.remote_ip}"
  end

  def repository_search_rate_limit_log_key
    "search-ratelimited-#{authed_or_anon}"
  end

  def repository_search_rate_limit_record
    controller_name = self.class.to_s.parameterize.gsub("controller", "")
    GitHub.dogstats.increment("search.ratelimited",
                              tags: ["controller:#{controller_name}",
                                     "index:#{index_name}",
                                     "logged_in:#{authed_or_anon}"])
  end

  def index_name
    return "unknown" if current_repository.nil?
    queries.current.index.name
  end

  def authed_or_anon
    logged_in? ? "auth" : "anon"
  end

  def limit_search_paging
    return render_404 if page > 100
  end

  # Override AbstractRepositoryController#defer_commit_badges? to
  # opt-in to deferred loading of commit signature badges.
  def defer_commit_badges?
    true
  end
end
