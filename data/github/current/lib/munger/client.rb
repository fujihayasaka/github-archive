# typed: false
# frozen_string_literal: true

# This is a client library for the Munger API service,
# which lives in https://github.com/github/munger
module Munger
  class Client
    autoload :DataNavigationDestination, "munger/client/data_navigation_destination"
    autoload :DataTopic, "munger/client/data_topic"
    autoload :DataUnsubscribeSuggestion, "munger/client/data_unsubscribe_suggestion"

    class MungerError < StandardError; end

    TRENDING_PERIOD_MAPPING = {
      daily: "daily",
      weekly: "weekly",
      monthly: "monthly",
    }.freeze

    HOME_PAGE_GLOBE_PAGE_SIZE = 1_000

    TIMEOUT_THRESHOLD = 2

    attr_reader :options, :faraday

    def initialize(host, options = {})
      @options = options.reverse_merge({
        timeout_threshold: TIMEOUT_THRESHOLD,
      })

      @faraday = build_faraday(host)
    end

    # Public: Returns repository recommendations, or nil, for a user. Recommendations are
    # unfiltered, meaning they may contain spammy or private repositories, repositories that no
    # longer exist, and repositories the user has already dismissed.
    #
    # user - a User instance
    # page - which page of results to load; an Integer
    # per_page - how many results to load per page; an Integer
    # fallback - A way to signal if we need to fallback to the non user
    # specific repositotory recommendations
    #
    # Returns an Array of RepositoryRecommendation instances, or nil.
    def repository_recommendations(user, page:, per_page:, fallback: false)
      return unless GitHub.munger_available?

      query = "page=#{page.to_i}&per_page=#{per_page.to_i}"

      url = if fallback
        "/features/jazz_fallback_repository_recommendations?#{query}"
      else
        pagination_query = "paginate_by=recommendations&#{query}"

        "/features/jazz_user_repository_recommendations/#{user.id}?#{pagination_query}"
      end

      response = GitHub.dogstats.distribution_time("repositories.request.repository_recommendations") { get url }
      return [] if response&.status == 404

      json = parse_response(response, user: user)

      if fallback && json && json.is_a?(Array)
        RepositoryRecommendation.recommendations_from_json(user, { "recommendations" => json })
      elsif json && json.key?("recommendations")
        RepositoryRecommendation.recommendations_from_json(user, json)
      end
    end

    # Public: Returns a collection of good first issues, or nil, for
    # a specific repository id.
    #
    # repo_id - a Repository id
    #
    # Returns an Array of JSON objects, or nil.
    def good_first_issues_for_repo_id(repo_id)
      return unless GitHub.munger_available?

      response = GitHub.dogstats.distribution_time("issues.request.multi_good_first_issues") do
        get("/features/first_issues", "repository_id" => [repo_id])
      end

      json = parse_response(response)

      if json.is_a?(Array) && json.first&.key?("issues")
        json.first
      else
        { "issues" => [] }
      end
    end

    # Public: Returns a payload for the Home Page Globe that contains activity
    # about pull requests that were opened and merged recently.
    #
    # More info: https://github.com/github/globe/issues/101
    #
    # Returns an Array of JSON objects, or nil.
    def home_page_globe
      return unless GitHub.munger_available?

      json = []
      page = 1

      loop do
        paged_response = GitHub.dogstats.distribution_time("globe.request.munger") do
          params = { page: page, per_page: HOME_PAGE_GLOBE_PAGE_SIZE }

          get("/features/daily_global_pr", params)
        end

        paged_json = parse_response(paged_response)
        break if paged_json.blank?

        json = json.union(paged_json)
        break if paged_json.length < HOME_PAGE_GLOBE_PAGE_SIZE

        page += 1
      end

      return unless json.present?

      json
    end

    # Public: Returns trending developers, or nil.
    #
    # period - Symbol, [:daily, :weekly, :monthly]
    #
    # page - Int, what page to return in the context of the per_page constraint.
    #
    # per_page - Int, how many results per page should be returned.
    #
    # language_id - Int, return only trending developers with a primary repository for the given
    # language id.
    #
    # sponsorable - Boolean, set to true to only get back developers who can be sponsored.
    #
    # Returns an array of JSON objects with user information
    def trending_developers(period: nil, per_page: nil, page: nil, language_id: nil, sponsorable: nil)
      return unless GitHub.munger_available?

      query_params = trending_query_params(page: page, per_page: per_page, language_id: language_id,
        sponsorable: !!sponsorable)

      period_url_path = if TRENDING_PERIOD_MAPPING[period].present?
        "/#{TRENDING_PERIOD_MAPPING[period]}"
      end

      response = GitHub.dogstats.distribution_time("trending.request.developers") do
        get "/features/trending_developers#{period_url_path}", query_params
      end

      json = parse_response(response)
      return unless json

      if json.is_a?(Hash)
        return unless json.keys.any? { |key| key.in? TRENDING_PERIOD_MAPPING.values }
      elsif json.is_a?(Array)
        return unless json.first&.key?("user_id")
      end

      json
    end

    # Public: Returns trending repositories, or nil.
    #
    # language_id - Int, return only repositories with the given language id
    #
    # page - Int, what page to return in the context of the per_page constraint.
    #
    # per_page - Int, how many results per page should be returned.
    #
    # period - Symbol, [:daily, :weekly, :monthly]
    #
    # spoken_language_code - String, the ISO 639-1 Code, representing the spoken
    # language
    #
    # Returns an array of JSON objects with repository information
    def trending_repositories(
      language_id: nil,
      page: nil,
      per_page: nil,
      period: nil,
      spoken_language_code: nil
    )
      return unless GitHub.munger_available?

      query_params = trending_query_params(page: page, per_page: per_page, language_id: language_id)
      query_params = query_params.merge({ spoken_language_code: spoken_language_code }.compact)

      period_url_path = if TRENDING_PERIOD_MAPPING[period].present?
        "/#{TRENDING_PERIOD_MAPPING[period]}"
      end

      response = GitHub.dogstats.distribution_time("trending.request.repositories") do
        get "/features/trending_repositories#{period_url_path}", query_params
      end

      json = parse_response(response)
      return unless json

      if json.is_a?(Hash)
        return unless json.keys.any? { |key| key.in? TRENDING_PERIOD_MAPPING.values }
      elsif json.is_a?(Array)
        return unless json.first&.key?("repository_id")
      end

      json
    end

    # Public: Returns recommended topics for a specific user id, or nil.
    #
    # user_id - Integer, this is the user id you want to receive topic recommendations
    # back for.
    #
    # Returns an array of JSON objects with topic information containing the following keys:
    #
    # id    - The topic's database id.
    # name  - The topic's name.
    # score - A decimal confidence score of the recommendation, between 0 and 1.
    def topic_recommendations(user_id)
      return unless GitHub.munger_available?

      response = GitHub.dogstats.distribution_time("recommendations.request.topics") do
        get "/features/topic_recommendations/#{user_id}"
      end

      json = parse_response(response)
      return unless json && json.is_a?(Hash)
      return unless json.keys.any? { |key| key == "recommendations" }

      json
    end

    # Public: Returns a flamingo adoption repository information
    #
    # Given a repository, this returns a flamingo adoption information
    # for the repository. It returns nil if the repository is not part of the
    # collection or if an error occurs
    def flamingo_adoption_for_repository(repository)
      return unless GitHub.munger_available?

      response = GitHub.dogstats.distribution_time("topics.request.actions_propensity_repository") do
        get "/features/actions_propensity_repository/#{repository.id}"
      end

      return unless response

      json = parse_response(response)
      return unless json

      json
    end

    # Public: Returns an Array of DataNavigationDestination instances or nil for the given User.
    #
    # Given a User, this returns a list of DataNavigationDestination instances for
    # navigations destinations that the User has recently visited. Returns nil if an error occurs.
    def navigation_destinations(user)
      return unless GitHub.munger_available?

      response = GitHub.dogstats.time("munger_client.users.request.navigation_destinations") do
        get "/features/user_navigation_destinations/#{user.id}"
      end

      json = parse_response(response, user: user)
      return unless json && json.key?("navigation_destinations")

      navigation_destinations = json["navigation_destinations"]
      navigation_destinations.map do |n|
        DataNavigationDestination.new(
          type: n["target_type"],
          id: n["target_id"],
          name: n["target_name"],
          visit_count: n["visit_count"],
          last_visited_at: n["last_visited_at"],
          generated_at: n["generated_at"],
        )
      end
    end

    # Public: Returns a list of notification unsubscribe recommendations for the given user.
    #
    # Returns Array<DataUnsubscribeSuggestion>, or nil if an error occurs.
    def notifications_unsubscribe_suggestions(user)
      return unless GitHub.munger_available?

      response = GitHub.dogstats.distribution_time("munger_client.users.request.notifications_unsubscribe_suggestions") do
        get "/features/unsubscribe_suggestions/#{user.id}", {}, { log_not_found_error: false }
      end

      json = parse_response(response, user: user)
      return unless json && json.key?("candidates")

      unsubscribe_suggestions = json["candidates"]
      unsubscribe_suggestions.map do |suggestion|
        DataUnsubscribeSuggestion.new(
          snapshot_date: json["snapshot_date"],
          user_id: json["user_id"],
          repository_id: suggestion["repository_id"],
          score: suggestion["score"],
          algorithm_version: json["algorithm_version"]
        )
      end
    end

    private

    # Private: Parses a Faraday response body, rescues any parsing errors,
    # and reports the error to Failbot.
    #
    # response - a Faraday::Response object
    # error_metadata - a Hash of metadata that should go to Failbot on error
    #
    # Returns JSON.
    def parse_response(response, **error_metadata)
      return unless response
      GitHub::JSON.parse(response.body)
    rescue Yajl::ParseError => boom
      Failbot.report(boom, error_metadata)
      nil
    end

    def get(path, params = {}, options = {})
      return unless circuit_breaker.allow_request?

      if GitHub.flipper[:munger_client_get_option_defaults].enabled?
        options = options.with_defaults(@options)
      end

      log_not_found_error = options.fetch(:log_not_found_error, true)

      client = faraday

      result = client.get path do |req|
        req.params.update params
        req.options.timeout = options[:timeout_threshold]
        req.options.open_timeout = options[:timeout_threshold]
        req.options.params_encoder = Faraday::FlatParamsEncoder

        if request_id = GitHub.context[:request_id]
          req.headers["X-GitHub-Request-Id"] = request_id
        end
      end

      if result.success? || result.status == 404
        if result.status == 404 && log_not_found_error
          GitHub.logger.info("404 response from Munger",
            "code.namespace" => "Munger::Client",
            "code.function" => "get",
            "gh.munger.client.path" => path
          )
        end

        circuit_breaker.success
        result
      else
        raise MungerError, "Unsuccessful response (#{result.status}) from #{path}."
      end
    rescue MungerError, Faraday::Error => boom
      circuit_breaker.failure
      Failbot.report(boom, app: "github-munger", path: path, params: params)
      nil
    end

    def circuit_breaker
      Resilient::CircuitBreaker.get("munger",
        instrumenter: GitHub,
        sleep_window_seconds:       600,
        request_volume_threshold:   2,
        error_threshold_percentage: 50,
        window_size_in_seconds:     300,
        bucket_size_in_seconds:     30,
      )
    end

    def build_faraday(url)
      options = { url: url }

      Faraday.new(options) do |b|
        b.adapter :excon
      end
    end

    def trending_query_params(page:, per_page:, language_id: nil, sponsorable: nil)
      query_params = { primary_language_id: language_id }
      if page.present? && per_page.present?
        query_params.merge!(page: page, per_page: per_page)
      end
      if GitHub.sponsors_enabled? && !sponsorable.nil?
        query_params[:sponsorable] = sponsorable.to_s
      end
      query_params.compact
    end
  end
end
