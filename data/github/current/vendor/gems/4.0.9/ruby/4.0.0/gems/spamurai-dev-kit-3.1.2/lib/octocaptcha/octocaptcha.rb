require 'net/http'
require 'time'
require 'json'
require 'socket'
require 'uri'
require 'octicons'
require 'lib/stats'
require 'octocaptcha/octocaptcha_url_helpers'

module SpamuraiDevKit
  class Octocaptcha
    include OctocaptchaUrlHelpers

    DEVELOPMENT_FUNCAPTCHA_PRIVATE_KEY="BFE5A88D-E4A3-1CD5-0F97-DF60D07711D9"

    class InvalidConfiguration < Exception; end

    attr_reader :app_name, :feature_name, :stats
    attr_accessor :private_key, :env, :app_url, :use_arkose_V4_api
    attr_accessor :octocaptcha_hmac_secret, :use_octocaptcha_verify_api
    attr_accessor :is_captcha_disabled, :is_captcha_service_disabled
    attr_accessor :use_datadome
    attr_accessor :octocaptcha_uri

    def initialize(app_name, feature_name)
      @app_name = app_name
      @feature_name = feature_name
      yield self if block_given?

      if !@app_name.is_a?(String) || @app_name.empty?
        raise InvalidConfiguration.new("app_name should be the name of your app. ex github")
      end

      if !@feature_name.is_a?(String) || @feature_name.empty?
        raise InvalidConfiguration.new("feature_name should be the name of your feature. ex signup")
      end

      if !["development", "production", "test", "staging"].include?(env)
        raise InvalidConfiguration.new("env should be set to 'development', 'production', or 'test'")
      end

      if is_development_env? || is_test_env?
        self.private_key ||= DEVELOPMENT_FUNCAPTCHA_PRIVATE_KEY
      end

      if !private_key.is_a?(String) || private_key.empty?
        raise InvalidConfiguration.new("private_key should be set")
      end

      if is_captcha_disabled != nil && !is_captcha_disabled.is_a?(Proc)
        raise InvalidConfiguration.new("is_captcha_disabled should be a Proc")
      end

      if is_captcha_service_disabled != nil && !is_captcha_service_disabled.is_a?(Proc)
        raise InvalidConfiguration.new("is_captcha_service_disabled should be a Proc")
      end

      if use_datadome != nil && !use_datadome.is_a?(Proc)
        raise InvalidConfiguration.new("use_datadome should be a Proc")
      end

      if app_url != nil && URI.parse(app_url).host.nil?
        raise InvalidConfiguration.new("app_url should be full url. ex https://github.com")
      end

      if use_arkose_V4_api != nil && !use_arkose_V4_api.is_a?(Proc)
        raise InvalidConfiguration.new("use_arkose_V4_api should be a proc that returns a boolean")
      end

      if use_octocaptcha_verify_api != nil && !use_octocaptcha_verify_api.is_a?(Proc)
        raise InvalidConfiguration.new("use_octocaptcha_verify_api should be a proc that returns a boolean")
      end

      @stats = Stats.get_stats_client("octocaptcha", app_name, feature_name, env, tags: [
        "is_captcha_service_disabled_overriden:#{is_captcha_service_disabled != nil}",
        "is_captcha_disabled_overriden:#{is_captcha_disabled != nil}",
      ])

      if is_captcha_service_disabled.nil? && self.is_test_env?
        self.is_captcha_service_disabled = -> { false }
      end

      self.octocaptcha_uri = if ["development", "test"].include?(env)
                              URI("http://octocaptcha.localhost")
                            else
                              URI("https://octocaptcha.com")
                            end
    end

    # Private: Use arkose v4 api
    #
    # Returns a boolean
    def use_arkose_V4_api?
      if use_arkose_V4_api.nil?
        false
      else
        use_arkose_V4_api.call == true
      end
    end

    # Private: Use verify token api
    #
    # Returns a boolean
    def use_octocaptcha_verify_api?
      if use_octocaptcha_verify_api.nil?
        false
      else
        use_octocaptcha_verify_api.call == true
      end
    end

    # Private: User provided function to check if captcha is disabled
    #
    # Returns a boolean
    def is_captcha_disabled?
      self.stats.time("is_captcha_disabled_time") do
        if is_captcha_disabled.nil?
          false
        else
          !!is_captcha_disabled.call
        end
      end
    end

    MAX_RETRIES_FOR_SERVICE_CHECK = 1
    # Private: User provided function to check if captcha service is disabled
    #
    # Returns a boolean
    def is_captcha_service_disabled?
      self.stats.time("is_captcha_service_disabled_time") do
        if is_captcha_service_disabled.nil?
          retries = 0
          begin
            http = Net::HTTP.new(octocaptcha_uri.host, octocaptcha_uri.port)
            http.open_timeout = 1
            http.read_timeout = 1
            http.use_ssl = octocaptcha_uri.scheme == "https"
            http.max_retries = 0

            res = http.head("/")

            tags = ["retries:#{retries}", "response_code:#{res.code}"]
            self.stats.increment("is_captcha_service_disabled", tags: tags)

            res.code != "200"
          rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError => exception
            tags = ["retries:#{retries}", "exception:#{exception.class}", "exception_message:#{exception.message}"]
            self.stats.increment("is_captcha_service_disabled", tags: tags)

            if (retries += 1) <= MAX_RETRIES_FOR_SERVICE_CHECK # retry up to 1 times
              retry
            else
              self.stats.increment("is_captcha_service_disabled_check_failed", tags: tags)
            end
            true
          end
        else
          !!is_captcha_service_disabled.call
        end
      end
    end

    def is_test_env?
      env == "test"
    end

    def is_development_env?
      env == "development"
    end

    def is_production_env?
      env == "production"
    end

    def is_staging_env?
      env == "staging"
    end

    def new_session(token: nil)
      OctocaptchaSession.new(self, token)
    end

    class OctocaptchaSession
      attr_reader :octocaptcha
      attr_reader :token, :value, :error, :funcaptcha_response_body

      def initialize(octocaptcha, token)
        @octocaptcha = octocaptcha
        @token = token
      end

      def url
        octocaptcha.url
      end

      def show_captcha?
        return @show_captcha if defined?(@show_captcha)

        @show_captcha = begin
          if octocaptcha.is_captcha_disabled?
            false
          elsif octocaptcha.is_captcha_service_disabled?
            false
          else
            true
          end
        end
      end

      def solved?
        [
          :octocaptcha_is_disabled,
          :octocaptcha_service_is_disabled,
          :funcaptcha_server_failed, # we want to let the user through if FunCaptcha is down
          :octocaptcha_server_failed, # we want to let the user through if Octocaptcha is down
          :solved_captcha,
          :datadome_captcha, # DataDome is handling bot detection, Arkose verify skipped
        ].include?(value)
      end

      def start
        instrument_event("start")
      end

      # Evaluates the user and retrieves the value and error values
      def verify
        # When DataDome is active, skip Arkose verification entirely.
        # No Arkose token exists (DataDome iframe sends captcha-suppressed, not captcha-complete).
        if octocaptcha.use_datadome&.call == true
          @value = :datadome_captcha
          octocaptcha.stats.increment "captcha.datadome_active", tags: ["validation_value:datadome_captcha"]
          return
        end

        # Skips instrumentation of attempt & success events because this is
        # ocurring on the dotcom side when the api call is made
        if octocaptcha.use_octocaptcha_verify_api?
          @value, @error = get_results_octocaptcha_verify_api
          return
        end

        @value, @error = octocaptcha.use_arkose_V4_api? ? get_results_V4 : get_results
        instrument_event("attempt")

        if solved?
          instrument_event("success")
        end
      end

      private

      def instrument_event(event_type)
        tags = ["show_captcha:#{show_captcha?}"]
        tags << "validation_value:#{value}" if value
        tags << "validation_error:#{error}" if error

        octocaptcha.stats.increment "captcha.#{event_type}", tags: tags
      end

      def get_results
        if octocaptcha.is_captcha_disabled?             then [:octocaptcha_is_disabled, nil]
        elsif octocaptcha.is_captcha_service_disabled?  then [:octocaptcha_service_is_disabled, nil]
        elsif octocaptcha.is_test_env?                  then [:solved_captcha, nil]
        # calling response issues a network call to validate the token
        elsif response.class < Exception                then [:funcaptcha_server_failed, response]
        elsif response.code != "200"                    then [:funcaptcha_server_failed, response.code]
        elsif response_body.class < Exception           then [:funcaptcha_server_failed, response_body]
        # This needs to go after the API request
        # If funcaptcha's servers are down a not present token is valid.
        # If there servers are not down (ie it gets to this line) then it is invalid
        # (ie this was probably directly posted by a bot)
        elsif token.nil? || token.empty?                then [:failed_captcha, :token_not_provided]
        elsif response_body["error"]                    then [:failed_captcha, response_body["error"]]
        elsif response_body["solved"]                   then [:solved_captcha, nil]
        else
          [:failed_captcha, nil]
        end
      end

      def get_results_V4
        if octocaptcha.is_captcha_disabled?                          then [:octocaptcha_is_disabled, nil]
        elsif octocaptcha.is_captcha_service_disabled?               then [:octocaptcha_service_is_disabled, nil]
        elsif octocaptcha.is_test_env?                               then [:solved_captcha, nil]
        # calling response issues a network call to validate the token
        elsif response.class < Exception                             then [:funcaptcha_server_failed, response]
        elsif response.code >= "500"                                 then [:funcaptcha_server_failed, response.code]
        elsif response.code == "400" && (token.nil? || token.empty?) then [:failed_captcha, :token_not_provided]
        elsif response.code == "404"                                 then [:funcaptcha_server_failed, response.code]
        elsif response_body.class < Exception                        then [:funcaptcha_server_failed, response_body]
        elsif response_body["error"]                                 then [:failed_captcha, response_body["error"]]
        elsif response.code != "200"                                 then [:funcaptcha_server_failed, response.code]
        elsif response_body["solved"]                                then [:solved_captcha, nil]
        else
          [:failed_captcha, nil]
        end
      end

      def get_results_octocaptcha_verify_api
        if octocaptcha.is_captcha_disabled?                          then [:octocaptcha_is_disabled, nil]
        elsif octocaptcha.is_captcha_service_disabled?               then [:octocaptcha_service_is_disabled, nil]
        elsif octocaptcha.is_test_env?                               then [:solved_captcha, nil]

        # calling octocaptcha_verify_api_response issues a network call to validate the token
        elsif octocaptcha_verify_api_response.class < Exception      then [:octocaptcha_server_failed, octocaptcha_verify_api_response]
        elsif octocaptcha_verify_api_response.code != "200"          then [:octocaptcha_server_failed, octocaptcha_verify_api_response.code]
        elsif octocaptcha_verify_api_response_body.class < Exception then [:octocaptcha_server_failed, octocaptcha_verify_api_response_body]
        elsif octocaptcha_verify_api_response_body["solved"]         then [:solved_captcha, nil]
        else
          [:failed_captcha, nil]
        end
      end

      MAX_RETRIES_FOR_VERIFICATION = 1
      CAPTCHA_URI = URI("https://funcaptcha.com/fc/v/")
      CAPTCHA_V4_URI = URI("https://github-verify.arkoselabs.com/api/v4/verify/")
      def response
        @response ||= begin
          arkose_api_version = octocaptcha.use_arkose_V4_api? ? 4 : 1
          captcha_uri = octocaptcha.use_arkose_V4_api? ? CAPTCHA_V4_URI : CAPTCHA_URI
          tags = ["arkose_api_version:#{arkose_api_version}"]
          octocaptcha.stats.time("verify_token_with_arkose_time", tags: tags) do
            http = make_http_client(captcha_uri)
            post = Net::HTTP::Post.new(captcha_uri)
            post.set_form_data(
              "private_key" => octocaptcha.private_key,
              "session_token" => token,
            )

            retries = 0
            begin
              res = http.request(post)

              tags = ["retries:#{retries}", "response_code:#{res.code}", "arkose_api_version:#{arkose_api_version}"]
              octocaptcha.stats.increment("verify_token_with_arkose", tags: tags)

              res
            rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError => exception
              tags = ["retries:#{retries}", "exception:#{exception.class}", "exception_message:#{exception.message}", "arkose_api_version:#{arkose_api_version}"]
              octocaptcha.stats.increment("verify_token_with_arkose", tags: tags)

              if (retries += 1) <= MAX_RETRIES_FOR_VERIFICATION # retry up to 2 times
                retry
              else
                octocaptcha.stats.increment("verify_token_with_arkose_check_failed", tags: tags)
              end

              exception
            end
          end
        end
      end

      class EmptyResponseBody < Exception; end
      def response_body
        return response if response.class < Exception
        @response_body ||= begin
          begin
            raise EmptyResponseBody if response.body.nil? || response.body.empty?
            # example response body https://github.com/github/github/blob/2794bdff10f71cfc6c9d97168c7da64403beeb02/config/instrumentation/hydro.rb#L116
            body = JSON.parse(response.body)
            hash_ref = octocaptcha.use_arkose_V4_api? ? body["session_details"] : body["other"]
            if hash_ref
              hash_ref["session_created"] = Time.parse(hash_ref["session_created"]) if hash_ref["session_created"]
              hash_ref["check_answer"] = Time.parse(hash_ref["check_answer"]) if hash_ref["check_answer"]
              hash_ref["verified"] = Time.parse(hash_ref["verified"]) if hash_ref["verified"]
            end

            # Hoist "solved" to a top level field to support code that expects it to be there
            if octocaptcha.use_arkose_V4_api? && body["session_details"].is_a?(Hash)
              body["solved"] = body["session_details"]["solved"]
            end

            @funcaptcha_response_body = body

            body
          rescue JSON::ParserError, EmptyResponseBody, ArgumentError => exception
            arkose_api_version = octocaptcha.use_arkose_V4_api? ? 4 : 1
            tags = ["exception:#{exception.class}", "exception_message:#{exception.message}", "arkose_api_version:#{arkose_api_version}"]
            octocaptcha.stats.increment("parse_response", tags: tags)

            exception
          end
        end
      end

      OCTOCAPTCHA_VERIFY_API = '/v1/verify'
      OCTOCAPTCHA_URL = "https://octocaptcha.com/#{OCTOCAPTCHA_VERIFY_API}"
      OCTOCAPTCHA_URI = URI(OCTOCAPTCHA_URL)
      def octocaptcha_verify_api_response
        @octocaptcha_verify_api_response ||= begin
          octocaptcha.stats.time("octocaptcha_verify_api_time") do
            http = make_http_client(OCTOCAPTCHA_URI)
            post = make_verify_post_request

            retries = 0
            begin
              res = http.request(post)
              tags = ["retries:#{retries}", "response_code:#{res.code}"]
              octocaptcha.stats.increment("octocaptcha_verify_api", tags: tags)
              res
            rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError => exception
              tags = ["retries:#{retries}", "exception:#{exception.class}", "exception_message:#{exception.message}"]
              octocaptcha.stats.increment("octocaptcha_verify_api", tags: tags)

              retry if (retries += 1) <= MAX_RETRIES_FOR_VERIFICATION # retry up to 2 times

              octocaptcha.stats.increment("octocaptcha_verify_api_check_failed", tags: tags)
              exception
            end
          end
        end
      end

      def make_http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 1
        http.read_timeout = 3
        http.use_ssl = true
        http.max_retries = 0
        http
      end

      def make_verify_post_request
        now = Time.now.to_i
        auth_message = "#{OCTOCAPTCHA_VERIFY_API},#{now}"
        authorization = OpenSSL::HMAC.hexdigest("SHA256", octocaptcha.octocaptcha_hmac_secret || "", auth_message)

        post = Net::HTTP::Post.new(OCTOCAPTCHA_URI)
        post.body = { "page" => octocaptcha.origin_page, "octocaptcha-token" => token }.to_json
        post["Content-Type"] = "application/json"
        post["X-Authorization-Time"] = now
        post["Authorization"] = authorization
        post
      end

      def octocaptcha_verify_api_response_body
        @octocaptcha_verify_api_response_body ||= begin
          if octocaptcha_verify_api_response.class < Exception
            octocaptcha_verify_api_response
          elsif octocaptcha_verify_api_response.body.nil? || octocaptcha_verify_api_response.body.empty?
            EmptyResponseBody.new
          else
            JSON.parse(octocaptcha_verify_api_response.body)
          end
        end
      end
    end
  end
end
