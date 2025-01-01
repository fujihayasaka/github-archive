# typed: true
# frozen_string_literal: true

# This should be used as the base class for our endpoints that are
# intended to be callable by the Spark SDK with ACA auth. All of them
# are expected to respond as well to standard GH auth.
class Api::Runtime::SdkBase < Api::App
  extend T::Helpers

  abstract!

  before do
    @verbose_logging_enabled = FeatureFlag.vexi.enabled?("spark_kv_verbose_logging", nil, default: false)

    decrypt_jwt_claims!
    deliver_error!(404) unless authed_user&.feature_enabled?(:copilot_workbench)
  end

  def decrypt_jwt_claims!
    # no user is loaded yet, so this can only be a global FF
    return unless FeatureFlag.vexi.enabled?("spark_kv_decrypt_jwt", nil, default: false)

    raw_header = request.env["HTTP_AUTHORIZATION"]
    if !raw_header || !raw_header.start_with?("Spark-Bearer ")
      verbose_log("Not using Spark-Bearer header, skipping")
      return
    end

    # if the auth header is using the special Spark-Bearer format but something is invalid from here on, return a
    # 404 instead of trying to gracefully continue

    verbose_log("Spark-Bearer authorization header found: #{raw_header}")

    encrypted_token = raw_header.split(" ")[1]
    if !encrypted_token
      verbose_log("Spark-Bearer format is invalid")
      deliver_error!(404)
    end

    decrypted = GitHub.decrypt_spark_token(encrypted_token)

    # TODO verify the signature
    jwt = JWT.decode(decrypted, nil, false)

    unless jwt.is_a?(Array) && jwt.length == 2 && jwt[0].is_a?(Hash)
      verbose_log("Decoded JWT is invalid")
      deliver_error!(404)
    end

    @token = jwt[0]["data"]["tkn"]
    @app_user = jwt[0]["data"]["app_user"]

    verbose_log("Got decrypted JWT values. token last 8: #{@token.last(8)} | app user: #{@app_user}")

    user_result = user_from_token(@token)
    unless user_result.success?
      verbose_log("User auth failed. #{user_result.failure_type} | #{user_result.message}")
      deliver_error!(404)
    end

    @token_user = user_result.user

    verbose_log("User auth succeeded. User login: #{@token_user.display_login} | User is bot: #{@token_user.bot?} | Actor: #{@token_user.actor&.display_login} | Ability delegate: #{@token_user.ability_delegate}")
  end

  def authed_user
    @token_user || current_user
  end

  def app_user_display_login
    if @app_user
      @app_user
    else
      current_user.display_login
    end
  end

  sig { params(token: String).returns(GitHub::Authentication::Result) }
  def user_from_token(token)
    api_auth = GitHub::Authentication::Attempt.new(
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      from: :api_other,
      token: token,
      password_auth_blocked: true,
    )
    api_auth.result
  end

  def verbose_log(message)
    return unless @verbose_logging_enabled

    GitHub.logger.info(message, { "gh.spark.app": params[:app] })
  end
end
