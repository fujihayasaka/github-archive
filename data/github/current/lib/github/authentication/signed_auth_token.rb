# typed: true
# frozen_string_literal: true

# A generalized, signed authentication token, supporting scopes and expiration.
#
# Examples
#
#   token = SignedAuthToken.generate :user    => someuser,
#                                    :scope   => 'some_scope',
#                                    :expires => 30.seconds.from_now
#   parsed_token = SignedAuthToken.verify :token => token
#                                         :scope => 'some_scope'
#   parsed_token.valid?
#   # => true
#   parsed_token.user
#   # => someuser
#
#   expired_token = SignedAuthToken.generate :user    => someuser,
#                                            :scope   => 'some_scope',
#                                            :expires => 30.seconds.ago
#   parsed_token = SignedAuthToken.verify :token => expired_token
#                                         :scope => 'some_scope'
#   parsed_token.valid?
#   # => false
#   parsed_token.reason
#   # => :expired
#   parsed_token.expired?
#   # => true
#   parsed_token.user
#   # => nil
class GitHub::Authentication::SignedAuthToken
  autoload :Session, "github/authentication/signed_auth_token/session"
  autoload :Version1, "github/authentication/signed_auth_token/version1"
  autoload :Version2, "github/authentication/signed_auth_token/version2"
  autoload :Version2Hex, "github/authentication/signed_auth_token/version2_hex"
  autoload :Version3, "github/authentication/signed_auth_token/version3"

  DEFAULT_EXPIRES = 30.seconds

  attr_accessor :user, :session, :expires, :scope, :data, :reason

  # Checks whether string is in the format of a SignedAuthToken
  #
  # Returns boolean based on validity.
  def self.valid_format?(token)
    !possible_versions(token).empty?
  end

  # Generate a token string from the given options. The data used to generate
  # the token is signed but not encrypted. Don't put sensitive data in the
  # `data` field.
  #
  # user:    - The User to make the token for (optional).
  # session: - The UserSession to make the token for (optional).
  # scope:   - The String scope the token is valid for.
  # expires: - The Time the token will expire.
  # data:    - Arbitrary data to store in the token (any basic type).
  #
  # Returns String token.
  def self.generate(user: nil, session: nil, scope:, expires: nil, data: nil)
    # Ensure that we aren't caching signed auth tokens.
    GitHub::CacheLeakDetector.no_caching!

    unless scope.is_a?(String) && !scope.empty?
      GitHub.dogstats.increment("signed_auth_token", tags: [
        "action:generate",
        "result:failure",
        "reason:invalid_scope"
      ])
      raise ArgumentError
    end

    if user.nil? && session.nil?
      GitHub.dogstats.increment("signed_auth_token", tags: [
        "action:generate",
        "result:failure",
        "reason:both_user_and_session_nil"
      ])
      raise ArgumentError
    end

    unless user.nil? || session.nil?
      GitHub.dogstats.increment("signed_auth_token", tags: [
        "action:generate",
        "result:failure",
        "reason:both_user_and_session_provided"
      ])
      raise ArgumentError
    end

    kwargs = {
      scope: scope,
      expires: expires,
      data: data,
    }
    # delete nil kwargs so Version3 and Session can use their own default values
    kwargs.delete_if { |_, value| value.nil? }

    if session.nil?
      kwargs = kwargs.merge(user: user)

      token = Version3.generate(**kwargs)
      GitHub.dogstats.increment("signed_auth_token", tags: [
        "action:generate",
        "result:success",
        "version:v3",
      ])
    else
      kwargs = kwargs.merge(session: session)

      token = Session.generate(**kwargs)
      GitHub.dogstats.increment("signed_auth_token", tags: [
        "action:generate",
        "result:success",
        "version:session",
      ])
    end

    token
  end

  # Verify a token.
  #
  # token: - The String token to verify.
  # scope: - The expected String scope of the token.
  #
  # Returns SignedAuthToken instance.
  def self.verify(token:, scope:)
    instrument(do_verify_with_experiment(token: token, scope: scope))
  end

  # Verify a token for stafftools.
  # In stafftools cases, when the support team is checking if a given SAT is valid,
  # they may want to know if the token is valid, even if the corresponding user account is suspended.
  # The standard verification exists early if the account is suspended so it requires
  # staff to unsuspend the account, reverify, then suspend again in order to know if the SAT is valid.
  # See https://github.com/github/authentication/issues/1368.
  #
  # token: - The String token to verify.
  # scope: - The expected String scope of the token.
  #
  # Returns SignedAuthToken instance.
  def self.verify_for_stafftools(token:, scope:)
    instrument(do_verify(token: token, scope: scope, stafftools_only_ignore_suspension: true))
  end

  def initialize(user: nil, session: nil, expires: nil, scope: nil, data: nil, reason: nil)
    @session = session
    @expires = expires
    @scope   = scope
    @data    = data
    @reason  = reason

    # Setting the token on the user, to allow easy checking for the token
    user.sat_context = self.clone if !user.nil?
    @user = user
  end

  # Helpers for identifying the reason why a token is invalid.
  #
  # Each method returns a bool.
  %w[bad_token bad_scope bad_login user_suspended expired valid session_expired session_revoked].each do |name|
    define_method("#{name}?") { @reason == name.intern }
  end

  # Returns the Installation id from the token data.
  #
  # Returns a Integer or nil.
  def installation_id
    data["installation_id"] if data.is_a?(Hash)
  end

  # Returns the Installation type from the token data.
  #
  # Returns a String or nil.
  def installation_type
    data["installation_type"] if data.is_a?(Hash)
  end

  def version
    :invalid
  end

  # Verify a token. Additionally, performs a science experiment for authentication with authnd, if enabled.
  #
  # token: - The String token to verify.
  # scope: - The expected String scope of the token.
  #
  # Returns SignedAuthToken instance.
  def self.do_verify_with_experiment(token:, scope:)
    raise ArgumentError unless scope.is_a?(String) && !scope.empty?

    e = GitHub::Authnd::Experiment::new "authnd.github.verify_signed_auth_token"

    e.context scope: scope
    e.use do
      do_verify(
        token: token,
        scope: scope,
      )
    end

    e.try do
      do_verify_with_authnd(
        token: token,
        scope: scope,
      )
    end

    e.ignore do |control, candidate|
      next true if e.ignore_sat_unsupported_versions(control, candidate)
      next true if e.ignore_sat_unsupported_result(control, candidate)
      next true if e.ignore_ssat_expiry(control, candidate)
    end

    e.compare do |control, candidate|
      next false unless (
        control.reason == candidate.reason ||
        control.reason == :bad_token && candidate.reason == :bad_scope || # authnd can't differentiate between these two failures, defaults to bad_scope
        !control.valid? && candidate.reason == :unknown   # ignore any failure modes not handled by authnd
      )

      # ignore version checks when we fail. dotcom will provide the version, but authnd and test stubs won't.
      next false unless control.version == candidate.version || !control.valid?
      next false unless control.scope == candidate.scope
      next false unless control&.user&.id == candidate&.user&.id
      next false unless control&.session&.id == candidate&.session&.id
      next false unless control.data == candidate.data

      true
    end

    e.clean do |value|
      cleaned = {
        success: value.valid?,
        reason: value.reason,
        user_id: value&.user&.id,
        session_id: value&.session&.id,
        data: value.data,
        version: value.version,
      }
      cleaned.select { |_k, v| !v.nil? }  # remove keys with nil values to make make the diff more readable
    end

    result = e.run
    result
  end

  # Verify a token using only the internal, dotcom logic.
  #
  # token: - The String token to verify.
  # scope: - The expected String scope of the token.
  # stafftools_only_ignore_suspension - if true, the token will return valid even if the corresponding user account is suspended. Only used as stafftools bypass for account recovery analysis (`self.verify_for_stafftools`). Only applies to v3 tokens.
  #
  # Returns SignedAuthToken instance.
  def self.do_verify(token:, scope:, stafftools_only_ignore_suspension: false)
    versions = possible_versions(token)
    return bad_token(:bad_token) if versions.empty?

    results = versions.map do |version|
      version.verify(token: token, scope: scope, stafftools_only_ignore_suspension: stafftools_only_ignore_suspension).tap do |result|
        return result if result.valid?
      end
    end

    # Prefer token that wasn't rejected for being invalidly formatted
    best_result = results.find { |i| !i.bad_token? }
    best_result ||= results.first

    best_result
  end

  # Verify a token by calling the external authnd service.
  #
  # token:      - The String token to verify.
  # scope:      - The expected String scope of the token.
  #
  # Returns SignedAuthToekn instance.
  def self.do_verify_with_authnd(token:, scope:)
    req = ::Authnd::Proto::AuthenticateRequest::new(
      credentials: ::Authnd::Proto::Credentials::signed_auth_token(token, scope)
    )
    resp = ::GitHub::Authnd.authenticator("github/authnd").authenticate(req)

    if resp.success?
      result = generate_authnd_response(scope: scope, resp: resp)
    else
      result = new(reason: authnd_failure_to_reason(resp.result))
    end
  rescue ArgumentError => e
    case e.message
    when "credentials have no contents"
      # expected error, experiment can send empty tokens to authnd and will cause authnd to throw
      result = new(reason: :bad_scope)
    else
      raise
    end
  ensure
    # if we raised in the method somewhere, result will be undefined
    # just treat that as an invalid/unknown SAT
    # specific logic/metrics are emitted in the experiment
    # for tracking raises timeouts, and other known causes
    result ||= new(reason: :unknown)

    tags = ["type:sat"]
    tags << "credential_version:#{result.version}"
    tags << "reason:#{result.reason}"
    GitHub.dogstats.increment("github.verify_sat_authnd", tags: tags)

    result
  end

  # Generate a SignedAuthToken object from an authnd response.
  #
  # scope: - The String scope for the SAT.
  # resp:  - The Hash response from authnd.
  #
  # Returns a versioned SAT object from data provided in the authnd response. Used for
  # comparison with the internal response.
  def self.generate_authnd_response(scope:, resp:)
    return nil unless resp.attributes

    kwargs = {
        reason: :valid,
        scope: scope,
    }

    user_id = resp.attributes["actor.id"]
    kwargs[:user] = User.find_by(id: user_id)

    payload = resp.attributes.select { |k, _v| k.start_with?("credential.payload:") }
    unless payload.empty?
      kwargs[:data] = payload.transform_keys do |k|
        k.to_s.delete_prefix("credential.payload:")
      end
    end

    session_id = resp.attributes["session.id"]
    unless session_id
      return Version3.new(**kwargs)
    end

    kwargs[:session] = UserSession.find_by(id: session_id)
    Session.new(**kwargs)
  end

  # Map the failure return by authnd to a verify failure reason
  #
  # failure: - The failure result returned by authnd.
  #
  # A Symbol reason indicating why the verification failed.
  def self.authnd_failure_to_reason(failure)
    known_results_to_reasons = {
      RESULT_FAILED_CREDENTIAL_EXPIRED: :expired,
      # this can also be :bad_token but authnd doesn't have way to differentiate yet.  this is handled
      # by the experiment comparison.
      RESULT_FAILED_CREDENTIAL_INVALID: :bad_scope,
      RESULT_FAILED_SUSPENDED: :user_suspended,
      RESULT_FAILED_SESSION_EXPIRED: :session_expired,
      RESULT_FAILED_SESSION_REVOKED: :session_revoked,
      RESULT_FAILED_USER_UNKNOWN: :bad_login,
      RESULT_FAILED_NOT_SUPPORTED: :authnd_not_supported,
    }
    known_results_to_reasons.fetch(failure, :unknown)
  end

  # Instrument the result of verifying a token.
  #
  # token - A SignedAuthToken instance.
  #
  # Returns the token.
  def self.instrument(token)
    GitHub.dogstats.increment("authentication.signed_auth_token", tags: [
      "valid:#{token.valid?}",
      "version:#{token.version}",
      "reason:#{token.reason}",
    ])

    token
  end

  # Get the list of versions that this token matches the format of.
  #
  # token - The String token to guess a version for.
  #
  # Returns an Array of SignedAuthToken subclasses.
  def self.possible_versions(token)
    return [] if !token.is_a?(String) || token.empty?

    # Prefer newer token versions by putting them first.
    [
      Version3,
      Session,
      Version2,
      Version2Hex,
      Version1,
    ].select { |version| version.token_regex.match?(token) }
  end

  def self.bad_token(reason)
    new(reason: reason)
  end
end
