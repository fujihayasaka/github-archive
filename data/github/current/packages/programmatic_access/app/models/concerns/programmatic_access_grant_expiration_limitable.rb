# typed: true
# frozen_string_literal: true

module ProgrammaticAccessGrantExpirationLimitable
  extend ActiveSupport::Concern
  extend T::Helpers

  LimitableTypes = T.type_alias do
    T.any(

      OrganizationProgrammaticAccessGrant,
      OrganizationProgrammaticAccessGrantRequest,
      UserProgrammaticAccessGrant,
      UserProgrammaticAccessGrantRequest
    )
  end

  def target_expiration_limit
    T.bind(self, LimitableTypes)

    return unless target
    return unless user_programmatic_access

    limit_enforcer = T.must(target)

    if T.must(target).user?
      return unless T.must(target).is_enterprise_managed?

      limit_enforcer = T.must(target).enterprise_managed_business
    end

    access = T.must(user_programmatic_access)

    lifetime_config = ProgrammaticAccessTokenLifetimeConfiguration.new(limit_enforcer, access.pat_type)

    return nil if lifetime_config.exempted_for?(access.owner)
    lifetime_config.expiration_limit
  end
end
