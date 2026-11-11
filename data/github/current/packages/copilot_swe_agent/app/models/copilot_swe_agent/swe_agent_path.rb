# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  # Shared helper for constructing staging-aware SWE agent API paths.
  #
  # All API calls to `/agents/swe*` endpoints should use this module to
  # ensure requests are routed to the correct staging environment based on
  # feature flags.
  module SweAgentPath
    class StagingEnvironment < T::Struct
      const :legacy_flag, Symbol
      const :feature_flag, Symbol
      const :env_name, String
    end

    DEFAULT_ENV_NAME = T.let("swe", String)
    STAGING_ENVIRONMENTS = T.let([
      StagingEnvironment.new(
        legacy_flag: :use_staging_sith_lord,
        feature_flag: :sweagentd_route_user_or_repo_to_staging_sith_lord,
        env_name: "swe-staging-sith-lord",
      ),
      StagingEnvironment.new(
        legacy_flag: :use_staging_jedi_knight,
        feature_flag: :sweagentd_route_user_or_repo_to_staging_jedi_knight,
        env_name: "swe-staging-jedi-knight",
      ),
      StagingEnvironment.new(
        legacy_flag: :use_staging,
        feature_flag: :sweagentd_route_user_or_repo_to_staging,
        env_name: "swe-staging",
      ),
      StagingEnvironment.new(
        legacy_flag: :use_staging_baby_yoda,
        feature_flag: :sweagentd_route_user_or_repo_to_staging_baby_yoda,
        env_name: "swe-staging-baby-yoda",
      ),
    ].freeze, T::Array[StagingEnvironment])

    sig do
      params(
        staging_env: T.nilable(String),
        use_staging: T::Boolean,
        use_staging_jedi_knight: T::Boolean,
        use_staging_sith_lord: T::Boolean,
        use_staging_baby_yoda: T::Boolean,
      ).returns(String)
    end
    def self.env_name(staging_env: nil, use_staging: false, use_staging_jedi_knight: false, use_staging_sith_lord: false, use_staging_baby_yoda: false)
      return staging_env unless staging_env.nil? || staging_env.empty?

      return "swe-staging-sith-lord" if use_staging_sith_lord
      return "swe-staging-jedi-knight" if use_staging_jedi_knight
      return "swe-staging" if use_staging
      return "swe-staging-baby-yoda" if use_staging_baby_yoda

      DEFAULT_ENV_NAME
    end

    sig do
      params(
        staging_env: T.nilable(String),
        use_staging: T::Boolean,
        use_staging_jedi_knight: T::Boolean,
        use_staging_sith_lord: T::Boolean,
        use_staging_baby_yoda: T::Boolean,
      ).returns(String)
    end
    def self.base_path(staging_env: nil, use_staging: false, use_staging_jedi_knight: false, use_staging_sith_lord: false, use_staging_baby_yoda: false)
      "agents/#{env_name(staging_env:, use_staging:, use_staging_jedi_knight:, use_staging_sith_lord:, use_staging_baby_yoda:)}"
    end

    sig do
      params(
        nwo: String,
        api_version: T.nilable(String),
        staging_env: T.nilable(String),
        use_staging: T::Boolean,
        use_staging_jedi_knight: T::Boolean,
        use_staging_sith_lord: T::Boolean,
        use_staging_baby_yoda: T::Boolean,
      ).returns(String)
    end
    def self.job_path(nwo:, api_version: nil, staging_env: nil, use_staging: false, use_staging_jedi_knight: false, use_staging_sith_lord: false, use_staging_baby_yoda: false)
      base = base_path(staging_env:, use_staging:, use_staging_jedi_knight:, use_staging_sith_lord:, use_staging_baby_yoda:)
      version_segment = api_version.present? ? "/#{api_version}" : ""
      "#{base}#{version_segment}/jobs/#{nwo}"
    end

    # Resolves a single staging environment from feature flags for the given actors.
    sig do
      params(
        user: T.nilable(User),
        repository: T.nilable(Repository),
        owner: T.nilable(T.any(User, Organization)),
      ).returns(T.nilable(String))
    end
    def self.resolve_env(user: nil, repository: nil, owner: nil)
      resolved_owner = owner || repository&.owner
      environment = STAGING_ENVIRONMENTS.find do |candidate|
        flag_enabled?(candidate.feature_flag, user, repository, resolved_owner)
      end
      environment&.env_name
    end

    # Legacy compatibility for callers that still consume staging booleans.
    sig do
      params(
        user: T.nilable(User),
        repository: T.nilable(Repository),
        owner: T.nilable(T.any(User, Organization)),
      ).returns(T::Hash[Symbol, T::Boolean])
    end
    def self.staging_flags_for(user: nil, repository: nil, owner: nil)
      resolved_owner = owner || repository&.owner
      flags = T.let({}, T::Hash[Symbol, T::Boolean])

      STAGING_ENVIRONMENTS.each do |environment|
        flags[environment.legacy_flag] = flag_enabled?(environment.feature_flag, user, repository, resolved_owner)
      end

      flags
    end

    sig do
      params(
        flag: Symbol,
        user: T.nilable(User),
        repository: T.nilable(Repository),
        owner: T.nilable(T.any(User, Organization)),
      ).returns(T::Boolean)
    end
    private_class_method def self.flag_enabled?(flag, user, repository, owner)
      if user && repository && owner
        FeatureFlag.vexi.enabled?(flag, user, repository, owner, default: false)
      elsif user && repository
        FeatureFlag.vexi.enabled?(flag, user, repository, default: false)
      elsif user
        FeatureFlag.vexi.enabled?(flag, user, default: false)
      else
        false
      end
    end
  end
end
