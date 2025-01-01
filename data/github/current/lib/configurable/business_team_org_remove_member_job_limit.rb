# typed: true
# frozen_string_literal: true

# Configurable for the limit of concurrent OrganizationBulkRemoveMembersCleanupJob instances
module Configurable
  module BusinessTeamOrgRemoveMemberJobLimit
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "business_team_org_remove_member_job_limit"
    DEFAULT_BUSINESS_TEAM_ORG_REMOVE_MEMBER_JOB_LIMIT = 25

    # Get the limit for concurrent OrganizationBulkRemoveMembersCleanupJob instances.
    #
    # Returns Integer.
    sig { returns(Integer) }
    def business_team_org_remove_member_job_limit
      config.get(KEY)&.to_i || DEFAULT_BUSINESS_TEAM_ORG_REMOVE_MEMBER_JOB_LIMIT
    end

    # Set the limit for concurrent OrganizationBulkRemoveMembersCleanupJob instances.
    #
    # value - Integer representing the job limit to set.
    # actor - User setting the limit.
    # final - Optional Boolean representing whether the limit should override
    #   values set on objects lower down in the hierarchy.
    #
    # Returns nothing.
    sig { params(value: Integer, actor: User, final: T::Boolean).void }
    def set_business_team_org_remove_member_job_limit(value, actor:, final: false)
      config.set!(KEY, value, actor, final)
    end

    # Clear the limit for concurrent OrganizationBulkRemoveMembersCleanupJob instances.
    #
    # actor: User clearing the limit.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def clear_business_team_org_remove_member_job_limit(actor:)
      config.delete(KEY, actor)
    end
  end
end
