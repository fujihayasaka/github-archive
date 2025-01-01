# typed: strict
# frozen_string_literal: true

module Organization::TradeScreeningDependency
  include TradeControls::AbstractTradeScreeningDependency
  include GitHub::Memoizer
  include Kernel
  extend T::Helpers

  requires_ancestor { Organization }

  # Public: Either returns the trade screening record linked to an
  # SToS (Standard Terms of Service) org or returns the has_one :trade_screening_record
  # association for this actor.
  #
  # If the associated record doesn't exist, it falls back to building a new
  # one. This ensures callers do not need the safe-navigation operator. It
  # also ensures a consistent API between Users with an `not_screened` record
  # and those without an associated screening at all; as those two scenarios
  # are semantically the same.
  #
  # WARNING: Don't call this method directly to check if the actor can perform a
  # commercial transaction. That is, don't do `trade_screening_record.msft_trade_screening_status`.
  # This is especially true when the target is an Organization or Business in which case we need to
  # ensure that both the org/business and the current user have a non-blocking status. Instead, use
  # `check_actor_screening_status` for GET requests or `ensure_actor_can_perform_commercial_interaction`
  # for POST requests. Without this, in the scenario where the org/business has a non-blocking status but
  # the user does not, this method will return the non-blocking record because of the order of precedence.
  sig { override.params(ignore_linked_record: T::Boolean).returns(AccountScreeningProfile) }
  def trade_screening_record(ignore_linked_record: false)
    self_screening_record = super() || build_trade_screening_record(owner: self)
    return self_screening_record if self_screening_record.persisted? || ignore_linked_record

    linked_screening_record = linked_trade_screening_record
    return linked_screening_record if linked_screening_record.present?

    self_screening_record
  end

  # Public: Returns the trade screening record linked to this SToS (Standard Terms of Service) org.
  #
  # If the associated record doesn't exist, it falls back to building a new
  # one. This ensures callers do not need the safe-navigation operator.
  sig { returns(T.nilable(AccountScreeningProfile)) }
  def linked_trade_screening_record
    return business_trade_screening_record if delegate_billing_to_business?
    return nil unless org_is_on_standard_tos?
    return @linked_trade_screening_record unless @linked_trade_screening_record.nil?

    @linked_trade_screening_record = T.let(nil, T.nilable(AccountScreeningProfile))
    return @linked_trade_screening_record = linked_billing_contact&.billable_owner&.trade_screening_record if feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
    @linked_trade_screening_record = TradeControls::ScreeningRecordLinkManager.stos_org_trade_screening_record(org: T.cast(self, Organization))
  end

  # Public: Removes the billing link for a Standard Terms of Service organization.
  #
  # reason - the reason for unlinking the record
  sig { override.params(reason: String).returns(T::Boolean) }
  def unlink_trade_screening_record_from_org_without_actor(reason:)
    return false unless org_is_on_standard_tos?

    result = T.let(false, T::Boolean)
    ActiveRecord::Base.connected_to(role: :writing) do
      result = TradeControls::ScreeningRecordLinkManager.unlink_trade_screening_record_from_org_without_actor(org: T.cast(self, Organization), reason:)
    end
    reset_billing_memoized_attributes
    result
  end

  # Public: Returns the trade screening record for the orgs owning business
  #
  # If the associated record doesn't exist, it falls back to building a new
  # one. This ensures callers do not need the safe-navigation operator.
  sig { returns(T.nilable(AccountScreeningProfile)) }
  def business_trade_screening_record
    return nil unless delegate_billing_to_business?
    return @business_trade_screening_record unless @business_trade_screening_record.nil?

    @business_trade_screening_record = T.let(nil, T.nilable(AccountScreeningProfile))
    @business_trade_screening_record = T.must(business).trade_screening_record
  end

  sig { override.returns(T::Boolean) }
  def is_allowed_to_remove_billing_information?
    # A "group of friends" org should not be able to remove billing info
    # they should have a linked screening profile that can be unlinked
    return false if org_is_on_standard_tos?

    super
  end

  # Public: Checks if this user is allowed to be automatically approved as sponsorable.
  # They are only allowed to be auto approved if their SDN (special designated national) screening
  # status is part of the account screening profile SDN_ALLOWED_AUTO_SPONSORSHIP_LIST.
  sig { override.returns(T::Boolean) }
  def has_sdn_auto_sponsorable_restrictions?
    false # orgs and bots can't have SDN restrictions
  end

  # Public: used to check if the owner of the trade screening record is on
  # business terms of service
  sig { override.returns(T::Boolean) }
  def org_is_on_business_tos?
    T.bind(self, Organization)

    return @org_is_on_business_tos unless @org_is_on_business_tos.nil?

    tos = self.terms_of_service.name
    @org_is_on_business_tos = T.let(false, T.nilable(T::Boolean))
    @org_is_on_business_tos = Organization::TermsOfService::BUSINESS_TERMS_OF_SERVICE_TYPES.include?(tos)
  end

  # Public: used to check if the org owner of the trade screening record is on
  # standard terms of service
  sig { override.returns(T::Boolean) }
  def org_is_on_standard_tos?
    T.bind(self, Organization)

    return @org_is_on_standard_tos unless @org_is_on_standard_tos.nil?

    @org_is_on_standard_tos = T.let(false, T.nilable(T::Boolean))
    @org_is_on_standard_tos = !org_is_on_business_tos?
  end

  # Public: Returns object type for instrumentation logging
  sig { override.returns(Symbol) }
  def instrumentation_object_type
    return :CTOS_ORGANIZATION if org_is_on_business_tos?
    return :ORGANIZATION if org_is_on_standard_tos?
    :UNKNOWN
  end

  # Public: Checks if the org on Standard Terms of Service has a linked trade screening record
  sig { override.returns(T::Boolean) }
  def has_linked_trade_screening_record?
    return @has_linked_trade_screening_record unless @has_linked_trade_screening_record.nil?
    return @has_linked_trade_screening_record = false unless self.organization?

    @has_linked_trade_screening_record = T.let(nil, T.nilable(T::Boolean))
    @has_linked_trade_screening_record = TradeControls::ScreeningRecordLinkManager.stos_org_trade_screening_record_exists?(org: T.cast(self, Organization))
  end

  # Public: Used to suspend an organization.
  sig { override.params(staff_user: User, reason: String).returns(T::Boolean).checked(:always).on_failure(:raise) }
  def sdn_suspend(staff_user:, reason:)
    raise Organization::OrganizationSuspensionError, "Staff user is required!" if staff_user.blank?
    raise Organization::OrganizationSuspensionError, "Reason is required!" if reason.blank?

    return false unless self.toggle_sdn_suspension_status(staff_user: staff_user, should_suspend: true, reason: reason)
    return false unless self.trade_screening_record(ignore_linked_record: true).true_match?

    if !self.suspend(reason, hard_flag: true)
      msg = self.errors[:base].to_sentence
      reason += ", however, suspension failed."
      tags = ["reason: #{reason}"]

      # Keep track of failed suspensions in datadog and the reason
      GitHub.dogstats.increment("sdn.true_match.suspension.failed", tags: tags)
      raise AccountScreeningProfile::AccountScreeningProfileUpdateError.new(msg)
    end

    # Add a staff note to the org for visibility
    self.add_sdn_suspension_staff_note(note: reason)

    apply_restrictions_for_sdn_suspension(staff_user: staff_user, reason: reason)

    # Cancel all marketplace subscription items to prevent incorrect payouts
    Billing::CancelSubscriptionItemsJob.perform_later(user_id: self.id, force: true, subscribable_type: Marketplace::ListingPlan.name, sdn_suspension: true, event: :suspension)

    self.place_legal_hold(actor: staff_user)
    true
  end

  # Public: Used to un-suspend an organization.
  sig { override.params(staff_user: User, reason: String).returns(T::Boolean).checked(:always).on_failure(:raise) }
  def sdn_unsuspend(staff_user:, reason:)
    raise Organization::OrganizationSuspensionError, "Staff user is required!" if staff_user.blank?
    raise Organization::OrganizationSuspensionError, "Reason is required!" if reason.blank?

    self.toggle_sdn_suspension_status(staff_user: staff_user, should_suspend: false, reason: reason)

    if !self.unsuspend(reason)
      msg = self.errors[:base].to_sentence
      reason += ", however, unsuspension failed."
      tags = ["reason: #{reason}"]

      # Keep track of failed unsuspensions in datadog and the reason
      GitHub.dogstats.increment("sdn.true_match.unsuspension.failed", tags: tags)
      raise AccountScreeningProfile::AccountScreeningProfileUpdateError.new(msg)
    end

    # Lift trade controls restriction
    compliance = TradeControls::ManualCompliance.new(actor: staff_user, reason: reason)
    self.trade_controls_restriction.override!(compliance: compliance) if self.has_any_trade_restrictions?

    all_repos = self.repositories
    all_repos.each do |repo|
      repo.unset_archived if repo.public? && repo.archived?
      repo.unlock_excluding_descendants! if repo.private? && repo.locked_on_trade_restriction?
    end

    self.add_sdn_unsuspension_staff_note(note: reason)
    self.clear_legal_hold(actor: User.staff_user)
    true
  end

  sig { override.returns(T::Boolean) }
  def sdn_suspended?
    self.async_sdn_suspended?.sync
  end

  # Public: async check whether this organization has SDN suspension
  sig { returns(Promise[T::Boolean]) }
  def async_sdn_suspended?
    async_has_full_trade_restrictions?.then do |has_full_trade_restrictions|
      next Promise.resolve(false) unless suspended? || has_full_trade_restrictions

      async_trade_screening_record(ignore_linked_record: true).then(&:true_match?)
    end
  end

  sig { override.void }
  def send_sponsors_maintainer_restricted_email
    raise NotImplementedError
  end

  # Public: Used to determine if we should apply some restricted behavior to
  # an organization which during the org creation flow had a blocking SDN screening
  # status. This organization will be on the free plan since we don't create orgs
  # on paid plans if they have a blocking SDN status.
  sig { returns(T::Boolean) }
  def has_sdn_new_org_with_free_plan_restriction?
    return false unless self.live_sdn_screening_enabled?
    return false unless trade_screening_record.hit_in_review? || trade_screening_record.is_true_match_restricted?
    return false unless trade_screening_record.metadata["screening_context"] == "new_org_creation"

    if organization = trade_screening_record.organization
      organization.free_plan?
    else
      false
    end
  end

  private

  sig { params(staff_user: User, reason: String).void }
  def apply_restrictions_for_sdn_suspension(staff_user:, reason:)
    return if self.has_full_trade_restrictions?

    private_repos = self.private_repositories
    private_repos.find_each do |repository|
      repository.lock_excluding_descendants!(Repository::LockDependency::TRADE_RESTRICTION)
    end
  end
end
