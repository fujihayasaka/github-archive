# typed: true
# frozen_string_literal: true

# Custom scientist experiment to configure a few options unique to the authnd experiment.
class GitHub::Authnd::Experiment < GitHub::Experiment
  def enabled?
    ::GitHub::Authnd.experiments_enabled? && super
  end

  # Overriding super to pass whole control/candidate objects to ignore block
  # https://github.com/github/scientist/blob/ba46e31f1d191128f30f95d59c22beb06b353479/lib/scientist/experiment.rb#L162
  def ignore_mismatched_observation?(control, candidate)
    return true if ignore_availability_failure(candidate)

    return false unless @_scientist_ignores
    @_scientist_ignores.any? do |ignore|
      ignore.call control, candidate
    end
  rescue StandardError => ex # rubocop:todo Lint/GenericRescue
    raised :ignore, ex
  end

  def track_replication_lag(created_at, credential_type)
    # compute the lag in milliseconds
    lag = (Time.now - T.cast(created_at, Time)) * 1000

    # Track the actual lag duration in a metric. We only do this if it was under the threshold because we don't want all the successful results polluting the data.
    GitHub.dogstats.distribution("authnd.experiment.lag", lag, tags: ["credential_type:#{credential_type}", "experiment:#{self.name}"])
  end

  def track_known_mismatch(kind, exception: nil)
    # Timeout error, ignore it and report a metric.
    tags = ["kind:#{kind}", "experiment:#{self.name}"]
    tags << "exception:#{exception.class.name}" if exception
    GitHub.dogstats.increment("authnd.experiment.ignored", tags: tags)
  end

  def ignore_availability_failure(result)
    return false if result.nil? || result.exception.nil?

    ignored = false
    if result.exception.is_a?(Faraday::TimeoutError)
      track_known_mismatch(:timeout, exception: result.exception)
      ignored = true
    elsif result.exception.is_a?(::Authnd::Proto::Error) && result.exception.twirp_error != nil
      # Use the Twirp error code as a metric tag.
      # Twirp error codes are fairly limited (https://twitchtv.github.io/twirp/docs/errors.html)
      # So the cardinality here should be pretty low
      track_known_mismatch(result.exception.twirp_error.code, exception: result.exception)
      ignored = true
    end

    ignored
  end

  def ignore_oauth_replication_lag(control, candidate)
    # neither side should have raised
    return false if control.value.nil? || candidate.value.nil?

    # if control failed, or candidate succeeded, it's not lag
    return false if !control.value.success || candidate.value.success

    # we don't support bot tokens in general
    return false if control.value.user.is_a? Bot

    unless Rails.env.development?
      # check if the token was created in the last minute
      token_created_at = control.value.user.oauth_access.created_at
      return false if token_created_at.nil?
      return false if token_created_at < (Time.now - 1.minute)

      track_replication_lag(token_created_at, "oauth_access_token")
      track_known_mismatch(:replication_lag)
    end
    true
  end

  def ignore_server_to_server_replication_lag(control, candidate)
    ignored = false
    unless Rails.env.development?
      if control.value.success? && candidate.value.authnd_response.result == :RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND
        track_known_mismatch(:replication_lag)
        ignored = true
      end
    end
    ignored
  end

  def ignore_ssh_replication_lag(control, candidate)
    # neither side should have raised
    return false if control.value.nil? || candidate.value.nil?

    # if control failed, or candidate succeeded, it's not lag
    return false if control.value[0] != :ok || candidate.value[0] == :ok

    unless Rails.env.development?
      # check if the public key was created in the last minute
      key_created_at = control.value[2].created_at
      return false if key_created_at.nil?
      return false if key_created_at < (Time.now - 1.minute)

      track_replication_lag(key_created_at, "ssh_public_key")
      track_known_mismatch(:replication_lag)
    end
    true
  end

  def ignore_oauth_integration_expiry(control, candidate)
    # neither side should have raised
    return false if control.value.nil? || candidate.value.nil?

    # the case we're checking is the control succeeds and the candidate fails
    return false unless control.value.success && !candidate.value.success

    # specifically due to candidate thinking the token expired
    return false unless candidate.value.authnd_response.result == :RESULT_FAILED_CREDENTIAL_EXPIRED

    # and the app in question is an integration
    return false unless control.value.user.oauth_access.application.is_a? Integration

    # and has user_token_expiration *disabled*
    return false if control.value.user.oauth_access.application.user_token_expiration

    track_known_mismatch(:integration_expiry)
    true
  end

  def ignore_ssat_expiry(control, candidate)
    # neither side should have raised
    return false if control.value.nil? || candidate.value.nil?

    # the case we're checking is the control succeeds and the candidate fails for expired
    return false unless control.value.reason == :valid && candidate.value.reason == :session_expired

    session = control.value.session if control.value.version == :session
    return false if session.expires_at.nil?

    # make sure session is or is just about to expire - leave some wiggle room for server time differences
    return false unless session.expires_at < (Time.now + 1.minute)
    track_known_mismatch(:ssat_expiry_replication_lag)
    true
  end

  def ignore_oauth_suspension_type_mismatch(control, candidate)
    # neither side should have raised
    return false if control.value.nil? || candidate.value.nil?

    control.value.failure_type == :oauth_application_suspended && candidate.value.failure_type == :suspended
  end

  def ignore_sat_unsupported_versions(control, candidate)
    # authnd only supports session and v3 version for signed auth tokens
    control.value && [:session, :"3"].exclude?(control.value.version)
  end

  def ignore_sat_unsupported_result(control, candidate)
    candidate.value && candidate.value.reason == :authnd_not_supported
  end

  def compare_oauth_access_token_experiment_result(control, candidate)
    return false unless control.success == candidate.success
    return false unless control.failure_type == candidate.failure_type
    return false unless control.user&.id == candidate.user&.id
    return false unless (control.user&.scopes || []) == (candidate.user&.scopes || [])
    unless control.user&.feature_enabled?(:disable_authnd_oauth_access_hydration)
      return false unless control.user&.oauth_access&.id == candidate.user&.oauth_access&.id
    end
    true
  end

  def clean_oauth_access_token_experiment_result(value)
    {
      success: value.success,
      failure_type: value.failure_type,
      user_id: value.user&.id,
      scopes: value.user&.scopes,
      suspended: value.user&.suspended?,
      access_id: value.user&.oauth_access&.id,
      token_id: value.user&.oauth_access&.id,
      token_created: value.user&.oauth_access&.created_at,
      token_app_type: value.user&.oauth_access&.application_type,
      authnd_response: value.authnd_response
    }
  end

  def ignore_oauth_access_token_experiment(token, control, candidate)
    return false if GitHub.flipper[:authnd_disable_experiment_ignore_oauth].enabled?

    return true if ServerToServerTokens::Domain.matches_pattern?(token)
    return true if ignore_oauth_replication_lag(control, candidate)
    return true if ignore_oauth_integration_expiry(control, candidate)
    return true if ignore_oauth_suspension_type_mismatch(control, candidate)
    false
  end

  def compare_server_to_server_token_experiment_result(control, candidate)
    return false unless control.success == candidate.success
    return false unless control.failure_type == candidate.failure_type
    return false unless control.user&.id == candidate.user&.id
    return false unless control.user&.installation&.class&.name == candidate.user&.installation&.class&.name
    return false unless control.user&.installation&.id == candidate.user&.installation&.id
    true
  end

  def clean_server_to_server_token_experiment_result(value)
    {
      success: value.success,
      failure_type: value.failure_type,
      user_id: value.user&.id,
      suspended: value.user&.suspended?,
      installation_type: value.user&.installation&.class&.name,
      installation_id: value.user&.installation&.id,
      authnd_response: value.authnd_response
    }
  end

  def ignore_server_to_server_token_experiment(token, control, candidate)
    return false if GitHub.flipper[:authnd_disable_experiment_ignore_server_to_server].enabled?

    return true unless ServerToServerTokens::Domain.matches_pattern?(token)
    return true if ignore_server_to_server_replication_lag(control, candidate)
    false
  end

  def compare_exchange_token_experiment_result(token, control, candidate)
    if ServerToServerTokens::Domain.matches_pattern?(token)
      compare_server_to_server_token_experiment_result(control, candidate)
    else
      compare_oauth_access_token_experiment_result(control, candidate)
    end
  end

  def clean_exchange_token_experiment_result(token, value)
    if ServerToServerTokens::Domain.matches_pattern?(token)
      clean_server_to_server_token_experiment_result(value)
    else
      clean_oauth_access_token_experiment_result(value)
    end
  end

  def ignore_exchange_token_experiment_result(token, control, candidate)
    if ServerToServerTokens::Domain.matches_pattern?(token)
      ignore_server_to_server_token_experiment(token, control, candidate)
    else
      ignore_oauth_access_token_experiment(token, control, candidate)
    end
  end
end
