# typed: strict
# frozen_string_literal: true

module TradeControls::TradeScreeningDependency
  include TradeControls::AbstractTradeScreeningDependency
  include GitHub::Memoizer

  extend T::Helpers

  requires_ancestor { User }

  extend ActiveSupport::Concern

  included do
    # similar to :profile but this is primarily populated and used
    # when the user is about to make a financial transaction
    T.bind(self, T.class_of(User))
    self.has_one :trade_screening_record, dependent: :destroy, class_name: "AccountScreeningProfile", autosave: false, as: :owner,
      inverse_of: :owner
  end

  sig { override.returns(T::Boolean) }
  def is_allowed_to_remove_billing_information?
    return false if upcoming_charges?

    super
  end

  # Public: Checks if this user is allowed to be automatically approved as sponsorable.
  # They are only allowed to be auto approved if their SDN (special designated national) screening
  # status is part of the account screening profile SDN_ALLOWED_AUTO_SPONSORSHIP_LIST.
  sig { override.returns(T::Boolean) }
  def has_sdn_auto_sponsorable_restrictions?
    return false unless feature_enabled?(:live_sdn_screening)

    !trade_screening_record.allowed_auto_sponsorship?
  end

  # Public: Returns object type for instrumentation logging
  sig { override.returns(Symbol) }
  def instrumentation_object_type
    return :USER if user?
    :UNKNOWN
  end

  # Public: Creates a link between a Standard Terms of Service organization and an admin user's screening record.
  # The link allows a Standard Terms of Service organization to depend on the admin's screening record for SDN
  # and commercial interaction checks.
  #
  # organization - the target Standard Terms of Service organization
  # screening_flow - the context from which the linking is being done
  sig { override.params(organization: Organization, screening_flow: T.nilable(T.any(Symbol, String))).returns(T::Boolean) }
  def link_trade_screening_record_to_org(organization:, screening_flow: nil)
    return false unless self.user?
    T.bind(self, User)

    return false unless organization.org_is_on_standard_tos?
    return false unless organization.adminable_by?(self) || organization.billing_manager?(self)
    return false unless self.trade_screening_record.persisted?
    return false if self.has_trade_screening_restriction?

    user_screening_record = self.trade_screening_record
    org_screening_record = organization.trade_screening_record(ignore_linked_record: true)
    if org_screening_record.persisted?
      ActiveRecord::Base.connected_to(role: :writing) do
        org_screening_record.destroy!
      end
      GitHub.dogstats.increment(
        "sdn.individual_owned_org_pseudo_record_dropped",
        tags: [
          "old_status: #{org_screening_record.msft_trade_screening_status}",
          "new_status:#{user_screening_record.msft_trade_screening_status}",
          "screening_flow:#{screening_flow}",
        ],
      )
    end

    return false unless self.unlink_trade_screening_record_from_org(organization: organization)

    result = T.let(false, T::Boolean)
    ActiveRecord::Base.connected_to(role: :writing) do
      result = TradeControls::ScreeningRecordLinkManager.link_trade_screening_record_to_org(
        screening_record: user_screening_record,
        org: organization
      )
    end
    organization.reset_billing_memoized_attributes
    result
  end

  # Public: Removes the link between a Standard Terms of Service organization and an admin user's screening record.
  #
  # organization - the target Standard Terms of Service organization
  sig { override.params(organization: Organization).returns(T::Boolean) }
  def unlink_trade_screening_record_from_org(organization:)
    return false unless self.user?
    T.bind(self, User)

    return false unless organization.org_is_on_standard_tos?
    return true unless organization.has_linked_trade_screening_record?

    can_manage_org = organization.adminable_by?(self) || organization.billing_manager?(self)
    user_owns_record = self.has_trade_screening_record_linked_to_org?(organization: organization)
    return false unless can_manage_org || user_owns_record || site_admin?

    result = T.let(false, T::Boolean)
    ActiveRecord::Base.connected_to(role: :writing) do
      result = TradeControls::ScreeningRecordLinkManager.unlink_trade_screening_record_from_org(actor: self, org: organization)
    end
    organization.reset_billing_memoized_attributes
    result
  end

  # Public: Checks if the admin user has a trade screening record which is linked to an organization on
  # standard terms of service
  #
  # organization - the target Standard Terms of Service organization
  sig { override.params(organization: Organization).returns(T::Boolean) }
  def has_trade_screening_record_linked_to_org?(organization:)
    return false unless self.user?
    return false unless organization.org_is_on_standard_tos?
    return false unless self.trade_screening_record.persisted?

    self.trade_screening_record.id == organization.trade_screening_record.id
  end

  # Public: Suspend the user in compliance with SDN (specially designated nationals) protocols.
  # This type of suspension performs the following:
  #   * Suspends the user
  #   * Locks private repositories
  #   * Archives public repositories
  #   * Places a legal hold on the account
  #
  # staff_user: The staffer who is suspending the actor.
  # reason: reason for the suspension
  sig { override.params(staff_user: User, reason: String).returns(T::Boolean).checked(:always).on_failure(:raise) }
  def sdn_suspend(staff_user:, reason:)
    return false unless self.user?

    raise AccountScreeningProfile::AccountScreeningProfileUpdateError, "Staff user is required!" if staff_user.blank?
    raise AccountScreeningProfile::AccountScreeningProfileUpdateError, "Reason is required!" if reason.blank?

    toggle_sdn_suspension_status(staff_user: staff_user, should_suspend: true, reason: reason)

    screening_record = self.trade_screening_record(ignore_linked_record: true)
    return false unless screening_record.true_match?

    if !self.suspend(reason, hard_flag: true)
      msg = self.errors[:base].to_sentence
      reason += ", however, suspension failed."
      tags = ["reason: #{reason}"]

      # Keep track of failed suspensions in datadog and the reason
      GitHub.dogstats.increment("sdn.true_match.suspension.failed", tags: tags)
      raise AccountScreeningProfile::AccountScreeningProfileUpdateError.new(msg)
    end

    self.unlink_contact_from_all_linked_orgs

    all_repos = self.private_repositories
    all_repos.find_each do |repository|
      repository.lock_excluding_descendants!(Repository::LockDependency::TRADE_RESTRICTION)
    end

    # Add a staff note to the user for visibility
    self.add_sdn_suspension_staff_note(note: reason)
    self.place_legal_hold(actor: staff_user)

    # Keep track of successful suspensions in datadog
    GitHub.dogstats.increment("sdn.true_match.suspension.success")

    # Notify legal team if sponsors maintainer has been suspended
    TradeControls::LegalNotification.create_for_sponsors_maintainer(account: self) if sponsors_listing
    true
  end

  # Public: SDN unsuspends an actor. This action is called through stafftools.
  #
  # staff_user: The staffer who is unsuspending the actor.
  # reason: reason for the unsuspension
  sig { override.params(staff_user: User, reason: String).returns(T::Boolean).checked(:always).on_failure(:raise) }
  def sdn_unsuspend(staff_user:, reason:)
    return false unless self.user?

    raise AccountScreeningProfile::AccountScreeningProfileUpdateError, "Staff user is required!" if staff_user.blank?
    raise AccountScreeningProfile::AccountScreeningProfileUpdateError, "Reason is required!" if reason.blank?

    toggle_sdn_suspension_status(staff_user: staff_user, should_suspend: false, reason: reason)

    if !self.suspended?
      # Keep track of inconsistent unsuspended status when in true_match
      GitHub.dogstats.increment("sdn.true_match.unsuspension.mismatch", tags: [
        "msft_trade_screening_status:#{self.trade_screening_status}",
        "msft_trade_screening_status_was:true_match",
        "reason:true_match_was_not_suspended"])
      Failbot.report! AccountScreeningProfile::AccountScreeningProfileUpdateError.new("True match screening profile was not suspended")
    end

    # TODO we should remove mark not spammy after the transitional period to the new suspension flow
    self.mark_not_spammy(reason: reason) if self.spammy?
    if !self.unsuspend(reason)
      msg = self.errors[:base].to_sentence
      reason += ", however, unsuspension failed."
      tags = ["reason: #{reason}"]

      # Keep track of failed unsuspensions in datadog and the reason
      GitHub.dogstats.increment("sdn.true_match.unsuspension.failed", tags: tags)
      raise AccountScreeningProfile::AccountScreeningProfileUpdateError.new(msg)
    end

    # Keep track of successful unsuspensions in datadog
    GitHub.dogstats.increment("sdn.true_match.unsuspension.success")
    self.clear_legal_hold(actor: staff_user)

    all_repos = self.private_repositories
    all_repos.find_each do |repo|
      repo.unlock_excluding_descendants! if repo.locked_on_billing? || repo.locked_on_trade_restriction?
    end

    self.add_sdn_unsuspension_staff_note(note: reason)
    true
  end

  sig { override.returns(T::Boolean) }
  def sdn_suspended?
    self.async_sdn_suspended?.sync
  end

  # Public: async check whether this user has sdn_restriction
  sig { returns(Promise[T::Boolean]) }
  def async_sdn_suspended?
    # we can't rely on true_match alone to determine if a user was sdn suspended. This is because we don't run
    # suspension steps on true_match status, instead a staffer has to sdn suspend an account manually after
    # a user is set to true_match.
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless self.suspended?

    async_trade_screening_record.then(&:true_match?)
  end

  # Override the built-in async_* association to ensure it is never nil.
  # Whenever the trade_screening_record doesn't exist, we build a new one.
  # see overridden trade_screened_record association.
  sig { params(ignore_linked_record: T::Boolean).returns(Promise[AccountScreeningProfile]) }
  def async_trade_screening_record(ignore_linked_record: false)
    ActiveRecord::Base.connected_to(role: :reading) do
      super().then do |tsr|
        tsr || trade_screening_record(ignore_linked_record: ignore_linked_record)
      end
    end
  end

  # Unlinks user from all orgs they currently have their billing information linked to when an account is sdn suspended.
  sig { void }
  def unlink_user_from_all_linked_orgs
    actor = self
    return unless actor.user? && actor.is_a?(User)

    orgs_linked_to_screening_record.each do |org|
      org.unlink_billing_contact(actor:)
    end
  end

  sig { returns(T::Array[Organization]) }
  def orgs_linked_to_screening_record
    return [] unless self.user?
    return [] unless self.trade_screening_record.persisted?

    self.owned_or_billing_manager_organizations.select \
      { |org| org.trade_screening_record.id == self.trade_screening_record.id }
  end

  sig { override.void }
  def send_sponsors_maintainer_restricted_email
    TradeScreeningMailer
      .sponsors_maintainer_restricted(account: T.cast(self, T.any(User, Organization)), emails: GitHub.trade_cela_emails)
      .deliver_later
  end

  private

  sig { override.params(record_to_screen: AccountScreeningProfile).returns(T::Boolean) }
  def perform_spammy_live_request(record_to_screen:)
    return false unless user? && spammy?

    update_trade_screening_record({ msft_trade_screening_status: "spammy" })
    result = TradeCompliance::TradeScreening::LiveResponse.new(
      external_uuid: record_to_screen.external_uuid,
      eid: "NO_SDN_REQUEST_MADE",
      status: "spammy",
      status_reason: "Spammy user screening record update"
    )
    instrument_result_to_hydro(result, record_to_screen)
    true
  end
end
