# typed: true
# frozen_string_literal: true

# Used by Actions Runtime to determine max concurrency + abuse monitoring
# Accessed via GraphQL
class ActionsPlanOwner
  attr_reader :owner, :repository

  ENTERPRISE = "enterprise"
  ENTERPRISE_TRIAL = "enterprise_trial"
  FREE_ORGANIZATION = "free_organization"
  TEAM = "team"
  FREE = "free"
  PRO = "pro"

  def initialize(owner)
    @owner = owner
  end

  def id
    use_next_gid = !GitHub.enterprise?
    use_next_gid ? owner.next_global_id : owner.global_relay_id
  end

  def database_id
    owner.id
  end

  def type
    owner.class.name
  end

  # Valid values are:
  # - free
  # - free_organization
  # - pro
  # - team
  # - enterprise
  # - enterprise_trial
  #
  # These are used by Actions Service/Compute to:
  #   - Determine build concurrency
  #   - Determine Abuse risk (is the account paid or not?)
  #
  # If you need to change these values, or add a new plan. Please coordinate with them.
  def async_plan_name
    owner.async_plan.then do |owner_plan|
      if owner_plan.business_plus? || owner_plan.enterprise?
        trial = Billing::PlanTrial.find_by(
          user: owner,
          plan: GitHub::Plan::BUSINESS_PLUS,
        )

        next ENTERPRISE unless trial

        # For free trials, we return "enterprise_trial", to prevent abuse
        next trial.async_pending_plan_change.then do |_plan_change|
          trial.active? ? ENTERPRISE_TRIAL : ENTERPRISE
        end
      end

      next PRO if owner_plan.pro?
      next TEAM if owner_plan.business?

      if owner_plan.free? || owner_plan.free_with_addons?
        next FREE_ORGANIZATION if owner.organization?
        next FREE
      end

      # ^ These are the official plans that support Actions.
      #
      # We still have some legacy plans that have access to Actions that need to be migrated.
      # So we return free for those because Free plans have the least abilities.

      FREE
    end
  end

  def plan_name
    async_plan_name.sync
  end

  def customer_id
    # Return id of the customer if it exists
    if owner.delegate_billing_to_business?
      owner.business.customer_id
    else
      owner.async_customer.then do |customer|
        customer&.id
      end
    end
  end

  # These values are determined in Actions Service. Best we can do here is guess at the defaults.
  def max_concurrent_jobs_guess
    @plan_name ||= plan_name
    case @plan_name
    when FREE, FREE_ORGANIZATION      then 20
    when PRO                          then 40
    when TEAM                         then 60
    when ENTERPRISE, ENTERPRISE_TRIAL then 180
    else "?"
    end
  end

  # These values are determined in Actions Service. Best we can do here is guess at the defaults.
  def max_concurrent_macos_jobs_guess
    @plan_name ||= plan_name
    case @plan_name
    when FREE, FREE_ORGANIZATION, PRO, TEAM then 5
    when ENTERPRISE, ENTERPRISE_TRIAL       then 50
    else "?"
    end
  end

  def name
    return owner.slug if owner.is_a? Business
    owner.login
  end
end
