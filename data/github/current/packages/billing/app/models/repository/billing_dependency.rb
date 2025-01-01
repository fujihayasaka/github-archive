# typed: strict
# frozen_string_literal: true

module Repository::BillingDependency
  extend T::Sig
  extend T::Helpers

  extend ActiveSupport::Concern

  requires_ancestor { Repository }

  # The plan owner is the account this repository is attached to. For public
  # repositories, it's the repository's owner, and for private repositories it's
  # whomever owns the repository network's root repository.
  #
  # In other words, if rtomayko/jobs is a fork of github/jobs,
  # rtomayko/job's `plan_owner` is the `github` Organization.
  sig { returns(T.nilable(::User)) }
  def plan_owner
    async_plan_owner.sync
  end

  sig { returns(Promise[T.nilable(::User)]) }
  def async_plan_owner
    if public?
      async_owner
    else
      async_network_owner
    end
  end

  # Check to see if this repo's owner is also the plan's owner.
  sig { returns(T::Boolean) }
  def plan_owned_by_owner?
    plan_owner == owner
  end

  # Public: If the repository is private and the network root owner is disabled
  # due to billing issues.
  #
  # This method purposly ignores the condition where a repo is disabled because
  # of ofac sanctions. the `disabled?` method should be used when
  # you want to check both conditions.
  sig { returns(T::Boolean) }
  def disabled_due_to_billing_issue?
    !!(private? && non_repo_plan_disabled_user?)
  end

  # Internal: plan_owner has been disabled and plan doesn't support repos
  sig { returns(T::Boolean) }
  private def non_repo_plan_disabled_user?
    plan_owner_disabled? && !plan_supports?(:repos)
  end

  # Internal: plan_owner either doesn't exist or has been disabled
  sig { returns(T::Boolean) }
  private def plan_owner_disabled?
    plan_owner = self.plan_owner
    plan_owner.nil? || plan_owner.disabled?
  end

  # Public: Enables or disables the owner for billing issues
  sig { void }
  def enable_or_disable_owner!
    if owner = self.owner
      should_disable? ? owner.disable! : owner.enable!
    end
  end

  # Should this user be disabled if it's not already?
  sig { returns(T::Boolean) }
  def should_disable?
    owner = T.must(self.owner)
    return false if owner.never_disable?

    # The beneficiary check is needed for couponed legacy plans to prevent users from unlocking
    # their account by toggling repository visibility. This is not needed for per-seat plans
    # since we downgrade them to free upon coupon expiration or when payment is past due.
    owner.should_disable? || (owner.beneficiary? && owner.plan.legacy?)
  end

  # Public: Does the owner of this repository have the plan capacity to make it
  #         private? Returns true if this repository is already private.
  sig { returns(T::Boolean) }
  def can_privatize?
    return true if private?
    # Only organization with Tier 0 restriction can make a repository private. If the
    # organization has any other restriction just return false.
    owner = T.must(self.owner)
    return false unless owner.restriction_tier_allows_feature?(type: :repository)

    if owner.plan.per_seat?
      owner_has_seats_for_collaborators? && owner_has_seats_for_collaborators?(pending_cycle: true)
    else
      !!(!owner.at_private_repo_limit? && !over_collaborator_limit_for_private_repos?)
    end
  end

  # Public: Does the the owner have enough seats to cover the collaborators on
  #         this repository if it's not already private.
  sig { params(pending_cycle: T::Boolean).returns(T::Boolean) }
  def owner_has_seats_for_collaborators?(pending_cycle: false)
    owner = T.must(self.owner)
    return true if owner.plan.free? || owner.plan.free_with_addons?
    return true if private? || owner.has_unlimited_seats? || owner.user?

    return true if !pending_cycle && owner.plan.per_repository?
    return true if pending_cycle && owner.pending_cycle_plan.per_repository?

    owner.seats_needed_for_collaborators_on(self, pending_cycle: pending_cycle).zero?
  end

  # Public: Would the repository have enough seats to cover collaborators when
  #         made private?
  sig { returns(T::Boolean) }
  def over_collaborator_limit_for_private_repos?
    [available_private_seats, 0].min < 0
  end

  sig { returns(T::Boolean) }
  def ensure_owner_has_enough_repo_quota
    return true if fork? || public? || advisory_workspace?

    owner = T.must(self.owner)
    if owner.disabled? && !owner.plan_supports?(:repos, visibility: :private, fallback_to_free: true)
      errors.add(:visibility, "can't be private. Please update your payment information before creating a new private repository.")
      false
    elsif owner.at_private_repo_limit?
      errors.add(:visibility, "can't be private. Please upgrade your subscription to create a new private repository.")
      false
    else
      true
    end
  end

  sig { returns(T::Boolean) }
  def licensing_enabled?
    private? && active? && has_business_owner?
  end

  sig { returns(T::Boolean) }
  def can_auto_merge_be_allowed?
    supports_protected_branches?
  end

  # Reset the LFS storage for this repository in the billing platform.
  # The billing platform tracks LFS storage by customer ID, organization ID,
  # and network root repository ID.  If any of these values change, then
  # we reset the billing storage level to avoid charging the customer
  # twice (via the old IDs and the new IDs).  The reconcile LFS storage
  # usage job will add the missing storage usage for the repository with
  # the new customer ID/organization ID/root repository ID later on.
  sig { void }
  def reset_billed_lfs_storage_usage
    return if GitHub.enterprise?

    client = Billing::Platform::Api::Client.new
    actor = owner&.delegate_billing_to_business? ? owner&.business : owner

    if GitHub.flipper[:lfs_metered_billing_vnext].enabled?(actor) && owner && actor
      customer_id = Asset::Activity.fetch_or_create_customer_id(owner)
      org_id = owner.is_a?(Organization) ? owner&.id : nil
      repo_id = id

      usage = client.get_watermark_level(
        usage_entity_id: customer_id,
        sku: "git_lfs_storage",
        org_id: org_id,
        repo_id: repo_id,
      )

      if usage.is_a?(Billing::Platform::Api::Error)
        GitHub.logger.error("Billing platform error", {
          "code.namespace" => "Repository",
          "code.function" => "reset_billed_lfs_storage_usage",
          "error" => usage,
        })
        return
      end

      if !(usage.is_a?(Hash) && usage.has_key?(:quantity))
        GitHub.logger.error("Unexpected billing platform error", {
          "code.namespace" => "Repository",
          "code.function" => "reset_billed_lfs_storage_usage",
          "error" => usage,
        })
        return
      end

      if usage[:quantity] > 0.001
        GlobalInstrumenter.instrument("billing_platform.metered_usage", {
          sku: "git_lfs_storage",
          quantity: -usage[:quantity],
          usage_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i, nanos: 0),
          source_uri: "gid://git-hub/reset/#{repo_id}",
          entity: {
            customer_id: customer_id,
            repo_id: repo_id,
            organization_id: org_id,
            actor_id: actor.id,
          },
        })
      end
    end
  end

  sig { returns(T.nilable(T.any(Licensing::SnapshotLicensesJob, FalseClass))) }
  private def snapshot_license_state
    return unless saved_changes.has_key?(:public) || saved_changes.has_key?(:active)
    Licensing::SnapshotLicensesJob.perform_later(T.must(owner).business)
  end
end
