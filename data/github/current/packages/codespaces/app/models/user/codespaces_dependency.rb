# typed: strict
# frozen_string_literal: true

module User::CodespacesDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))

    has_many :codespaces_repository_authorizations, class_name: "Codespaces::RepositoryAuthorization"
    has_many :trusted_repository_authorizations, class_name: "Codespaces::TrustedRepositoryAuthorization"
  end

  class_methods do

    sig { params(user: User, since: T.nilable(Time)).returns(Integer) }
    def billed_codespaces_count(user, since = nil)
      user
        .billed_billing_entries(since: since)
        .select(:codespace_guid)
        .distinct
        .count
    end

    sig { params(user: User, since: T.nilable(Time)).returns(Integer) }
    def owned_codespaces_count(user, since = nil)
      user
        .owned_billing_entries(since: since)
        .select(:codespace_guid)
        .distinct
        .count
    end
  end

  sig { returns(T::Boolean) }
  def codespaces_eligible?
    organization? && plan_codespaces_eligible? &&
      (!delegate_billing_to_business? || (plan.business? || plan.business_plus?))
  end

  # THE place to check if the Codespaces feature is globally enabled for the user or
  # organization, including the prebuilds feature. When false, the user will never see
  # codespaces and the org will not be able to access any codespaces settings.
  #
  # Does not take into account if the user/org would be blocked from using Codespaces
  # due to billing usage, org policies etc. See Codespaces::AccessChecker for more.
  sig { returns(T::Boolean) }
  def codespaces_feature_enabled?
    return !!@codespaces_feature_enabled if defined?(@codespaces_feature_enabled)

    !!@codespaces_feature_enabled = T.let(check_codespaces_feature_enabled, T.nilable(T::Boolean))
  end

  sig { returns(T.nilable(T.any(Codespaces::DeleteDependentCodespacesJob, FalseClass))) }
  def delete_dependent_codespaces
    Codespaces::DeleteDependentCodespacesJob.perform_later(owner_id: id, reason: Codespace.deletion_reasons[:bulk_dependent_deletion_user])
  end

  # For codespaces we only care about true forks of `repository`.
  #
  # User#my_fork_of will return `repository` if the `current_user` is the owner, that's not what we want. Calling this
  # lets us trust that any existing repository is in fact a fork.
  #
  # Returns: boolean, true if the user has an existing (actual) fork in `repository`'s network
  sig { params(repository: ::Repository).returns(T::Boolean) }
  def has_existing_fork_of?(repository)
    existing_fork = my_fork_of(repository)
    existing_fork.present? && existing_fork.fork?
  end

  sig { params(since: T.nilable(Time)).returns(ActiveRecord::Relation) }
  def owned_billing_entries(since: nil)
    entries = Codespaces::BillingEntry.where(codespace_owner: self)
    entries = entries.where("codespace_created_at >= ?", since) if since.present?
    entries
  end

  sig { params(since: T.nilable(Time)).returns(ActiveRecord::Relation) }
  def billed_billing_entries(since: nil)
    entries = Codespaces::BillingEntry.where(billable_owner: self)
    entries = entries.where("codespace_created_at >= ?", since) if since.present?
    entries
  end

  sig { returns(T::Boolean) }
  def free_codespace_use_enabled?
    self.feature_enabled?(:codespaces_billing_free, memoize: false) ||
      self.billable_owner.feature_enabled?(:codespaces_billing_free, memoize: false)
  end

  # Gates Salus Private Beta features, targeting specific enterprises
  # Customer must be in the codespaces_salus_beta_customers feature flag AND
  # the specific feature may have a killswitch flag that gates the feature
  sig { returns(T::Boolean) }
  def in_codespaces_salus_beta?
    self.business.present? && self.business.in_codespaces_salus_beta?
  end

  # Enables vnets but not all of Salus features
  # This bypasses the salus flag for the vnet injection feature
  sig { returns(T::Boolean) }
  def in_vnet_only_beta?
    self.business.present? && self.business.in_vnet_only_beta?
  end

  sig { returns(T::Boolean) }
  def billing_v_next_enabled_for_codespaces?
    return true if ::FeatureFlag.vexi.enabled?(:cutoff_emissions_to_meuse, default: false)
    !!billable_owner.billing_customer&.billing_platform_enabled_product&.codespaces?
  end

  private

  sig { returns(T::Boolean) }
  def check_codespaces_feature_enabled
    return false unless GitHub.codespaces_enabled?

    return codespaces_feature_enabled_for_org? if self.organization?

    true
  end

  sig { returns(T::Boolean) }
  def codespaces_feature_enabled_for_org?
    # if the org has the codespaces billing free flag enabled, allow access
    return true if free_codespace_use_enabled?

    # if the org is part of an enterprise account that has been suspended, disallow access
    return false if self.business && self.business.suspended?

    # if the org is part of an enterprise account and that has disabled codespaces or has not selected this org, disallow access
    return false if self.business &&
      Codespaces::BusinessDelegator.new(self.business).codespaces_disabled_for_org?(
        T.cast(self, Organization)
      )

    # If the org has been invoiced, they should have access.
    return true if self.invoiced?

    # make sure the org has a plan and it supports codespaces
    return false unless Codespaces::OrgPolicy.new(org: self, user: nil).plan_supports_codespaces?

    business_cluster_reliant_checks_result = with_database_error_fallback(fallback: fail_open_during_billing_cluster_outage?) do
      # always allow codespace use for TRUSTED tier organizations
      result = TrustTiers::Tier.for_billable_owner(self)
      return true if result.tier == TrustTiers::Tier::TRUSTED

      # check if the org is on an ACTIVE enterprise (GHEC) trial
      # HOWEVER if the codespaces_allow_trials flag is enabled, we allow codespaces for users on enterprise trials
      trial = Billing::PlanTrial.find_by(user: self, plan: GitHub::Plan::BUSINESS_PLUS)
      return false if trial.present? && trial.active? && !GitHub.flipper[:codespaces_allow_trials].enabled?
    end
    return business_cluster_reliant_checks_result unless business_cluster_reliant_checks_result.nil?

    # check if the org is part of a trial Enterprise Account
    # ONLY if we're blocking tier 2 & 3 orgs from using codespaces if they're part of a trial Enterprise Account (EA)
    # most of the time, we should catch these as part of the check for active GHEC trials.
    # However, it is possible that orgs can be transferred in to trial EA that was created off of a different
    # org's GHEC trial.
    return false if self.business&.trial? && GitHub.flipper[:codespaces_block_low_tier_ea_trials].enabled?

    true
  end

  sig { returns(T::Boolean) }
  def fail_open_during_billing_cluster_outage?
    !self.feature_enabled?(:codespaces_billing_cluster_outage_fail_closed)
  end
end
