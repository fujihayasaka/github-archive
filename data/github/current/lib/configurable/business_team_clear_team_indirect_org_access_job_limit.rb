# typed: true
# frozen_string_literal: true

# Configurable for the limit of concurrent BusinessTeamClearTeamIndirectOrgAccessJobLimit instances
module Configurable
  module BusinessTeamClearTeamIndirectOrgAccessJobLimit
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "business_team_clear_team_indirect_org_access_job_limit"
    DEFAULT_BUSINESS_TEAM_CLEAR_TEAM_INDIRECT_ORG_ACCESS_JOB_LIMIT = 30
    ENTERPRISE_DEFAULT_BUSINESS_TEAM_CLEAR_TEAM_INDIRECT_ORG_ACCESS_JOB_LIMIT = 3

    # Get the limit for concurrent BusinessTeamClearTeamIndirectOrgAccessJobLimit instances.
    #
    # Returns Integer.
    sig { returns(Integer) }
    def business_team_clear_team_indirect_org_access_job_limit
      config.get(KEY)&.to_i || default_business_team_clear_team_indirect_org_access_job_limit
    end

    # Set the limit for concurrent BusinessTeamClearTeamIndirectOrgAccessJobLimit instances.
    #
    # value - Integer representing the job limit to set.
    # actor - User setting the limit.
    # final - Optional Boolean representing whether the limit should override
    #   values set on objects lower down in the hierarchy.
    #
    # Returns nothing.
    sig { params(value: Integer, actor: User, final: T::Boolean).void }
    def set_business_team_clear_team_indirect_org_access_job_limit(value, actor:, final: false)
      config.set!(KEY, value, actor, final)
    end

    # Clear the limit for concurrent BusinessTeamClearTeamIndirectOrgAccessJobLimit instances.
    #
    # actor: User clearing the limit.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def clear_business_team_clear_team_indirect_org_access_job_limit(actor:)
      config.delete(KEY, actor)
    end

    sig { returns(Integer) }
    def default_business_team_clear_team_indirect_org_access_job_limit
      if GitHub.enterprise?
        ENTERPRISE_DEFAULT_BUSINESS_TEAM_CLEAR_TEAM_INDIRECT_ORG_ACCESS_JOB_LIMIT
      else
        DEFAULT_BUSINESS_TEAM_CLEAR_TEAM_INDIRECT_ORG_ACCESS_JOB_LIMIT
      end
    end
  end
end
