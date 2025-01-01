# typed: true
# frozen_string_literal: true

module Porter
  # Accesses an internal API in porter to support the public-facing API in app/api.
  class ApiClient
    include Urls

    MEDIA_TYPE = "application/vnd.porter.v1+json".freeze

    def initialize(current_user:, current_repository:, auth_token: GitHub.porter_internal_api_token, timeout: 1, set_import_started: true, send_import_status: false, site_admin: false)
      @current_user       = current_user
      @current_repository = current_repository
      @auth_token         = auth_token
      @timeout            = timeout
      @set_import_started = set_import_started
      @send_import_status = send_import_status
      @site_admin         = site_admin
    end

    # The last successful (200..299) response.
    attr_reader :last_response

    # Starts an import.
    def start_import(data)
      result_from conn.put(nil, data)
    end

    # Stops an import.
    def stop_import
      result_from conn.delete
    end

    # Queries the state of an import.
    def import_status
      result_from conn.get
    end

    # Queries the list of authors found during this import.
    def authors(params)
      result_from conn.get("authors", params)
    end

    # Sets an author mapping.
    def update_author(author_id, data = {})
      result_from conn.patch("authors/#{author_id}", data)
    end

    # "yes, please use git lfs push to upload my large files"
    # or
    # "no, please do not use git lfs push to upload my large files"
    def set_lfs_preference(data = {})
      result_from conn.patch("lfs", data)
    end

    # Updates an existing import with auth and/or project choice
    def update_import(data = {})
      result_from conn.patch(nil, data)
    end

    # Queries the list of large files found for the import
    def large_files(params)
      result_from conn.get("large_files", params)
    end

    private

    # Extract a data hash from a Faraday::Response.
    def result_from(faraday_response)
      @last_response = faraday_response
      faraday_response.env[:data]
    end

    attr_reader :current_user, :current_repository, :auth_token, :timeout,
      :set_import_started, :send_import_status, :site_admin

    def current_request_id
      GitHub.context[:request_id]
    end

    def conn
      @conn ||= build_faraday
    end

    def build_faraday
      options = {
        url: api_endpoint,
        headers: {
          "Accept" => MEDIA_TYPE,
          "X-GitHub-User-ID" => current_user.id.to_s,
          "X-GitHub-User-Login" => current_user.login.to_s,
          "X-GitHub-User-Site-Admin" => site_admin ? "true" : "false",
          "X-GitHub-Repository-ID" => current_repository.id.to_s,
          "X-GitHub-Push-Permission" => current_repository.pushable_by?(current_user) ? "true" : "false",
          "X-GitHub-Set-Import-Started" => set_import_started ? "true" : "false",
          "X-GitHub-Send-Import-Status" => send_import_status ? "true" : "false",
        },
        request: {
          timeout: timeout,
          open_timeout: 5,
        },
      }
      if token_for_current_user
        options[:headers]["X-GitHub-User-Token"] = token_for_current_user.to_s
      end
      if current_request_id
        options[:headers]["X-GitHub-Request-Id"] = current_request_id.to_s
      end
      Faraday.new(options) do |c|
        c.basic_auth(auth_token, "github")
        c.use ClientRequestLimit
        c.use ErrorRateLimit
        c.use JsonRequest
        c.use ResponseHandler
        c.adapter Faraday.default_adapter
      end
    end

    # Generate a base URL, based on the current repository.
    def api_endpoint
      porter_api_base_url(repository: current_repository)
    end

    # Authenticate the current request.
    def token_for_current_user
      @token_for_current_user ||= Porter::TokenProvider.new(
        application_id: GitHub.porter_app_id,
      ).get_token(current_user)
    end

    class ClientRequestLimit < Faraday::Middleware
      class Error < RuntimeError ; end

      def call(env)
        raise Error if limiter.at_limit?
        @app.call(env)
      end

      private

      def limiter
        @limiter ||= Limiter.new \
          key: "porter:api_client:request_rate",
          tries: 100,
          ttl: 10.seconds
      end
    end

    # Abort requests if the error rate from porter is too high
    class ErrorRateLimit < Faraday::Middleware
      class Error < RuntimeError ; end

      def call(env)
        raise Error if too_many_errors?
        @app.call(env)
      rescue Faraday::TimeoutError
        limiter.incr
        raise
      end

      private

      def too_many_errors?
        limiter.at_limit? no_incr: true
      end

      def limiter
        @limiter ||= Limiter.new \
          key: "porter:api_client:timeout_error_rate",
          tries: 5,
          ttl: 1.minute,
          ban_ttl: 5.minutes
      end
    end

    class Limiter
      include GitHub::RateLimitable

      def initialize(key:, tries:, ttl:, ban_ttl: nil)
        @key = key
        @tries = tries
        @ttl = ttl
        @ban_ttl = ban_ttl
      end

      def at_limit?(no_incr: false)
        options = { max_tries: tries, ttl: ttl, ban_ttl: ban_ttl }
        no_incr ? rate_limit_check(key, options).at_limit? : rate_limit_increment(key, options).at_limit?
      end

      def incr
        rate_limit_increment(key, { ttl: ttl })
      end

      attr_reader :key, :tries, :ttl, :ban_ttl
    end

    # Build the JSON request body for a request.
    class JsonRequest < Faraday::Middleware
      def call(env)
        if body = env[:body]
          env[:body] = GitHub::JSON.encode(body)
          env[:request_headers]["Content-Type"] = "application/json"
        end
        @app.call(env)
      end
    end

    # Faraday middleware that converts the raw response into one that Porter::ApiClient's callers can use.
    class ResponseHandler < Faraday::Response::Middleware
      # Parse :body into :data.
      # Raise if :status is not 2xx.
      def on_complete(response)
        parse(response)
        if error = error_from(response)
          raise error
        end
      end

      private

      # Return an error object if status is not 2xx.
      def error_from(response)
        status  = response[:status].to_i
        if status < 200 || status >= 300
          Error.new(response)
        end
      end

      # Parse :body, if present and json, and store in :data.
      def parse(response)
        if body = response[:body]
          response[:data] = GitHub::JSON.decode(body) rescue nil
        end
      end
    end

    # An error response from the upstream porter server.
    class Error < ::RuntimeError
      def initialize(response)
        @response = response
        super("Porter API Error: #{response[:status]}")
      end

      def status
        @response[:status].to_i
      end

      def public_error_message
        @response[:data] && @response[:data]["message"]
      end
    end
  end
end
