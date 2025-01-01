# typed: true
# frozen_string_literal: true

class CodesearchController < ApplicationController
  # needs investigation for protected organizations
  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction
  before_action :login_required, only: [:index], if: :use_login_required?

  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:index_embeddings, :delete_embeddings]

  after_action :count_muted_search, only: [:index]

  javascript_bundle :search
  stylesheet_bundle :search

  include GitHub::RateLimitedRequest

  rate_limit_requests \
    only: :index,
    if: :codesearch_rate_limit_filter,
    key: :codesearch_rate_limit_key,
    log_key: :codesearch_rate_limit_log_key,
    max: :codesearch_rate_limit_max,
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL,
    at_limit: :codesearch_rate_limit_record

  include ReactHelper
  include BlackbirdControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:refresh_blackbird_caches]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:warm_blackbird_caches]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    only: [:count]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:explore_topics]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def self.react_bundle_name
    "blackbird-search"
  end

  def index
    return render_404 if page > 100

    context_region_title "Search"

    # Redirect to repository search if that's the context they submitted
    if params[:search_target] == "repository"
      repo = Repository.nwo(params[:nwo])
      return render_404 unless repo && repo.pullable_by?(current_user)

      if blackbird_enabled?
        query = "repo:#{repo.name_with_display_owner} #{get_query || ""}"
        if language.present?
          if language.name.include?(" ")
            query << " language:\"#{language.name}\""
          else
            query << " language:#{language.name}"
          end
        end
        return redirect_to search_path(q: query, type: params[:type])
      else
        return redirect_to repo_search_path(repo.owner, repo.name,
          type: params[:type],
          q: get_query,
          ref: params[:ref])
      end
    elsif user = params[:user]
      return redirect_to user_search_path(user, type: params[:type], q: get_query)
    end

    if blackbird_enabled?
      if params[:q]&.present?
        blackbird_search
      else
        add_react_search_feature_flags
        render_react_app(
          payload: {
            type: "home",
            helpUrl: GitHub.help_url,
            logged_in: logged_in?,
            cookie_consent_enabled: @cookie_consent_enabled,
          },
          title: "Search",
          page_data: { container_xl: true, class: "full-width", footer: false },
          ssr: true
        )
      end
      return
    end

    respond_to do |format|
      format.html do
        # we need to track requests to this controller that don't use react to compare to requests that do
        request&.env[GitHub::TaggingHelper::PROCESS_REQUEST_REACT_TYPE] = "rails"

        # for the view
        @language = language
        @search   = sanitized_query
        @state    = params[:state]
        @package_type = params[:package_type]
        @sort     = get_sort
        @order    = get_order
        @unscoped_search = get_unscoped_query

        if @search.present?
          @type = params[:type] = queries.search_type

          # We prevent unauthenticated code type searches using
          # `before_action :login_required` above, but that only works if the
          # type is specified in the params. If it isn't, then the QueryHelper
          # will try to determine the query type based on the qualifiers
          # present in the user query, which is what happens in the line above.
          # (Even if a type param is present, the type could be overridden if
          # it's not a valid value.) If this resolves to `code` for anonymous
          # users then we need to trigger the access_denied response just as
          # `login_required` would have initially.
          return access_denied if !logged_in? && code_query?

          if dotcom_search_in_ghe_enabled? && queries.options.key?(:environment)
            if get_query.include? "environment:github"
              return redirect_to dotcom_search_url(q: @search, type: @type)
            end
          end

          # relies on conditionals applied by logical_service method on base
          push_service_mapping_context

          GitHub.dogstats.increment("search", tags: ["client:mobile"]) if mobile?
          render "codesearch/results", locals: { scope: :global, originating_request_id: request_id }
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
    render "codesearch/advanced_search", locals: { blackbird_enabled: blackbird_enabled? }
  end

  def count # rubocop:todo GitHub/UseRestfulActions
    if code_query? && !logged_in?
      render partial: "codesearch/logged_out_message"
    elsif code_query? && GitHub.flipper[:react_code_search_enabled].enabled?
      render partial: "codesearch/react_enabled_message"
    else
      query = queries.current

      # relies on conditionals applied by logical_service method on base
      push_service_mapping_context

      count = Search::CountView.new(query: query, type: type)
      render html: count.render
    end
  end

  def explore_topics # rubocop:todo GitHub/UseRestfulActions
    query = queries[queries.search_type]
    topic_name = if query.qualifiers.key?(:topic) && query.qualifiers[:topic].must
      query.qualifiers[:topic].must.first
    end
    return head :ok unless topic_name
    return head :not_found unless Topic.valid_name?(topic_name)

    related_topics = Topic.applied_and_related_to(topic_name, limit: 10)

    respond_to do |format|
      format.html do
        render partial: "codesearch/explore_topics",
               locals: { related_topics: related_topics, query_param: query_param(query) }
      end
    end
  end

  # overrides default in ApplicationController to
  # condition on query type resolved in method scope
  def logical_service # rubocop:todo GitHub/UseRestfulActions
    case type
    when Search::Types::CODE
      if GitHub.use_elastomer_code_search?
        "#{GitHub::ServiceMapping::SERVICE_PREFIX}/es_code_search"
      else
        "#{GitHub::ServiceMapping::SERVICE_PREFIX}/blackbird"
      end
    when Search::Types::DISCUSSION
      "#{GitHub::ServiceMapping::SERVICE_PREFIX}/discussions"
    when Search::Types::MARKETPLACE
      "#{GitHub::ServiceMapping::SERVICE_PREFIX}/marketplace"
    when Search::Types::REGISTRY_PACKAGE
      "#{GitHub::ServiceMapping::SERVICE_PREFIX}/package_registry"
    else
      super
    end
  end

  private

  def query_param(query)
    query_parts = []
    if query.qualifiers.key?(:org) && query.qualifiers[:org].must
      query_parts << "org:#{query.qualifiers[:org].must.first}"
    end
    if query.qualifiers.key?(:fork) && query.qualifiers[:fork].must
      query_parts << "fork:#{query.qualifiers[:fork].must.first}"
    end
    query_parts.join(" ")
  end

  def limit_anon_by_ja3?
    !GitHub.enterprise?
  end

  def request_ja3_hash
    request&.env["HTTP_X_SSL_JA3_HASH"]
  end

  # Unauthenticated: 10 searches every minute
  # Authenticated:   30 searches every minute
  def codesearch_rate_limit_max
    logged_in? ? 30 : 10
  end

  def codesearch_rate_limit_filter
    get_query.present?
  end

  def limit_request_by_ja3?
    limit_anon_by_ja3? && !logged_in? && request_ja3_hash.present?
  end

  def codesearch_rate_limit_key
    limiter = if limit_request_by_ja3?
      "#{type}:#{request_ja3_hash}"
    elsif logged_in?
      T.must(current_user).id
    else
      T.must(request).remote_ip
    end
    "search_limiter:#{limiter}"
  end

  def codesearch_rate_limit_log_key
    "search-ratelimited-#{authed_or_anon}"
  end

  def codesearch_rate_limit_record
    controller_name = self.class.to_s.parameterize.gsub("controller", "")
    GitHub.dogstats.increment("search.ratelimited",
                              tags: ["controller:#{controller_name}",
                                     "index:#{index_name}",
                                     "logged_in:#{authed_or_anon}"])
  end

  def index_name
    queries.current.index.name
  end

  def authed_or_anon
    logged_in? ? "auth" : "anon"
  end

  def get_query
    case params[:q]
    when Array;  params[:q].join(" ")
    when String; params[:q]
    end
  end

  def get_unscoped_query
    scope_regex = /(^|\s)(org|user|repo):\S+/
    if get_query.present? && get_query =~ scope_regex
      get_query.split(" ").reject { |word| word =~ scope_regex }.join(" ")
    end
  end

  def get_country
    country = params[:c]
    case country
    when Array
      country.map { |str| str.upcase }
    when String
      country = country.upcase
      if country.include?(",")
        country.split(",")
      else
        country
      end
    else
      "ANY"
    end
  end

  def page
    current_page(:p)
  end

  def per_page
    Search::Query::per_page_default
  end

  def get_sort
    return params[:s] if params[:s].present?

    sort = queries.current.sort
    sort.at(0) if sort.is_a? Array
  end

  def get_order
    if params[:s].present?
      order = params[:o]
      order.present? ? order : "desc"
      order = "desc" unless %w[asc desc].include? order
      order
    else
      sort = queries.current.sort
      sort.at(1) if sort.is_a? Array
    end
  end

  def sort
    [get_sort, get_order] if params[:s].present?
  end

  # Return the type of the query (from CONTENT_TYPES) based on the :type parameter or nil.
  def type
    if blackbird_enabled?
      return client_type_to_type(client_type) || default_type
    end

    return nil if params[:type].blank?

    case params[:type].to_s.downcase
    when "code"
      Search::Types::CODE
    when "commits"
      Search::Types::COMMIT
    when "discussions"
      if !GitHub.discussions_available_on_platform?
        Search::Types::REPOSITORY
      else
        Search::Types::DISCUSSION
      end
    when "issues"
      Search::Types::ISSUE
    when "marketplace"
      if GitHub.marketplace_enabled?
        Search::Types::MARKETPLACE
      else
        Search::Types::REPOSITORY
      end
    when "registrypackages"
      Search::Types::REGISTRY_PACKAGE
    when "users"
      Search::Types::USER
    when "topics"
      Search::Types::TOPIC
    when "wikis"
      Search::Types::WIKI
    else
      default_type
    end
  end

  # The default type when a requested type isn't known or the requested type can't be searched (for example, Marketplace on GHES).
  def default_type
    Search::Types::REPOSITORY
  end

  def queries # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @queries ||= Search::QueryHelper.new(sanitized_query, type,
        current_user: current_user,
        remote_ip: request&.remote_ip,
        aggregations: true,
        highlight: true,
        language: language,
        sort: sort,
        page: page,
        per_page: per_page,
        state: params[:state],
        package_type: params[:package_type],
        user_session: user_session,
        cap_filter: cap_filter,
        request_id: request_id
    )
  end

  def count_muted_search
    if params[:muted]
      GitHub.dogstats.increment "search", tags: ["action:mute"]
    end
  end

  def dotcom_search_in_ghe_enabled?
    GitHub::Connect.unified_search_enabled?
  end

  def code_query?
    type == Search::Types::CODE
  end

  def user_query?
    type == Search::Types::USER
  end

  def use_login_required?
    (code_query? && !GitHub.flipper[:anonymous_search_and_codeview].enabled?) || GitHub.multi_tenant_enterprise?
  end

  def sanitized_query
    if dotcom_search_in_ghe_enabled? && get_query.present?
      get_query.gsub(/\s?environment:\s?(github|local)\s?/, " ").strip
    else
      get_query
    end
  end

  def request_url
    # If this is Blackbird search, the requested URL may be in the format
    # `github.com/search.json?*`` instead of `github.com/search?*``. This replaces
    # the `search.json` with `search` if it exists so we redirect to the right place
    request&.url.gsub("search.json", "search")
  end

  # Opt-in to deferred loading of commit signature badges.
  def defer_commit_badges?
    true
  end
  helper_method :defer_commit_badges?

  # performs non-blackbird search for the blackbird UI
  def legacy_query
    # Copied from CodesearchController.queries

    search_query = params[:expanded_query] || sanitized_query

    helper = Search::QueryHelper.new(search_query, type,
      current_user: current_user,
      remote_ip: request&.remote_ip,
      aggregations: true,
      highlight: true,
      language: language,
      sort: sort,
      page: current_page(:p),
      per_page: Search::Query::per_page_default,
      state: params[:state],
      package_type: params[:package_type],
      user_session: user_session,
      request_id: request_id
    )

    query = helper[type]
    normalize_qualifiers(query)
    results = query&.execute

    [results, query]
  end

  def client_type
    request_type = params[:type].to_s.downcase

    if request_type == Search::ClientTypes::DISCUSSION.downcase && !GitHub.discussions_available_on_platform?
      return Search::ClientTypes::REPOSITORY
    end

    if request_type == Search::ClientTypes::MARKETPLACE && !GitHub.marketplace_enabled?
      return Search::ClientTypes::REPOSITORY
    end

    Search::ClientTypes::ALL.each do |client_type|
      return client_type if client_type.downcase == request_type
    end

    default_type # This is a Search::Type, but each of these is also a Search::ClientType
  end
end
