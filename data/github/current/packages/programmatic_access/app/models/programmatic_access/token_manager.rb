# typed: true
# frozen_string_literal: true

module ProgrammaticAccess
  class TokenManager
    # create and destroy methods have their own classes, this class manages the other operations that needed to be
    # wrapped for proper package separation between programmmatic_access and programmatic_access_tokens without making
    # callers worry about setting the correct attributes and opts needed for authnd reqs

    sig { params(access: UserProgrammaticAccess).returns(ProgrammaticAccessTokens::IResult).checked(:always).on_failure(:raise) }
    def self.expiration_for(access)
      ProgrammaticAccessTokens.domain.expiration_for(*tenant_safe_params(access))
    end

    sig { params(access: UserProgrammaticAccess).returns(String).checked(:always).on_failure(:raise) }
    def self.token_last_eight(access)
      ProgrammaticAccessTokens.domain.token_last_eight(*tenant_safe_params(access))
    end

    sig { params(access: UserProgrammaticAccess, expires: T.nilable(Time)).returns(ProgrammaticAccessTokens::IResult).checked(:always).on_failure(:raise) }
    def self.regenerate(access, expires)
      GitHub.tracer.in_span("ProgrammaticAccess::regenerate", kind: :internal) do |span|
        grant = access.grant
        span.add_attributes(
          "gh.programmatic_access.owner.id" => access.user_id,
          "gh.programmatic_access.permissions.count" => grant&.permission_records&.count || 0,
        )
        if invalid_expiration_date_for_target?(access)
          grant ||= access.grant_request
          grant_target = grant&.target
          policy_config = ProgrammaticAccessTokenLifetimeConfiguration.new(grant_target, grant.user_programmatic_access.pat_type)
          return ProgrammaticAccessTokens::Domain.failure("expiration is above the limit set by #{policy_config.target_and_type_with_limit}")
        end

        result = ProgrammaticAccessTokens.domain.regenerate(*tenant_safe_params(access, expires_at: expires))
        access.notify_owner(about: :regenerated) if result.success?

        result
      end
    rescue ActiveRecord::ActiveRecordError => err
      Failbot.report!(err)
      ProgrammaticAccessTokens::Domain.failure(err.message)
    end

    # https://github.com/github/ecosystem-apps/issues/5335
    sig { params(access: UserProgrammaticAccess, opts: T::Hash[Symbol, T.untyped]).returns([Integer, Integer, T::Hash[Symbol, T.untyped]]).checked(:always).on_failure(:raise) }
    def self.tenant_safe_params(access, opts = {})
      [access.user_id, access.id, opts.merge({ business: access.owner&.enterprise_managed_business })]
    end

    def self.invalid_expiration_date_for_target?(access)
      return false unless access.targeting_organizations?

      grant = access.grant || access.grant_request
      limit = grant.target_expiration_limit
      return false unless limit

      access.pat_lifetime_in_days > limit
    end
  end
end
