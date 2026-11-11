# typed: strict
# frozen_string_literal: true

# Configures a cap on pull request creation based on open pull requests.
module Configurable
  module PullRequestCreationCap
    extend ActiveSupport::Concern
    extend T::Helpers

    include ::Configurable

    requires_ancestor { PullRequestCreationConfig }

    ENABLED_KEY = T.let("pull_request_creation_cap_enabled".freeze, String)
    CAP_KEY = T.let("pull_request_creation_cap".freeze, String)

    # Our research has shown humans open 1 PR max per day on average:
    # https://gist.github.com/moraesc/b7181de3e7ddd4394ea7919b82d05a05
    DEFAULT_CAP = T.let(1, Integer)
    MINIMUM_CAP = T.let(1, Integer)
    # GitHub recommends staying at or below 1,000 open pull requests against the same branch:
    # https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits#pull-requests-limits
    MAXIMUM_CAP = T.let(1_000, Integer)

    sig { params(enabled: T::Boolean, cap: T.nilable(T.any(Integer, String)), actor: User).void }
    def set_pull_request_creation_cap(enabled:, cap:, actor:)
      normalized_cap = normalize_cap(cap)
      return if enabled == pull_request_creation_cap_enabled? && normalized_cap == pull_request_creation_cap

      config.set(CAP_KEY, normalized_cap.to_s, actor)

      if enabled
        config.enable(ENABLED_KEY, actor)
      else
        config.disable(ENABLED_KEY, actor)
      end

      nil
    end

    sig { returns(T::Boolean) }
    def pull_request_creation_cap_enabled?
      return false unless FeatureFlag.vexi.enabled?(:pull_request_creation_cap, repository, default: false)

      config.enabled?(ENABLED_KEY)
    end

    sig { returns(Integer) }
    def pull_request_creation_cap
      value = config.get(CAP_KEY)
      return DEFAULT_CAP if value.nil?

      Integer(value, 10)
    end

    private

    sig { params(cap: T.nilable(T.any(Integer, String))).returns(Integer) }
    def normalize_cap(cap)
      normalized_cap = cap.is_a?(String) ? Integer(cap, 10) : cap

      raise ArgumentError, invalid_cap_error_message unless normalized_cap.is_a?(Integer) && normalized_cap.between?(MINIMUM_CAP, MAXIMUM_CAP)

      normalized_cap
    rescue ArgumentError, TypeError
      raise ArgumentError, invalid_cap_error_message
    end

    sig { returns(String) }
    def invalid_cap_error_message
      "Cap must be a whole number between #{MINIMUM_CAP} and #{MAXIMUM_CAP}."
    end
  end
end
