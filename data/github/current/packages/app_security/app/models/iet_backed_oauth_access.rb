# typed: true
# frozen_string_literal: true

require "jwt"

class IetBackedOauthAccess
  # Enforces interface compliance
  include OauthAccessTokens::IOauthAccess

  HYDRO_MISMATCH_SCHEMA = "github.iet_backed_oauth_access.v1.Mismatch"
  HYDRO_REDACTED = "[redacted]"
  ALLOWED_METHODS = %w[
    access_level
    application
    application_id
    application_type
    authorization
    authorization_id
    created_at
    expires_at
    feature_flag_enabled?
    id
    installation
    installation_id
    installation_type
    integration_application_type
    integration_application_type?
    is_application
    issued_at
    oauth_application_type
    oauth_application_type?
    pat_lifetime_in_days
    pat_type
    pat_type_name
    personal_access_token
    personal_access_token?
    safe_app
    saml_enforceable?
    scopes
    scopes?
    to_param
    token_last_eight
    user
    user_id
  ].freeze

  attr_reader :iet_claims, :credential_id, :fallback_access

  def self.from_iet(iet, expected_credential_id: nil)
    unless iet.present?
      GitHub.dogstats.increment("iet_backed_oauth_access.from_iet_nil", tags: ["reason:token_not_present"])
      return nil
    end

    unless is_iet_token?(iet)
      tags = ["reason:not_an_iet_token"]
      tags << invalid_string_iet_token_tag(iet)

      GitHub.dogstats.increment("iet_backed_oauth_access.from_iet_nil", tags: tags)
      return nil
    end

    access = new(iet)

    # Validate that IET credential_id matches expected credential_id from authnd
    if expected_credential_id && access.credential_id != expected_credential_id
      GitHub.dogstats.increment("iet_backed_oauth_access.from_iet_nil", tags: ["reason:credential_id_mismatch"])
      return nil
    end

    unless access.database_record_exists?
      GitHub.dogstats.increment("iet_backed_oauth_access.from_iet_nil", tags: ["reason:database_record_not_found"])
      return nil
    end

    access
  end

  # Check if a token is an IET (Identity Exchange Token) JWT
  def self.is_iet_token?(iet)
    GitHub::Authnd::InternalExchangeToken.valid_token?(iet)
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
        returnable = database_access&.#{method_name}#{args_forwarding}

        candidate = super#{args_forwarding}
        is_match = iet_result_matches_db_result?(iet_value: candidate, db_fallback_value: returnable)
        tags = ["method:#{method_name}", "match:\#{is_match}"]
        GitHub.dogstats.increment("iet_backed_oauth_access.experiment", tags: tags)
        instrument_mismatch_event(:#{method_name}, candidate, returnable) unless is_match
      ensure
        return returnable
      end
    RUBY
  end

  def self.instrumented_fallback(method, default: nil)
    location = T.must(T.must(caller_locations(1, 1)).first)

    ExperimentMethods.module_eval <<-RUBY, location.path.to_s, location.lineno
      def #{method}
        instrument_fallback_access(__method__)
        database_access&.#{method} || #{default.inspect}
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
  ensure
    "iet_validity_error:unknown_error" # catch-all for any other unexpected errors
  end

  experiment :feature_flag_enabled?, splat: true, kwargs: true
  include GitHub::VexiActor

  def initialize(iet)
    @iet = iet
    @iet_claims = decode_iet(iet)

    @credential_id = @iet_claims[Authnd::Client::Attributes::CREDENTIAL_ID]
  end

  # IOauthAccess interface methods - implement using IET claims when possible

  sig { returns T::Boolean }
  def database_record_exists?
    database_access.present?
  end

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

    is_feature_enabled = iet_application_id_enabled?

    # Try to load application from claims
    if application_type || is_feature_enabled
      application_id = self.application_id.to_i
      if application_id > 0
        case application_type
        when "OauthApplication"
          @application = OauthApplication.find_by(id: application_id)
        when "Integration"
          @application = Integration.find_by(id: application_id)
        else
          @application = nil
        end
      else
        @application = nil
      end

      # If we found any application ID and type in the IET, respect them and don't fall back to the database, even
      # if they don't point to an existing record:
      return @application if @application || is_feature_enabled
    end

    @application = begin
      instrument_fallback_access(__method__)
      database_access&.application
    end
  end

  sig { returns Promise[T.nilable(T.any(OauthApplication, Integration))] }
  experiment def async_application
    if iet_application_id_enabled?
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
    else
      instrument_fallback_access(__method__)
      if database_access
        T.must(database_access).async_application.then do |app|
          @application = app
        end
      else
        @application = nil
        Promise.resolve(nil)
      end
    end
  end

  sig { override.returns(T.nilable(OauthApplication)) }
  def oauth_application
    application = self.application
    application if application.is_a?(OauthApplication)
  end

  sig { override.returns(T.nilable(Integer)) }
  experiment def installation_id
    @iet_claims[Authnd::Client::Attributes::INSTALLATION_ID]&.to_i
  end

  sig { override.returns(T.nilable(T.any(ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))) }
  experiment def installation
    return @installation if defined?(@installation)

    scoped_installation_type = @iet_claims[Authnd::Client::Attributes::SCOPED_INSTALLATION_TYPE]
    is_feature_enabled = iet_installation_enabled?

    # Load installation from claims if available
    if scoped_installation_type || is_feature_enabled
      scoped_installation_id = @iet_claims[Authnd::Client::Attributes::SCOPED_INSTALLATION_ID].to_i
      if scoped_installation_id > 0
        case scoped_installation_type
        when "ScopedIntegrationInstallation"
          @installation = ScopedIntegrationInstallation.find_by(id: scoped_installation_id)
        when "SiteScopedIntegrationInstallation"
          @installation = SiteScopedIntegrationInstallation.find_by(id: scoped_installation_id)
        else
          @installation = nil
        end
      else
        @installation = nil
      end

      # If we found any scoped installation ID and type in the IET, respect them when the feature flag is enabled by
      # not falling back to the database, even if they don't point to an existing record:
      return @installation if @installation || is_feature_enabled
    end

    @installation = begin
      instrument_fallback_access(__method__)
      database_access&.installation
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
    if iet_installation_enabled?
      # A real OauthAccess record returns `nil` or a scoped installation type, so mirror that here:
      return @iet_claims[Authnd::Client::Attributes::SCOPED_INSTALLATION_TYPE]
    end

    instrument_fallback_access(__method__)
    database_access&.installation_type
  end

  sig { override.returns(T.nilable(Integer)) }
  experiment def authorization_id
    if iet_authorization_id_enabled?
      return @iet_claims[Authnd::Client::Attributes::AUTHORIZATION_ID]&.to_i
    end

    instrument_fallback_access(__method__)
    database_access&.authorization_id
  end
  alias_method :oauth_authorization_id, :authorization_id

  # Needed in /app/api/repository_keys.rb:49
  sig { override.returns(T.nilable(OauthAuthorization)) }
  experiment def authorization
    if iet_authorization_id_enabled?
      return @authorization if defined?(@authorization)
      authorization_id = self.authorization_id
      @authorization = if authorization_id && authorization_id > 0
        OauthAuthorization.find_by(id: authorization_id)
      end
      return @authorization
    end

    instrument_fallback_access(__method__)
    database_access&.authorization
  end
  alias_method :ability_delegate, :authorization

  sig { override.returns(Promise[T.nilable(OauthAuthorization)]) }
  experiment def async_authorization
    if iet_authorization_id_enabled?
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
    else
      instrument_fallback_access(__method__)
      if database_access
        T.must(database_access).async_authorization
      else
        Promise.resolve(nil)
      end
    end
  end
  alias_method :async_ability_delegate, :async_authorization

  experiment def credential_authorizations
    if iet_credential_authorizations_enabled?
      Organization::CredentialAuthorization.where(credential_type: "OauthAccess", credential_id: credential_id)
    else
      instrument_fallback_access(__method__)
      database_access&.credential_authorizations
    end
  end

  sig { override.returns(String) }
  def code
    instrument_fallback_access(__method__)
    database_access&.code || ""
  end

  sig { override.returns(String) }
  def description
    instrument_fallback_access(__method__)
    database_access&.description || ""
  end

  sig { override.returns(String) }
  def note
    instrument_fallback_access(__method__)
    database_access&.note || ""
  end

  sig { override.returns(String) }
  def note_url
    instrument_fallback_access(__method__)
    database_access&.note_url || ""
  end

  sig { override.returns(String) }
  def fingerprint
    instrument_fallback_access(__method__)
    database_access&.fingerprint || ""
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

  def updated_at
    instrument_fallback_access(__method__)
    database_access&.updated_at
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
    time_value_from_claim_field(Authnd::Client::Attributes::CREDENTIAL_EXPIRES_AT)
  end

  sig { override.returns(T.nilable(Integer)) }
  def expires_at_timestamp
    expires_at&.to_i
  end

  sig { override.params(created_by: T.any(Date, Time, ActiveSupport::TimeWithZone)).returns(T::Boolean) }
  def personal_access_token_eligible_for_account_recovery?(created_by)
    created_at = self.created_at
    if created_at
      return OauthAccess.personal_access_token_eligible_for_account_recovery?(created_by: created_by,
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
  experiment def is_application # rubocop:disable Naming/PredicatePrefix
    if iet_application_id_enabled?
      application_id = self.application_id
      # Based on the SQL definition for the generated `oauth_accesses.is_application` field:
      return !application_id.nil? && application_id != 0
    end

    instrument_fallback_access(__method__)
    database_access&.is_application || false
  end

  sig { override.returns(T::Array[String]) }
  experiment def access_level
    OauthAccess.access_level_from(scopes)
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
    if iet_application_id_enabled?
      return OauthAccessTokens::Domain.programmatic_access_token_type(
        is_personal_access_token: personal_access_token?,
      )
    end

    instrument_fallback_access(__method__)
    database_access&.pat_type
  end

  sig { override.returns(T.nilable(String)) }
  experiment def pat_type_name
    return pat_type&.name if iet_application_id_enabled?

    instrument_fallback_access(__method__)
    database_access&.pat_type_name
  end

  experiment def pat_lifetime_in_days
    if iet_pat_lifetime_in_days_enabled?
      return ProgrammaticAccess::ExpirationLimit.pat_lifetime_in_days_from(issued_at: issued_at,
        created_at: created_at, expires_at: expires_at)
    end

    instrument_fallback_access(__method__)
    database_access&.pat_lifetime_in_days || :unlimited
  end

  sig { override.params(target: T.untyped).returns(T.nilable(T::Boolean)) }
  def pat_adheres_by_targets_expiration_limit?(target)
    pat_type = self.pat_type
    if pat_type && iet_pat_lifetime_in_days_enabled?
      return ProgrammaticAccess::ExpirationLimit.pat_adheres_by_targets_expiration_limit?(target, access: self,
        pat_lifetime_in_days: pat_lifetime_in_days, pat_type: pat_type)
    end

    instrument_fallback_access(__method__)
    database_access&.pat_adheres_by_targets_expiration_limit?(target)
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
    if iet_application_id_enabled?
      application = self.application
      return application if application

      case application_type
      when "Integration"
        OauthAccess.fallback_integration(application_id: application_id)
      else
        OauthAccess.fallback_oauth_application(description: description, note_url: note_url)
      end
    end

    instrument_fallback_access(__method__)
    database_access&.safe_app
  end

  sig { returns T.nilable(T::Boolean) }
  experiment def saml_enforceable?
    if iet_application_id_enabled?
      return OauthAccessTokens::Domain.saml_enforceable?(is_personal_access_token: personal_access_token?,
        application: application)
    end

    instrument_fallback_access(__method__)
    database_access&.saml_enforceable?
  end

  sig { override.returns(String) }
  def vexi_id
    GitHub::VexiActor.to_feature_flag_id(OauthAccess.name, id)
  end

  private

  sig { params(iet_value: T.untyped, db_fallback_value: T.untyped).returns(T::Boolean) }
  def iet_result_matches_db_result?(iet_value:, db_fallback_value:)
    if iet_value.is_a?(Time) && db_fallback_value.is_a?(Time)
      # Compare with seconds precision:
      iet_value.to_i == db_fallback_value.to_i
    elsif iet_value.is_a?(Promise) && db_fallback_value.is_a?(Promise)
      iet_result_matches_db_result?(iet_value: iet_value.sync, db_fallback_value: db_fallback_value.sync)
    else
      iet_value == db_fallback_value
    end
  end

  def iet_authorization_id_enabled?
    return @iet_authorization_id_enabled if defined?(@iet_authorization_id_enabled)
    @iet_authorization_id_enabled = FeatureFlag.vexi.enabled?(:iet_authorization_id, actor_for_feature_flag,
      default: false)
  end

  def iet_application_id_enabled?
    return @iet_application_id_enabled if defined?(@iet_application_id_enabled)
    @iet_application_id_enabled = FeatureFlag.vexi.enabled?(:iet_application_id, actor_for_feature_flag,
      default: false)
  end

  def iet_skip_hydro_logging_enabled?
    return @iet_skip_hydro_logging_enabled if defined?(@iet_skip_hydro_logging_enabled)
    @iet_skip_hydro_logging_enabled = FeatureFlag.vexi.enabled?(:iet_skip_hydro_logging, actor_for_feature_flag,
      default: false)
  end

  def iet_installation_enabled?
    return @iet_installation_enabled if defined?(@iet_installation_enabled)
    @iet_installation_enabled = FeatureFlag.vexi.enabled?(:iet_installation, actor_for_feature_flag, default: false)
  end

  def iet_pat_lifetime_in_days_enabled?
    return @iet_pat_lifetime_in_days_enabled if defined?(@iet_pat_lifetime_in_days_enabled)
    @iet_pat_lifetime_in_days_enabled = FeatureFlag.vexi.enabled?(:iet_pat_lifetime_in_days, actor_for_feature_flag,
      default: false)
  end

  sig { returns T.nilable(Vexi::Actor) }
  def actor_for_feature_flag
    return @actor_for_feature_flag if defined?(@actor_for_feature_flag)
    # Avoid extra DB query just to allow a gradual actor-based rollout of a feature flag. Only use the OauthAccess's
    # user if we happen to have already loaded it by now:
    @actor_for_feature_flag = if database_access && database_access.association(:user).loaded?
      database_access.user
    end
  end

  def iet_credential_authorizations_enabled?
    return @iet_credential_authorizations_enabled if defined?(@iet_credential_authorizations_enabled)
    actor = if database_access && database_access.association(:user).loaded?
      database_access.user
    end
    @iet_credential_authorizations_enabled = FeatureFlag.vexi.enabled?(:iet_credential_authorizations, actor,
      default: false)
  end

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
      OauthAccessTokens.domain.by_id(credential_id)
    end
  end

  def instrument_fallback_access(method_name, source: :explicit)
    GitHub.dogstats.increment(
      "iet_backed_oauth_access.fallback_used",
      tags: ["method:#{method_name}", "source:#{source}"]
    )
  end

  def instrument_mismatch_event(method_name, claim_value, database_value)
    return if iet_skip_hydro_logging_enabled?

    # Only publish once per method per request
    @instrumented_mismatches ||= Set.new
    return if @instrumented_mismatches.include?(method_name)
    @instrumented_mismatches << method_name

    location = caller_locations(2, 1)&.first

    payload = {
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      credential_id: credential_id,
      method: method_name.to_s,
      mismatch_type: mismatch_type(claim_value, database_value),
      claim_value: sanitize_value(method_name, claim_value),
      database_value: sanitize_value(method_name, database_value),
      actor_id: @iet_claims[Authnd::Client::Attributes::ACTOR_ID],
      actor_type: @iet_claims[Authnd::Client::Attributes::ACTOR_TYPE],
      detected_at: Time.current,
      caller_path: location&.path,
      caller_lineno: location&.lineno,
      caller_label: location&.label,
    }.compact

    GitHub.hydro_publisher.publish(payload, schema: HYDRO_MISMATCH_SCHEMA)
  rescue => e
    GitHub.logger.warn("IetBackedOauthAccess mismatch hydro publish failed: #{e.message}")
  end

  def mismatch_type(claim_value, database_value)
    if claim_value.nil? && !database_value.nil?
      "MISSING_CLAIM"
    elsif !claim_value.nil? && database_value.nil?
      "MISSING_DB_VALUE"
    elsif !claim_value.nil? && !database_value.nil? && !same_type?(claim_value, database_value)
      "TYPE_MISMATCH"
    else
      "VALUE_MISMATCH"
    end
  end

  def same_type?(value1, value2)
    # Treat TrueClass and FalseClass as the same type (both are booleans)
    return true if boolean?(value1) && boolean?(value2)

    # We can compare two instances of subclasses of Time, so treat as same type:
    return true if value1.is_a?(Time) && value2.is_a?(Time)

    value1.class == value2.class
  end

  def boolean?(value)
    value.is_a?(TrueClass) || value.is_a?(FalseClass)
  end

  def sanitize_value(method_name, value)
    return HYDRO_REDACTED unless ALLOWED_METHODS.include?(method_name.to_s)

    case value
    when nil
      nil
    when Time
      value.utc.iso8601
    when ActiveRecord::Base
      value.id.to_s
    when Integer
      value.to_s
    else
      value.to_s
    end
  end

  # Safety net: Handle any missing methods by falling back to database_access
  # This prevents 500 errors when code calls methods we haven't explicitly wrapped
  def method_missing(method_name, *args, **kwargs, &block)
    if database_access&.respond_to?(method_name)
      instrument_fallback_access(method_name, source: :method_missing)
      database_access.public_send(method_name, *args, **kwargs, &block) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    database_access&.respond_to?(method_name, include_private) || super
  end
end
