# typed: strict
# frozen_string_literal: true

# Manage interactions with the ORCID API.
class OrcidClient
  include GitHub::Memoizer
  extend T::Sig

  # User agent string we set on outgoing requests.
  USER_AGENT = "GitHub ORCID Integration"

  # Maximum time that we wait for a response from the ORCID servers, in seconds.
  REQUEST_TIMEOUT = 4

  # Template for URLs used to initiate the OAuth handshake.
  OAUTH_AUTHORIZE_URL_TEMPLATE = Addressable::Template.new(
    "https://{host}/oauth/authorize{?client_id,response_type,scope,redirect_uri,state}"
  )

  # Scope to request. Currently the minimum, as we only need to read the identifier.
  #
  # See: https://info.orcid.org/ufaqs/what-is-an-oauth-scope-and-which-scopes-does-orcid-support/
  OAUTH_SCOPE = "/authenticate"

  # Response to request from the OAuth handshake process. Requesting a code begins a "3-legged OAuth" handshake.
  OAUTH_RESPONSE_TYPE = "code"

  # Template for the URL used to exchange a code for authenticated record data.
  OAUTH_TOKEN_URL_TEMPLATE = Addressable::Template.new(
    "https://{host}/oauth/token"
  )

  # Construct a URL that begins the OAuth handshaking process using the current environment's configured OAuth
  # application client data, our default (minimal) scope, and the response type that our controller expects.
  #
  # redirect_uri - a String URI matching one of the allowlisted redirect URIs configured in our ORCID account.
  # state - a unique identifier used to track this OAuth transaction and defend against CSRF attacks.
  sig { params(redirect_uri: String, state: String).returns(Addressable::URI) }
  def oauth_url(redirect_uri:, state:)
    OAUTH_AUTHORIZE_URL_TEMPLATE.expand(
      host: GitHub.orcid_host,
      client_id: GitHub.orcid_oauth_client_id,
      scope: OAUTH_SCOPE,
      response_type: OAUTH_RESPONSE_TYPE,
      redirect_uri:,
      state:,
    )
  end

  # Exchange a code acquired from an OAuth redirect for the verified ORCID identifier associated with the
  # authenticated account.
  #
  # code - String given to us by a redirect during the ORCID OAuth handshake.
  #
  # Returns a Result that contains either the authenticated ORCID identifier or details about the failure that
  # prevented us from getting one.
  sig { params(code: String).returns(Result) }
  def get_authenticated_identifier(code:)
    token_url = OAUTH_TOKEN_URL_TEMPLATE.expand(host: GitHub.orcid_host).to_s
    common_attrs = {
      "url.full" => token_url,
    }

    begin
      response = connection.post(token_url) do |conn|
        conn.headers["Content-type"] = "application/x-www-form-urlencoded"
        conn.headers["Accept"] = "application/json"

        conn.body = URI.encode_www_form(
          client_id: GitHub.orcid_oauth_client_id,
          client_secret: GitHub.orcid_oauth_client_secret,
          grant_type: "authorization_code",
          code:,
        )
      end

      unless response.body.is_a?(Hash)
        return FailedResult.new(
          user_message: "the ORCID server returned an unexpected result",
          internal_message: "not-a-hash",
          log_attrs: common_attrs,
        )
      end

      identifier = response.body["orcid"]
      unless identifier&.is_a?(String)
        return FailedResult.new(
          user_message: "the ORCID server returned an unexpected result",
          internal_message: "missing-orcid-key",
          log_attrs: common_attrs,
        )
      end

      SuccessfulResult.new(identifier, log_attrs: common_attrs)
    rescue Faraday::TimeoutError => e
      FailedResult.new(
        user_message: "the ORCID server took too long to respond",
        internal_message: "timeout",
        log_attrs: common_attrs,
      )
    rescue Faraday::Error => e
      FailedResult.new(
        user_message: "the ORCID server returned an error",
        internal_message: "unsuccessful-response",
        log_attrs: common_attrs.merge({
          "exception.type" => e.class.name,
          "exception.message" => e.message,
          "http.response.status_code" => e.response[:status]&.to_s,
        }),
      )
    end
  end

  # Used to install a test adapter for tests.
  cattr_accessor :faraday_conf_block, default: ->(conn) { conn.adapter Faraday.default_adapter }

  # Abstract base class to return from methods on this class that can succeed or fail. Use the #on method to
  # handle specific cases in a type-safe way.
  class Result
    extend T::Sig
    extend T::Helpers
    abstract!

    sig { params(log_attrs: T::Hash[String, String]).void }
    def initialize(log_attrs)
      @log_attrs = log_attrs
    end

    # OTel-compatible logging metadata to attach to the log message produced after this call.
    sig { returns(T::Hash[String, String]) }
    attr_reader :log_attrs

    # Execute one of two blocks based on whether or not this call succeeded.
    #
    # Usage:
    #
    #   result = client.some_method_that_can_fail
    #   result.on(
    #     success: ->(r) { "r is a SuccessfulResult" },
    #     failure: ->(r) { "r is a FailedResult" },
    #   )
    sig do
      abstract.
        type_parameters(:R0, :R1)
        .params(
          success: T.proc.params(result: SuccessfulResult).returns(T.type_parameter(:R0)),
          failure: T.proc.params(result: FailedResult).returns(T.type_parameter(:R1)),
        )
        .returns(T.any(T.type_parameter(:R0), T.type_parameter(:R1)))
    end
    def on(success:, failure:) ; end
  end

  # Concrete Result subclass to be returned when a call succeeded.
  class SuccessfulResult < Result
    sig { params(identifier: String, log_attrs: T::Hash[String, String]).void }
    def initialize(identifier, log_attrs: {})
      super({ "gh.orcid.token.result" => "success" }.merge(log_attrs))
      @identifier = identifier
    end

    # The authenticated ORCID identifier.
    sig { returns(String) }
    attr_reader :identifier

    sig do
      override.
        type_parameters(:R0, :R1)
        .params(
          success: T.proc.params(result: SuccessfulResult).returns(T.type_parameter(:R0)),
          failure: T.proc.params(result: FailedResult).returns(T.type_parameter(:R1)),
        )
        .returns(T.any(T.type_parameter(:R0), T.type_parameter(:R1)))
    end
    def on(success:, failure:)
      success.call(self)
    end
  end

  # Concrete Result subclass to be returned when a call failed.
  class FailedResult < Result
    sig { params(user_message: String, internal_message: String, log_attrs: T::Hash[String, String]).void }
    def initialize(user_message:, internal_message:, log_attrs: {})
      super({
        "gh.orcid.token.result" => "failure",
        "gh.orcid.token.reason" => internal_message,
      }.merge(log_attrs))
      @user_message = user_message
    end

    # Returns a phrase suitable for display to end users to describe what went wrong. This will typically contain
    # less detail than what we send to Splunk.
    sig { returns(String) }
    attr_reader :user_message

    sig do
      override.
        type_parameters(:R0, :R1)
        .params(
          success: T.proc.params(result: SuccessfulResult).returns(T.type_parameter(:R0)),
          failure: T.proc.params(result: FailedResult).returns(T.type_parameter(:R1)),
        )
        .returns(T.any(T.type_parameter(:R0), T.type_parameter(:R1)))
    end
    def on(success:, failure:)
      failure.call(self)
    end
  end

  private

  # Construct a persistent Faraday connection to use for requests to ORCID hosts.
  sig { returns(Faraday::Connection) }
  memoize def connection
    GitHub::FaradayClient::External.new do |conn|
      conn.options[:timeout] = REQUEST_TIMEOUT
      conn.response :raise_error
      conn.response :json, content_type: /\bjson\z/
      conn.headers["User-Agent"] = USER_AGENT
      self.class.faraday_conf_block.call(conn)
    end
  end
end
