# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  # Shared helper for constructing staging-aware SWE agent API paths.
  #
  # All API calls to `/agents/swe*` endpoints should use this module to
  # ensure requests are routed to the correct staging environment based on
  # feature flags.
  module SweAgentPath
    sig do
      params(
        use_staging: T::Boolean,
        use_staging_jedi_knight: T::Boolean,
        use_staging_sith_lord: T::Boolean,
      ).returns(String)
    end
    def self.env_name(use_staging: false, use_staging_jedi_knight: false, use_staging_sith_lord: false)
      return "swe-staging-sith-lord" if use_staging_sith_lord
      return "swe-staging-jedi-knight" if use_staging_jedi_knight
      return "swe-staging" if use_staging

      "swe"
    end

    sig do
      params(
        use_staging: T::Boolean,
        use_staging_jedi_knight: T::Boolean,
        use_staging_sith_lord: T::Boolean,
      ).returns(String)
    end
    def self.base_path(use_staging: false, use_staging_jedi_knight: false, use_staging_sith_lord: false)
      "agents/#{env_name(use_staging:, use_staging_jedi_knight:, use_staging_sith_lord:)}"
    end

    sig do
      params(
        nwo: String,
        api_version: T.nilable(String),
        use_staging: T::Boolean,
        use_staging_jedi_knight: T::Boolean,
        use_staging_sith_lord: T::Boolean,
      ).returns(String)
    end
    def self.job_path(nwo:, api_version: nil, use_staging: false, use_staging_jedi_knight: false, use_staging_sith_lord: false)
      base = base_path(use_staging:, use_staging_jedi_knight:, use_staging_sith_lord:)
      version_segment = api_version.present? ? "/#{api_version}" : ""
      "#{base}#{version_segment}/jobs/#{nwo}"
    end

    # Resolves staging routing flags from feature flags for the given actors.
    # Pass any combination of user, repository, and owner — all non-nil values
    # are forwarded to FeatureFlag.vexi.enabled? as actors.
    sig do
      params(
        user: T.nilable(User),
        repository: T.nilable(Repository),
        owner: T.nilable(T.any(User, Organization)),
      ).returns(T::Hash[Symbol, T::Boolean])
    end
    def self.staging_flags_for(user: nil, repository: nil, owner: nil)
      resolved_owner = owner || repository&.owner
      {
        use_staging: flag_enabled?(:sweagentd_route_user_or_repo_to_staging, user, repository, resolved_owner),
        use_staging_jedi_knight: flag_enabled?(:sweagentd_route_user_or_repo_to_staging_jedi_knight, user, repository, resolved_owner),
        use_staging_sith_lord: flag_enabled?(:sweagentd_route_user_or_repo_to_staging_sith_lord, user, repository, resolved_owner),
      }
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
