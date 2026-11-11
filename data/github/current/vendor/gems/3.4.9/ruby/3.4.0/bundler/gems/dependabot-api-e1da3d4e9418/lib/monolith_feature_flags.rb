# frozen_string_literal: true

require "feature_flags"

module MonolithFeatureFlags
  # RawActor wraps a FeatureFlags::Actor for use with monolith_feature_enabled?
  class RawActor
    attr_reader :actor

    def initialize(actor)
      @actor = actor
    end

    def monolith_actor
      actor
    end
  end

  # This method wraps the FeatureFlag library for the monolith in metrics along
  # with a configurable fail_state.  Feature flags can be checked per actor,
  # or globally by passing nil as the actor.
  #
  # The fail state can be:
  # - false  the feature should be assumed disabled on error [default]
  # - true   the feature should be assumed enabled on error
  # - :error the feature should raise any errors from the attempt
  #
  # Consider which behaviour is most appropriate for your feature, if the check
  # happens in a background job raising an error and retrying it might provide
  # the best experience.
  #
  # rubocop:disable Metrics/MethodLength
  def monolith_feature_enabled?(feature:, actor: nil, use_cache: true, fail_state: false)
    start_time = Time.now.in_time_zone
    begin
      result = FeatureFlags.feature_enabled?(feature: feature, actor: actor&.monolith_actor, use_cache: use_cache)
      response = :ok
    rescue FeatureFlags::Client::Error => e
      response = :error
      if fail_state == :error
        result = false
        raise
      else
        Dependabot::Exceptions.report!(e)
        result = fail_state
      end
    ensure # Metrics should be sent even if we raise
      MetricsClient.distribution(
        "monolith_feature_flag_duration_seconds",
        Time.now.in_time_zone - start_time,
        tags: {
          feature: feature,
          actor_class: actor.nil? ? "global" : actor.class.to_s.parameterize,
          response: response,
          feature_enabled: result,
        }
      )
    end
    result
  end
  # rubocop:enable Metrics/MethodLength

  def connect_monolith_feature_flags_client
    FeatureFlags.feature_flags_client
  end
end
