# typed: true
# frozen_string_literal: true

# SecurityCenterBusinessPlanOrgEligibility captures a unique requirement around Security Center support for
# organizations on a Teams plan ("business"). Ingesting data for all security features for all such orgs
# is not feasible, so we are scoping it down to any Teams orgs that have been billed for the feature. The
# most common example to provide here is turning Secret Protection on for a private repository.
class Repository::SecurityCenterBusinessPlanOrgEligibility
  extend ActiveSupport::Concern
  extend T::Helpers

  TRACKING_KEY = "security_center.business_org_eligibility"

  # Returns true if secret scanning was enabled on a private repo at some point in the past.
  sig { params(owner: T.nilable(T.any(User, Organization, Business))).returns(T::Boolean) }
  def enabled?(owner)
    self.class.enabled?(owner)
  end

  # Returns true if secret scanning was enabled on a private repo at some point in the past.
  sig { params(owner: T.nilable(T.any(User, Organization, Business))).returns(T::Boolean) }
  def self.enabled?(owner)
    return false unless owner
    return false unless eligible_owner?(owner)
    owner.config.enabled?(TRACKING_KEY)
  end

  # Eligibility is only if they are an org on a "business" plan
  sig { params(repo: Repository).void }
  def start_tracking_if_eligible(repo)
    self.class.start_tracking_if_eligible(repo)
  end

  # Eligibility is only if they are an org on a "business" plan
  sig { params(repo: Repository).void }
  def self.start_tracking_if_eligible(repo)
    # Only if the repo would result in a charge to the customer are they eligible
    return if repo.public?

    owner = repo.owner
    return unless owner
    return unless eligible_owner?(owner)

    # Are we already tracking?
    return if owner.config.enabled?(TRACKING_KEY)

    ActiveRecord::Base.connected_to(role: :writing) do
      owner.config.enable(TRACKING_KEY, User.ghost)
    end
  end

  sig { params(owner: T.nilable(T.any(User, Organization, Business))).returns(T::Boolean) }
  def eligible_owner?(owner)
    self.class.eligible_owner?(owner)
  end

  sig { params(owner: T.nilable(T.any(User, Organization, Business))).returns(T::Boolean) }
  def self.eligible_owner?(owner)
    return false unless owner.is_a?(User) && owner.organization?
    return false unless owner.plan.business?
    true
  end
end
