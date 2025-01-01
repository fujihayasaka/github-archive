# typed: true
# frozen_string_literal: true

class Api::Search < Api::App
  map_to_service :es_code_search, only: ["GET /search/code"] # rubocop:todo GitHub/MapToService
  include Api::RateLimitConfiguration::AnonymousRequestKeyGenerator

  module Helpers
    # Internal: Get the results for the given query, and handle any exceptions.
    #
    # query - The Search::Query to execute.
    #
    # If the search tier reports that the query exceeds the maximum offset, the
    # current API request is immediately halted, and an API response is sent to
    # communicate the problematic input.
    #
    # If the search tier fails during query execution, the exception is reported
    # to Failbot, and an empty Search::Results object is returned.
    #
    # Returns a Search::Results object.
    include Api::App::ErrorDependency

    OPT_IN_TO_JA3_RATE_LIMITING = [
      Search::Types::COMMIT,
      Search::Types::REPOSITORY
    ].freeze

    def results_for(query)
      unless query.valid_query?
        deliver_error! 422,
          errors: [
            api_error(:Search, :q, :invalid, message: query.invalid_reason),
          ],
          documentation_url: "/v3/search/"
      end

      begin
        query.execute
      rescue Search::Query::MaxOffsetError => boom
        deliver_error! 422,
          message: boom.message,
          documentation_url: "/v3/search/"
      rescue StandardError => boom # rubocop:todo Lint/GenericRescue
        failbot(env, exception: boom)
        Search::Results.empty
      end
    end

    def transform_highlights(results)
      results.each do |result|
        ::Search::OffsetHighlighter.transform result["highlight"]
      end
    end

    def sort_expression_for(search_type)
      sort = params[:sort]
      if Api::App::AcceptedSortOrderings.include?(params[:order])
        direction = params[:order]
      else
        direction = "desc"
      end

      return nil if sort.blank?

      return nil unless valid_sort_values_for(search_type).include?(sort)

      [sort, direction]
    end

    def valid_sort_values_for(search_type)
      case search_type
      when :issue_search then ::Search::Queries::IssueQuery::SORT_MAPPINGS.keys
      when :label_search then ::Search::Queries::LabelQuery::SORT_MAPPINGS.keys
      when :repo_search  then ::Search::Queries::RepoQuery::SORT_MAPPINGS.keys
      when :user_search  then ::Search::Queries::UserQuery::SORT_MAPPINGS.keys
      when :code_search  then ::Search::Queries::CodeQuery::SORT_MAPPINGS.keys
      when :commit_search then ::Search::Queries::CommitQuery::SORT_MAPPINGS.keys
      end
    end

    def highlight?
      medias.api_param?("text-match")
    end

    def highlight
      if highlight?
        ::Search::OffsetHighlighter.defaults
      else
        false
      end
    end
  end

  include Helpers

  def rate_limit_configuration
    # use the existing limiter on Enterprise so that customers
    # can configure authenticated and unauthenticated access to
    # search without needing to use the separate limiter
    if GitHub.enterprise?
      return Api::RateLimitConfiguration.for(
        Api::RateLimitConfiguration::SEARCH_FAMILY,
        self,
      )
    end

    if request.path_info == "/search/code"
      if current_integration&.feature_enabled?(:code_search_expanded_ratelimit)
        return Api::RateLimitConfiguration.for(
          Api::RateLimitConfiguration::CODE_SEARCH_EXPANDED_RATELIMIT_FAMILY,
          self
        )
      end

      Api::RateLimitConfiguration.for(
        Api::RateLimitConfiguration::CODE_SEARCH_FAMILY,
        self,
      )
    else
      Api::RateLimitConfiguration.for(
        Api::RateLimitConfiguration::SEARCH_FAMILY,
        self,
      )
    end
  end

  # Internal: Overrides default auth scheme to also support Integration Bearer
  # Assertions (user for public searches from Enterprise)
  def attempt_login
    @current_user = nil
    assertion = Api::IntegrationAssertion.new(env)

    if assertion.valid?
      self.current_integration = assertion.integration
      @current_user = assertion.integration.bot
    else
      super
    end
  end

  before do
    cache_control "no-cache"
    set_vary_header

    if params[:q] && !params[:q].to_s.dup.force_encoding("UTF-8").valid_encoding?
      deliver_error! 422,
        errors: [api_error(:Search, :q, :unprocessable)],
        documentation_url: "/v3/search"
    end

    if !params[:q].present?
      deliver_error! 422,
        errors: [api_error(:Search, :q, :missing)],
        documentation_url: "/v3/search"
    end
  end

  # Setup search rate limiters
  # Do this after the before block so UTF-8 param check takes precedence
  include Search::RateLimitRegistry

  # Order of rate limiters is important
  include Search::Limiters::SearchElapsedTimeRegistryAdapter

  get "/search/users", operation_id: "search/users" do
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    query = ::Search::Queries::UserQuery.new \
      current_enterprise_installation: current_enterprise_installation,
      remote_ip: remote_ip,
      phrase: params[:q],
      source_fields: false,
      sort: sort_expression_for(:user_search),
      page: pagination[:page],
      per_page: pagination[:per_page],
      highlight: highlight,
      normalizer: method(:transform_highlights)

    deliver :user_search_result_hash,
      results_for(query), highlight: highlight?, current_user: current_user
  end

  get "/search/topics", operation_id: "search/topics" do
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    query = ::Search::Queries::TopicQuery.new \
      remote_ip: remote_ip,
      phrase: params[:q],
      source_fields: false,
      page: pagination[:page],
      per_page: pagination[:per_page],
      highlight: highlight,
      normalizer: method(:transform_highlights)

    deliver :topic_search_result_hash, results_for(query), highlight: highlight?
  end

  get "/search/labels", operation_id: "search/labels" do
    deliver_error!(422) unless params[:repository_id].present?

    repo = find_repo!

    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    query = ::Search::Queries::LabelQuery.new \
      remote_ip: remote_ip,
      phrase: params[:q],
      source_fields: false,
      repo_id: repo.id,
      sort: sort_expression_for(:label_search),
      page: pagination[:page],
      per_page: pagination[:per_page],
      highlight: highlight,
      normalizer: method(:transform_highlights)

    deliver :label_search_result_hash, results_for(query), highlight: highlight?
  end

  get "/search/repositories", operation_id: "search/repos" do
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    query = ::Search::Queries::RepoQuery.new \
      current_user: current_user,
      current_enterprise_installation: current_enterprise_installation,
      remote_ip: remote_ip,
      phrase: params[:q],
      source_fields: false,
      sort: sort_expression_for(:repo_search),
      page: pagination[:page],
      per_page: pagination[:per_page],
      highlight: highlight,
      normalizer: method(:transform_highlights)

    deliver :repo_search_result_hash, results_for(query),
      highlight: highlight?
  end

  get "/search/issues", operation_id: "search/issues-and-pull-requests" do
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # NOTE: If highlighting is requested, the response may have an IssueComment in the `text_matches`.
    #       Since `object_type` and `object_url` are extracted from _source[comments], we need
    #       source_fields when highlighting.
    source_fields = highlight? ? [:comments] : false
    query = ::Search::Queries::IssueQuery.new \
      allow_insecure_user_to_server_app_query: false,
      current_user: current_user,
      current_enterprise_installation: current_enterprise_installation,
      remote_ip: remote_ip,
      phrase: params[:q],
      source_fields: source_fields,
      sort: sort_expression_for(:issue_search),
      page: pagination[:page],
      per_page: pagination[:per_page],
      highlight: highlight,
      normalizer: method(:transform_highlights),
      context: "api-issues-search"

    deliver :issue_search_result_hash, results_for(query), highlight: highlight?
  rescue Search::Queries::IssueQuery::InsecureUserToServerAppQuery => error
    deliver_error!(422, message: error.message)
  end

  get "/search/code", operation_id: "search/code" do
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_codesearch_is_enabled!

    deny_anonymous_code_search!

    if GitHub.use_elastomer_code_search?
      results = results_for(code_query)
      deliver :code_search_result_hash, results, highlight: highlight?
    else

      result_limit = 1000
      if logged_in? && (GitHub.flipper[:blackbird_increase_max_result_limit].enabled?(current_user) || current_integration && GitHub.flipper[:blackbird_increase_max_result_limit].enabled?(current_integration))
        result_limit = 5000
      end
      # Disallow searching beyond 5000 results
      max_page = (result_limit / pagination[:per_page].to_f).ceil
      if pagination[:page] > max_page
        deliver_error!(422, message: "Cannot access beyond the first #{result_limit} results")
      end

      # Note: Blackbird uses 0-indexed page numbers
      page = pagination[:page]
      if page > 0
        page -= 1
      end

      actor = ::Search::Blackbird::Client.api_actor(current_user, remote_ip, api_auth.token)

      snippet_options = {
        desired_width: 120,
        high_density_snippet_max_lines: 0,
        format: ::Blackbird::Query::V1::SnippetFormat::SNIPPET_FORMAT_PLAIN_TEXT,
      }
      if logged_in? && GitHub.flipper[:blackbird_dotcom_api_expanded_snippets].enabled?(current_user) || current_integration && GitHub.flipper[:blackbird_dotcom_api_expanded_snippets].enabled?(current_integration)
        snippet_options = {
          desired_width: 120,
          max_total_lines: 64,
          double_snippet_context_lines: 30,
          mode: ::Blackbird::Query::V1::SnippetMode::SNIPPET_MODE_UNIFIED,
          format: ::Blackbird::Query::V1::SnippetFormat::SNIPPET_FORMAT_PLAIN_TEXT,
        }
      end

      request_timeout = GitHub.request_timeout(request.env) - 1
      response = ::Search::Blackbird::Client.legacy_query(current_user,
        actor: actor,
        tenant: ::Search::Blackbird::Client.tenant(GitHub::CurrentTenant.get),
        query: params[:q],
        results_per_page: pagination[:per_page],
        page_number: page,
        document_location_limit: 5,
        request_timeout: Google::Protobuf::Duration.new(seconds: request_timeout),
        snippet_options: snippet_options,
        experiments: experiments,
        context: "api",
      )

      errors = response[:errors]&.filter do |e|
        FATAL_BLACKBIRD_ERRORS.include?(e[:type])
      end
      if errors.present?
        error = errors.first
        message = error[:type].to_s
        message += " " + error[:message] if error[:message].present?
        message += " " + error[:suggestion] if error[:suggestion].present?
        deliver_error!(error[:type] == :ERROR_TYPE_ACTOR_NOT_AUTHORIZED ? 401 : 422, message: message)
      elsif !response[:results].nil?
        repo_ids = response[:results].map { |result| result[:repo_id] }.uniq
        repos = Repository.active.where(id: repo_ids).includes(:owner, :network).index_by(&:id)
        response[:results].each { |result| result[:repo] = repos[result[:repo_id]] }
      end

      if response[:failed]
        if response[:error_message].is_a?(Twirp::Error)
          case response[:error_message].code
          when :resource_exhausted, :invalid_argument, :not_found, :unauthenticated
            code = Twirp::ERROR_CODES_TO_HTTP_STATUS[response[:error_message].code]
            deliver_error!(code, message: response[:error_message].msg)
          when :deadline_exceeded
            deliver_error!(408, message: "This query timed out. Try a simpler query, or try again later")
          end
        end

        Failbot.report(StandardError.new("Blackbird legacy_query failed"), error_message: response[:error_message].to_h)
        deliver_error!(500, message: "internal server error")
      end

      # deliver needs total_count for pagination to work
      response[:total_count] = [response[:result_count], 1000].min
      deliver :blackbird_code_search_result_hash, response, highlight: highlight?
    end
  end

  get "/search/commits", operation_id: "search/commits" do

    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    query = ::Search::Queries::CommitQuery.new \
      current_user: current_user,
      current_enterprise_installation: current_enterprise_installation,
      remote_ip: remote_ip,
      phrase: params[:q],
      sort: sort_expression_for(:commit_search),
      page: pagination[:page],
      per_page: pagination[:per_page],
      highlight: highlight,
      normalizer: method(:transform_highlights)

    results = results_for(query)

    repo_commits = results.map { |result| [result["_source"]["repo_id"], result["_source"]["hash"]] }

    comment_counts = fetch_comment_counts(repo_commits)

    results.zip(comment_counts).each do |result, comment_count|
      result["_comment_count"] = comment_count
    end

    deliver :commit_search_result_hash, results,
      highlight: highlight?
  end

  def rate_limit_verified?
    !current_enterprise_installation.nil?
  end

  def code_query
    return @code_query if defined?(@code_query)
    query_params = {
      current_user: current_user,
      current_enterprise_installation: current_enterprise_installation,
      remote_ip: remote_ip,
      phrase: params[:q],
      sort: sort_expression_for(:code_search),
      page: pagination[:page],
      per_page: pagination[:per_page],
      highlight: highlight,
      normalizer: method(:transform_highlights),
      request_category: "api"
    }
    @code_query = ::Search::Queries::CodeQuery.new(query_params)
  end

  # overrides default in Api::App to
  # condition on query type resolved in method scope
  def logical_service
    if request.path_info == "/search/code"
      if GitHub.use_elastomer_code_search?
        "#{GitHub::ServiceMapping::SERVICE_PREFIX}/es_code_search"
      else
        "#{GitHub::ServiceMapping::SERVICE_PREFIX}/blackbird"
      end
    else
      super
    end
  end

  # Public: Returns the rate limiting key for an anonymous request, or nil if this feature is not enabled.
  # This method is used as a callback in the RateLimitConfiguration to give us more fine-grained control over
  # how searches are rate limited, in order to mitigate abuse without affecting other rate limit families.
  # The ja3 hash is used to more accurately detect bad actors who are spreading their requests
  # across multiple IP addresses (i.e., botnets).
  sig { override.returns(T.nilable(String)) }
  def anonymous_request_key_generator
    ja3_path_aggregate_hash if anon_ja3_rate_limiting_enabled?
  end

  private

  def experiments
    if current_user&.employee?
      begin
        experiments = params[:experiments] || ""
        Hash[experiments.split(",").map { |x| x.split("=") }]
      rescue ArgumentError
        {}
      end
    else
      {}
    end
  end

  # Queries MySQL for the number of comments on each given repo commit.
  #
  # repo_commits - the list of repo commits (e.g. [[3, <oid>], [5, <oid>], ...])
  #
  # Returns the respective comment counts (e.g. [2, 0, ...])
  def fetch_comment_counts(repo_commits)
    return [] if repo_commits == []

    sql = Arel.sql(<<-SQL)
      SELECT repository_id, commit_id, COUNT(*)
      FROM commit_comments
      WHERE
    SQL

    sql += Arel.sql(<<-SQL)
      (
    SQL

    repo_commits.each_with_index do |(repository_id, commit_id), index|
      sql += Arel.sql(" OR ") if index > 0

      sql += Arel.sql(<<-SQL, repository_id: repository_id, commit_id: commit_id)
        (repository_id = :repository_id AND commit_id = :commit_id)
      SQL
    end

    sql += Arel.sql(<<-SQL)
      )
    SQL

    if GitHub.spamminess_check_enabled?
      sql += Arel.sql(<<-SQL)
         AND user_hidden = false
      SQL
    end

    sql += Arel.sql(<<-SQL)
      GROUP BY repository_id, commit_id
    SQL

    count_map = CommitComment.connection.select_rows(sql).map { |repo_id, hash, count| [[repo_id, hash], count] }.to_h

    repo_commits.map { |key| count_map[key] || 0 }
  end

  def ensure_codesearch_is_enabled!
    return if GitHub.enterprise?

    # Code search has been disabled for the current user or the current OAuth app.
    # https://github.com/devtools/feature_flags/disable_codesearch
    if codesearch_disabled?
      deliver_error!(403, message: "Code search is not available at this time.")
    end
  end

  def anonymous_code_search?
    !logged_in? && !current_enterprise_installation
  end

  def deny_anonymous_code_search!
    return if GitHub.enterprise?

    if anonymous_code_search?
      deliver_error! 401,
          errors: [api_error(:Search, :q, :invalid, message: "Must be authenticated to access the code search API")],
          documentation_url: @documentation_url
    end
  end

  # Internal: Determine if code search is disabled for the logged in user or for
  # he current OAuth app.
  #
  # see https://github.com/devtools/feature_flags/disable_codesearch
  #
  # Returns `true` or `false`
  def codesearch_disabled?
    (logged_in? && current_user.codesearch_disabled?) ||
    (current_app_via_oauth && current_app_via_oauth.codesearch_disabled?)
  end

  # Internal: Returns true if the given `query` is a global code search query
  def global_code_search?(query)
    query.valid_query? &&
      query.global?
  end

  def search_type
    case request.path_info
    when "/search/users"
      Search::Types::USER
    when "/search/topics"
      Search::Types::TOPIC
    when "/search/labels"
      Search::Types::LABEL
    when "/search/repositories"
      Search::Types::REPOSITORY
    when "/search/issues"
      Search::Types::ISSUE
    when "/search/code"
      Search::Types::CODE
    when "/search/commits"
      Search::Types::COMMIT
    else
      "UnknownSearchType"
    end
  end

  def code_search?
    search_type == Search::Types::CODE
  end

  sig { returns(T::Boolean) }
  def anon_ja3_rate_limiting_enabled?
    !GitHub.enterprise?
  end

  sig { returns(T::Boolean) }
  def rate_limit_commits_by_ja3?
    # Remove this method when the feature is removed
    GitHub.flipper[:rate_limit_anon_commits_search_by_ja3].enabled?
  end

  # Private: Returns a SHA256 hash of the JA3 fingerprint and the request path.
  # The JA3 hash has a high collission possibility, so we use the path as an additional
  # dimension to reduce the likelihood of collisions for bad actors targeting a specific endpoint.
  sig { returns(T.nilable(String)) }
  def ja3_path_aggregate_hash
    return nil unless OPT_IN_TO_JA3_RATE_LIMITING.include?(search_type)
    if search_type == Search::Types::COMMIT  # Remove this block with :rate_limit_anon_commits_search_by_ja3 flag
      return nil unless rate_limit_commits_by_ja3?
    end
    return nil unless hash = env.fetch("HTTP_X_SSL_JA3_HASH", nil)
    "#{hash}:#{search_type}"
  end

  FATAL_BLACKBIRD_ERRORS = Set[
    :ERROR_TYPE_UNSPECIFIED,
    :ERROR_TYPE_QUERY_PARSING_FATAL,
    :ERROR_TYPE_TIMEOUT,
    :ERROR_TYPE_ACTOR_NOT_AUTHORIZED,
    :ERROR_TYPE_SCOPE_UNSATISFIABLE,
  ]
end
