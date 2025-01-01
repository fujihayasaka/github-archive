# typed: strict
# frozen_string_literal: true
class EnterpriseTeamOrganizationMapping < ApplicationRecord::Domain::Users
  extend(T::Sig)

  belongs_to :enterprise_team, -> do
    unscope(where: :deleted_at)
  end
  belongs_to :organization, inverse_of: :enterprise_team_organization_mappings
  belongs_to :team, optional: true, dependent: :destroy, inverse_of: :enterprise_team_organization_mapping

  validates_presence_of :enterprise_team, :organization
  validates :enterprise_team, uniqueness: { scope: :organization }

  JOB_RESTRAINT_LOCK_KEY_TEMPLATE = "organization-team-mapping-%s-lock"
  JOB_RESTRAINT_MAX_CONCURRENT_JOBS = 1
  JOB_RESTRAINT_LOCK_TTL = T.let(5.minutes, Integer)

  sig { params(enterprise_team_id: Integer, block: T.proc.params(arg0: GitHub::Restraint::Lock).returns(T.anything)).returns(T.anything) }
  def self.job_restraint_lock!(enterprise_team_id:, &block)
    GitHub::Restraint.new.lock!(
      JOB_RESTRAINT_LOCK_KEY_TEMPLATE % enterprise_team_id,
      JOB_RESTRAINT_MAX_CONCURRENT_JOBS,
      JOB_RESTRAINT_LOCK_TTL,
      &block
    )
  end
end
