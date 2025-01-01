# typed: true
# frozen_string_literal: true

module Api::App::ActionsJwtAuthHelper
  include Kernel
  extend T::Helpers
  requires_ancestor { Api::App }

  Entity = T.type_alias { T.any(Business, Organization, Repository) }

  def issue_jwt(sub, extra_claims = {})
    payload = {
      # issued at time, 60 seconds in the past to allow for clock drift
      iat: Time.now.to_i - 60,
      # JWT expiration time (60 minute maximum)
      exp: Time.now.to_i + (60 * 60),
      # iss is the url of the stamp that issued the token
      iss: default_iss,
      # aud is the url of the stamp that the token is intended for
      aud: default_aud,
      # sub is the user that the token is for
      sub: sub.to_s,
    }.merge(extra_claims)

    JWT.encode(payload, signing_key[:key], "RS256", { kid: signing_key[:kid] })
  end

  sig { params(user: User, entity: Entity).returns(String) }
  def issue_jwt_for_user(user, entity)
    if user.is_a?(Bot)
      return issue_jwt(user.id, { installation_id: user.installation.id, installation_type: user.installation.class.to_s, scope: runner_api_jwt_scope(entity) })
    end
    issue_jwt(user.id, { scope: runner_api_jwt_scope(entity) })
  end

  def validate_jwt(jwt, expected_iss: GitHub.host_name_with_tenant, expected_aud: GitHub.host_name_with_tenant)
    begin
      jwt_claims, _ = JWT.decode(jwt, nil, true, verification_options(expected_iss, expected_aud)) do |header|
        key_func(header.with_indifferent_access)
      end

      jwt_claims.with_indifferent_access
    rescue JWT::InvalidIatError, JWT::InvalidIssuerError, JWT::ExpiredSignature, JWT::VerificationError, JWT::ImmatureSignature, JWT::InvalidAudError, JWT::InvalidSubError, JWT::InvalidJtiError => e
      # emit a metric for how often failed JWT auth is happening. This is largely to increase visibility during rollout.
      GitHub.dogstats.increment("actions.jwt_auth.failed", tags: ["error_type:#{e.class.name}"])
      raise
    rescue JWT::DecodeError
      # We may want to check if this request is auth'd another way (not a JWT)
      # So if the string is not a JWT just return nil instead of raising an error
      nil
    end
  end

  def validate_and_find_user_by_jwt(jwt)
    claims = validate_jwt(jwt)
    return nil unless claims

    [find_user_from_jwt(claims), claims[:scope]]
  end

  def attempt_actions_jwt_login
    begin
      user, scope = validate_and_find_user_by_jwt(api_auth.token)
      return unless user

      @current_user = user
      @remote_token_auth = true
      @actions_jwt_auth_scope = scope
    rescue JWT::InvalidIatError, JWT::InvalidIssuerError, JWT::ExpiredSignature, JWT::VerificationError, JWT::ImmatureSignature, JWT::InvalidAudError, JWT::InvalidSubError, JWT::InvalidJtiError
      reject_for_bad_credentials!
    end
  end

  sig { params(entity: Entity).returns(T::Boolean) }
  def invalid_jwt_login?(entity)
    return false unless GitHub.flipper.feature(:actions_runners_check_jwt_auth_attempt).enabled?
    return false unless using_jwt_login?
    return true unless entity.feature_enabled?(:actions_scale_sets_use_dotcom_apis)

    expected_scope = runner_api_jwt_scope(entity)
    @actions_jwt_auth_scope != expected_scope
  end

  sig { params(entity: Entity).returns(String) }
  def runner_api_jwt_scope(entity)
    if entity.is_a?(Organization)
      "ApiOrgActionsRunner:#{entity.id}"
    elsif entity.is_a?(Business)
      "ApiBusinessActionsRunner:#{entity.id}"
    elsif entity.is_a?(Repository)
      "ApiRepoActionsRunner:#{entity.id}"
    else
      T.absurd(entity)
    end
  end

  private

  def using_jwt_login?
    !!@actions_jwt_auth_scope
  end

  def key_func(header)
    # Find the key that signed the JWT by kid
    key = verification_keys.find { |k| k[:kid] == header[:kid] }
    raise JWT::VerificationError, "No keys found that match the kid" unless key

    key[:key]
  end

  def verification_options(iss, aud)
    {
      verify_expiration: true,
      verify_not_before: true,
      verify_iat: true,
      verify_iss: true,
      verify_aud: true,
      algorithms: ["RS256"],
      iss: iss,
      aud: aud
    }
  end

  def signing_key
    @signing_key ||= GitHub.actions_jwt_signing_key
  end

  def verification_keys
    @verification_keys ||= GitHub.actions_jwt_verification_keys
  end

  def default_iss
    GitHub.host_name_with_tenant
  end

  def default_aud
    GitHub.host_name_with_tenant
  end

  def find_user_from_jwt(claims)
    return nil unless claims[:sub]

    user = ActiveRecord::Base.connected_to(role: :reading) do
      User.find_by(id: claims[:sub])
    end
    return nil unless user

    # lifted from: https://github.com/github/github/blob/712703adebc00d08c265ce2e5acc3d0f4acc8ab7/packages/apps/app/models/user/remote_authentication_dependency.rb#L180
    if user.is_a?(Bot)
      installation_type = claims[:installation_type]
      installation_id = claims[:installation_id]
      installation = find_installation(installation_type, installation_id)

      if installation.nil? && ActiveRecord::Base.connected_to?(role: :reading)
        installation = ActiveRecord::Base.connected_to(role: :writing) do
          find_installation(installation_type, installation_id)

          GitHub.dogstats.increment("signed_auth_token.installation.fallback_to_primary", tags: ["installation_type:#{installation_type}", "found_on_primary:#{!installation.nil?}"])
        end
      end

      return installation.bot if installation&.bot
    end

    user
  end

  # lifted from https://github.com/github/github/blob/712703adebc00d08c265ce2e5acc3d0f4acc8ab7/packages/apps/app/models/user/remote_authentication_dependency.rb#L208-L209
  def find_installation(installation_type, installation_id)
    if installation_type == "ScopedIntegrationInstallation"
      ScopedIntegrationInstallation.includes(:integration).find_by(id: installation_id)
    elsif installation_type == "SiteScopedIntegrationInstallation"
      SiteScopedIntegrationInstallation.includes(:integration).find_by(id: installation_id)
    else
      IntegrationInstallation.includes(:integration).find_by(id: installation_id)
    end
  end
end
