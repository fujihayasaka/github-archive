# typed: true
# frozen_string_literal: true

require "jwt"

# Public: The goal of this class is to provide a drop-in replacement for OauthAccess that can be initialized with an
# Internal Exchange Token (IET) instead of loading an OauthAccess record from the database. This allows us to avoid a
# database query in the common case where we have a valid IET with all the necessary claims to answer questions about
# the access token, and only fall back to hitting the database if we have to.
class IetBackedOauthAccess
  # Enforces interface compliance
  include OauthAccessTokens::IOauthAccess

  # https://app.datadoghq.com/databases/queries?query=cluster%3Amysql1%20mode%3Aproduction_replica%20command%3Aselect%20digest%3Ad0437c27d0732cdc57a3ba0f380559baf3d1b81fa56476abb18f7b7ecb6f89f5&dbPanels=%5B%7B%22t%22%3A%22dbQueryPanel%22%2C%22qs%22%3A%228fe79ede951877cb%22%2C%22dbType%22%3A%22MySQL%22%7D%5D&dbType=MySQL&fromUser=true&qListSort=count%3Adesc&start=1775481837474&end=1775496237474&paused=false
  OAUTH_ACCESS_LOOKUP_QUERY_DIGEST = "d0437c27d0732cdc57a3ba0f380559baf3d1b81fa56476abb18f7b7ecb6f89f5"

  attr_reader :iet_claims, :credential_id, :fallback_access

  def self.from_iet(iet, expected_credential_id: nil)
    unless iet.present?
      GitHub.dogstats.increment("iet_backed_oauth_access.from_iet_nil", tags: ["reason:token_not_present"])
      return nil
    end

    unless is_iet_token?(iet)
      tags = ["reason:not_an_iet_token"]
      tags << invalid_string_iet_token_tag(iet)
      tags << non_iet_token_format_tag(iet)

      GitHub.dogstats.increment("iet_backed_oauth_access.from_iet_nil", tags: tags)
      return nil
    end

    iet_backed_oauth_access = new(iet)

    # Validate that IET credential_id matches expected credential_id from authnd
    if expected_credential_id && iet_backed_oauth_access.credential_id != expected_credential_id
      GitHub.dogstats.increment("iet_backed_oauth_access.from_iet_nil", tags: ["reason:credential_id_mismatch"])
      return nil
    end

    iet_backed_oauth_access
  end

  # Check if a token is an IET (Identity Exchange Token) JWT
  def self.is_iet_token?(iet)
    GitHub::Authnd::InternalExchangeToken.valid_token?(iet)
  end

  # Identify the token format from its prefix for diagnostic tagging.
  # This helps distinguish which type of non-IET token was passed to from_iet
  # (e.g. raw OAuth tokens from the non-IET auth path).
  def self.non_iet_token_format_tag(token)
    return "token_format:not_a_string" unless token.is_a?(String)

    case token
    when /\Aghp_/                then "token_format:classic_pat"
    when /\Agho_/                then "token_format:oauth"
    when /\Aghu_/                then "token_format:user_to_server"
    when /\Aghs_/                then "token_format:server_to_server"
    when /\A(github_pat_|gh1_)/  then "token_format:fine_grained_pat"
    when /\AeyJ/                 then "token_format:jwt_like"
    else                              "token_format:unknown"
    end
  end

  # Experimentation framework to compare IET claims vs DB access for certain methods
  # Pattern yoinked from GitHub::Memoizer
  # Ensure we return the value from the DB method, but also call super to get the IET claim value
  # and instrument whether they match.
  #
  # We can't use Science directly here because we're interested in comparing the behavior throughout
  # the request lifecycle, not just in a single call.
  #
  # We're controlling rollout of this experiment via a feature flag in GitHub::Authentication::Default
  module ExperimentMethods
  end
  prepend ExperimentMethods

  def self.experiment(method_name, splat: false, kwargs: false)
    location = T.must(T.must(caller_locations(1, 1)).first)

    parts = []
    parts << "*args" if splat
    parts << "**kwargs" if kwargs
    args_signature = parts.empty? ? "" : "(#{parts.join(', ')})"
    args_forwarding = args_signature

    ExperimentMethods.module_eval <<-RUBY, location.path.to_s, location.lineno
      def #{method_name}#{args_signature}
        returnable = super#{args_forwarding}
        using_primary = ApplicationRecord::Domain::Integrations.connected_to?(role: :writing)
        tags = ["method:#{method_name}", "match:true", "skipped_db_fallback:true", "using_primary:\#{using_primary}"]
        GitHub.dogstats.increment("iet_backed_oauth_access.experiment", tags: tags)
      ensure
        return returnable
      end
    RUBY
  end

  def self.invalid_string_iet_token_tag(iet)
    if iet.is_a?(String)
      payload, = JWT.decode(iet, nil, false, { algorithm: "none" })

      if payload && (payload.is_a?(Hash) && payload["iss"] != "github/authnd")
        "iet_validity_error:payload_not_from_authnd"
      else
        "iet_validity_error:payload_is_not_a_hash"
      end
    else
      "iet_validity_error:not_a_string"
    end
  rescue JWT::DecodeError
    "iet_validity_error:jwt_decode_error"
  rescue TypeError
    "iet_validity_error:jwt_type_error"
  rescue => e
    "iet_validity_error:unknown_error"
  end

  experiment :feature_flag_enabled?, splat: true, kwargs: true
  include GitHub::VexiActor

  def initialize(iet)
    @iet = iet
    @iet_claims = decode_iet(iet)

    @credential_id = @iet_claims[Authnd::Client::Attributes::CREDENTIAL_ID]
  end

  # IOauthAccess interface methods - implement using IET claims when possible

  experiment def id
    credential_id
  end

  # Rails routing helper support
  sig { returns T.nilable(String) }
  experiment def to_param
    credential_id&.to_s
  end

  sig { override.returns(Integer) }
  experiment def user_id
    @iet_claims[Authnd::Client::Attributes::ACTOR_ID]&.to_i || 0
  end

  sig { override.returns(T.nilable(Users::IUser)) }
  experiment def user
    return @user if defined?(@user)

    # Load from claims if actor type is User, otherwise fallback to DB
    @user = if @iet_claims[Authnd::Client::Attributes::ACTOR_TYPE] == "User"
      user_id = self.user_id
      Users.domain.by_id(user_id) if user_id > 0
    else
      instrument_fallback_access(__method__)
      database_access&.user
    end
  end

  sig { override.returns(T.nilable(Integer)) }
  experiment def application_id
    @iet_claims[Authnd::Client::Attributes::APPLICATION_ID]&.to_i
  end

  sig { override.returns(T.nilable(String)) }
  experiment def application_type
    @iet_claims[Authnd::Client::Attributes::APPLICATION_TYPE]
  end

  sig { override.returns(T.nilable(T.any(OauthApplication, Integration))) }
  experiment def application
    return @application if defined?(@application)

    application_id = self.application_id.to_i

    @application = if application_id > 0
      case application_type
      when "OauthApplication"
        OauthAccessTokens.domain.oauth_applications.by_id(application_id)
      when "Integration"
        Integration.find_by(id: application_id)
      end
    end
  end

  sig { returns Promise[T.nilable(T.any(OauthApplication, Integration))] }
  experiment def async_application
    return Promise.resolve(@application) if defined?(@application)

    application_id = self.application_id

    if application_id && application_type && application_id > 0
      case application_type
      when "OauthApplication"
        Platform::Loaders::ActiveRecord.load(OauthApplication, application_id).then do |app|
          @application = app
        end
      when "Integration"
        Platform::Loaders::ActiveRecord.load(Integration, application_id).then do |app|
          @application = app
        end
      else
        @application = nil
        Promise.resolve(nil)
      end
    else
      @application = nil
      Promise.resolve(nil)
    end
  end

  sig { override.returns(T.nilable(OauthApplication)) }
  def oauth_application
    application = self.application
    application if application.is_a?(OauthApplication)
  end

  sig { override.returns(T.nilable(Integer)) }
  experiment def installation_id
    value = @iet_claims[Authnd::Client::Attributes::INSTALLATION_ID] ||
      @iet_claims[Authnd::Client::Attributes::SCOPED_INSTALLATION_ID]
    value&.to_i
  end

  sig { override.returns(T.nilable(T.any(ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))) }
  experiment def installation
    return @installation if defined?(@installation)

    installation_type = self.installation_type
    installation_id = self.installation_id

    @installation = if installation_id && installation_id > 0
      case installation_type
      when "ScopedIntegrationInstallation"
        ScopedIntegrationInstallation.find_by(id: installation_id)
      when "SiteScopedIntegrationInstallation"
        SiteScopedIntegrationInstallation.find_by(id: installation_id)
      end
    end
  end

  experiment :hashed_token, kwargs: true
  def hashed_token(hex: false)
    token_hash = @iet_claims[Authnd::Client::Attributes::TOKEN_HASH]

    # Try to use token.hash from IET claims
    if token_hash
      # The token.hash claim is already in the format we need (base64-encoded)
      hex ? Base64.decode64(token_hash).unpack("H*").first : token_hash
    end
  end

  sig { override.returns(T.nilable(Integration)) }
  def integration
    application = self.application
    application if application.is_a?(Integration)
  end

  sig { override.returns(T.nilable(String)) }
  experiment def installation_type
    # A real OauthAccess record returns `nil` or a scoped installation type, so mirror that here:
    @iet_claims[Authnd::Client::Attributes::SCOPED_INSTALLATION_TYPE]
  end

  sig { override.returns(T.nilable(Integer)) }
  experiment def authorization_id
    @iet_claims[Authnd::Client::Attributes::AUTHORIZATION_ID]&.to_i
  end
  alias_method :oauth_authorization_id, :authorization_id

  # Needed in /app/api/repository_keys.rb:49
  sig { override.returns(T.nilable(OauthAuthorization)) }
  experiment def authorization
    return @authorization if defined?(@authorization)

    authorization_id = self.authorization_id

    @authorization = if authorization_id && authorization_id > 0
      OauthAuthorization.find_by(id: authorization_id)
    end
  end
  alias_method :ability_delegate, :authorization

  sig { override.returns(Promise[T.nilable(OauthAuthorization)]) }
  experiment def async_authorization
    return Promise.resolve(@authorization) if defined?(@authorization)

    authorization_id = self.authorization_id

    if authorization_id && authorization_id > 0
      Platform::Loaders::ActiveRecord.load(OauthAuthorization, authorization_id).then do |oauth_authz|
        @authorization = oauth_authz
      end
    else
      @authorization = nil
      Promise.resolve(nil)
    end
  end
  alias_method :async_ability_delegate, :async_authorization

  experiment def credential_authorizations
    Organization::CredentialAuthorization.by_credential_type_and_id("OauthAccess", credential_id)
  end

  sig { override.returns(String) }
  def code
    instrument_fallback_access(__method__)
    database_access&.code || ""
  end

  sig { override.returns(T.nilable(String)) }
  experiment def description
    @iet_claims[Authnd::Client::Attributes::ACCESS_DESCRIPTION]
  end

  sig { override.returns(String) }
  def note
    instrument_fallback_access(__method__)
    database_access&.note || ""
  end

  sig { override.returns(T.nilable(String)) }
  experiment def note_url
    excluded_claims = @iet_claims[Authnd::Client::Attributes::EXCLUDED_CLAIMS] || []
    note_url_field = Authnd::Client::Attributes::ACCESS_NOTE_URL

    # Unless the IET says that the note URL field was excluded for being too big, we can rely on the value
    # that the IET has for it. For too-big note URLs, we'll have to fall back to reading it from the database.
    return @iet_claims[note_url_field] unless excluded_claims.include?(note_url_field)

    instrument_fallback_access(__method__)
    database_access&.note_url || ""
  end

  sig { override.returns(String) }
  experiment def fingerprint
    @iet_claims[Authnd::Client::Attributes::ACCESS_FINGERPRINT]
  end

  sig { override.returns(String) }
  experiment def token_last_eight
    @iet_claims[Authnd::Client::Attributes::TOKEN_SUFFIX] || ""
  end

  sig { override.returns(T.nilable(ActiveSupport::TimeWithZone)) }
  experiment def issued_at
    time_value_from_claim_field(Authnd::Client::Attributes::CREDENTIAL_ISSUED_AT) ||
      # https://datatracker.ietf.org/doc/html/rfc7519#section-4.1.6
      time_value_from_claim_field("iat")
  end

  sig { override.returns(T.nilable(ActiveSupport::TimeWithZone)) }
  experiment def created_at
    time_value_from_claim_field(Authnd::Client::Attributes::CREDENTIAL_CREATED_AT)
  end

  experiment def updated_at
    time_value_from_claim_field(Authnd::Client::Attributes::ACCESS_UPDATED_AT)
  end

  def accessed_at
    instrument_fallback_access(__method__)
    database_access&.accessed_at || Time.current.in_time_zone
  end

  sig { override.returns(T::Boolean) }
  def accessed_at?
    instrument_fallback_access(__method__)
    database_access&.accessed_at? || false
  end

  sig { override.returns(T.nilable(ActiveSupport::TimeWithZone)) }
  experiment def expires_at
    # Specifically return #expires_at in UTC to mirror behavior from OauthAccess#expires_at, whose definition comes
    # from lib/github/utc_timestamp.rb where the return value is always in UTC:
    time_value_from_claim_field(Authnd::Client::Attributes::CREDENTIAL_EXPIRES_AT)&.in_time_zone("UTC")
  end

  sig { override.returns(T.nilable(Integer)) }
  def expires_at_timestamp
    expires_at&.to_i
  end

  sig { override.params(created_by: T.any(Date, Time, ActiveSupport::TimeWithZone)).returns(T::Boolean) }
  def personal_access_token_eligible_for_account_recovery?(created_by)
    created_at = self.created_at
    if created_at
      return OauthAccessTokens::Domain.personal_access_token_eligible_for_account_recovery?(created_by: created_by,
        expires_at_timestamp: expires_at_timestamp, created_at: created_at,
        is_personal_access_token: personal_access_token?, scopes: scopes)
    end

    instrument_fallback_access(__method__)
    database_access&.personal_access_token_eligible_for_account_recovery?(created_by) || false
  end

  sig { override.returns(T::Boolean) }
  experiment def personal_access_token?
    @iet_claims[Authnd::Client::Attributes::APPLICATION_ID] == OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
  end

  sig { override.returns(T::Boolean) }
  experiment def integration_application_type?
    @iet_claims[Authnd::Client::Attributes::APPLICATION_TYPE] == "Integration"
  end

  sig { override.returns(T::Boolean) }
  experiment def oauth_application_type?
    !!(@iet_claims[Authnd::Client::Attributes::APPLICATION_TYPE] == "OauthApplication" && !personal_access_token?)
  end

  # Needed in /app/platform/authorization.rb:1285
  sig { override.returns(T::Boolean) }
  experiment def is_application
    application_id = self.application_id
    # Based on the SQL definition for the generated `oauth_accesses.is_application` field:
    !application_id.nil? && application_id != 0
  end

  sig { override.returns(T::Array[String]) }
  experiment def access_level
    OauthAccessTokens::Domain.access_level_from(scopes)
  end

  sig { override.returns(T.nilable(T::Array[String])) }
  experiment def scopes
    @iet_claims[Authnd::Client::Attributes::CREDENTIAL_SCOPES] || []
  end

  sig { override.returns(String) }
  def scopes_string
    scopes&.sort&.join(",") || ""
  end

  experiment :scopes?, splat: true
  def scopes?(*scopes)
    return false if self.scopes.nil?
    scopes.any? { |scope| self.scopes&.include?(scope.to_s) }
  end

  sig { override.returns(T.nilable(ProgrammaticAccessTokenType)) }
  experiment def pat_type
    OauthAccessTokens::Domain.programmatic_access_token_type(is_personal_access_token: personal_access_token?)
  end

  sig { override.returns(T.nilable(String)) }
  experiment def pat_type_name
    pat_type&.name
  end

  experiment def pat_lifetime_in_days
    ProgrammaticAccess::ExpirationLimit.pat_lifetime_in_days_from(issued_at: issued_at, created_at: created_at,
      expires_at: expires_at)
  end

  sig { override.params(target: T.untyped).returns(T.nilable(T::Boolean)) }
  def pat_adheres_by_targets_expiration_limit?(target)
    pat_type = self.pat_type
    if pat_type
      ProgrammaticAccess::ExpirationLimit.pat_adheres_by_targets_expiration_limit?(target, access: self,
        pat_lifetime_in_days: pat_lifetime_in_days, pat_type: pat_type)
    end
  end

  sig { override.returns(T.nilable(String)) }
  def default_expires_at
    instrument_fallback_access(__method__)
    database_access&.default_expires_at
  end

  def default_expires_at=(value)
    instrument_fallback_access(__method__)
    database_access&.default_expires_at = value if database_access
  end

  sig { override.returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def custom_expires_at
    instrument_fallback_access(__method__)
    database_access&.custom_expires_at
  end

  def custom_expires_at=(value)
    instrument_fallback_access(__method__)
    database_access&.custom_expires_at = value if database_access
  end

  # Needed in /app/platform/response/query_instrumenter.rb#L21
  experiment def safe_app
    application = self.application
    return application if application

    case application_type
    when "Integration"
      OauthAccessTokens::Domain.fallback_integration(application_id: application_id)
    else
      OauthAccessTokens::Domain.fallback_oauth_application(description: description, note_url: note_url)
    end
  end

  sig { returns T.nilable(T::Boolean) }
  experiment def saml_enforceable?
    OauthAccessTokens::Domain.saml_enforceable?(is_personal_access_token: personal_access_token?,
      application: application)
  end

  sig { override.returns(String) }
  def vexi_id
    GitHub::VexiActor.to_feature_flag_id("OauthAccess", id)
  end

  private

  sig { params(field_name: String).returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def time_value_from_claim_field(field_name)
    seconds_since_epoch = @iet_claims[field_name].to_i

    unless seconds_since_epoch == 0
      Time.at(seconds_since_epoch).in_time_zone
    end
  end

  def decode_iet(iet)
    # Decode the JWT without verification for now - the authentication system should have already verified it
    # In production, this would be verified by authnd before reaching this point
    JWT.decode(iet, nil, false)[0]
  rescue JWT::DecodeError => e
    GitHub.logger.warn("Failed to decode IET token: #{e.message}")
    {}
  end

  def database_access
    # Only load from database as a last resort
    return @fallback_access if defined?(@fallback_access)

    @fallback_access = if credential_id
      GitHub.context.push(
        taggable_query_digest: ["digest:#{OAUTH_ACCESS_LOOKUP_QUERY_DIGEST}"],
        remote_call_source_datadog_tags: ["source:iet_fallback_db_access"],
      ) do
        OauthAccessTokens.domain.by_id(credential_id)
      end
    end
  end

  def instrument_fallback_access(method_name, source: :explicit)
    using_primary = ApplicationRecord::Domain::Integrations.connected_to?(role: :writing)
    GitHub.dogstats.increment(
      "iet_backed_oauth_access.fallback_used",
      tags: ["method:#{method_name}", "source:#{source}", "skip_db_fallback_enabled:true",
        "using_primary:#{using_primary}"]
    )
  end

  # Safety net: Handle any missing methods by falling back to database_access
  # This prevents 500 errors when code calls methods we haven't explicitly wrapped
  def method_missing(method_name, *args, **kwargs, &block)
    if oauth_access_respond_to?(method_name)
      instrument_fallback_access(method_name, source: :method_missing)
      database_access.public_send(method_name, *args, **kwargs, &block) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    oauth_access_respond_to?(method_name, include_private) || super
  end

  def oauth_access_respond_to?(method_name, include_all = false)
    database_access = @fallback_access || OauthAccess.new
    database_access.respond_to?(method_name, include_all)
  end
end
