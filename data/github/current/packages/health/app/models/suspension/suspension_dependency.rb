# typed: false
# frozen_string_literal: true

# Functionality for accounts that can be suspended.
# Included by User (and therefore Organization), and Business.
module Suspension::SuspensionDependency
  extend ActiveSupport::Concern

  # Is this account suspended?
  #
  # Returns true if so, false otherwise.
  def suspended?
    !!suspended_at
  end

  # Should the suspend button show up for this account in stafftools?
  #
  # Returns true if so, false otherwise.
  def suspendable?
    if is_a?(Business)
      !staff_owned? && !GitHub.enterprise?  # False if staff owned or running GHES
    else
      !organization? && !site_admin? && !employee?
    end
  end

  # Suspend a user or business.
  #
  # Returns false if a reason was provided or account suspension is managed
  # externally, true otherwise. Error strings are added to :base if there are
  # any.
  def suspend(
    reason,
    actor: nil,
    hard_flag: false,
    instrument_abuse_classification: true,
    origin: nil,
    sdn_suspension: false,
    send_email: false,
    dsa_source: nil,
    dsa_countries: nil,
    moderation_end_timestamp: nil,
    tos_reason_for_business_org: nil,
    notes: nil,
    content_creation_date: nil,
    content_formats: nil,
    items_reported_to_ncmec: nil
  )
    errors.delete(:base)
    errors.add(:base, "You have to specify a reason for the suspension.") if reason.blank?

    # We can only suspend hammy accounts when hard_flag is true
    cannot_suspend = hammy? && !hard_flag
    if cannot_suspend
      account_type = is_a?(Business) ? "enterprises" : "users"
      errors.add(:base, "Hammy #{account_type} cannot be suspended. Please clear their hamminess first.")
    end

    serialized_previously_suspended = Hydro::EntitySerializer.account_suspended(self)

    return false unless errors[:base].empty?

    self.class.transaction do
      update_attribute(:suspended_at, Time.now)
    end

    # Stop all billing on the account to prevent us from attempting to bill the customer further
    cancel_billing

    unless is_a?(Business)
      revoke_active_sessions(:suspended)
      calculate_followerings_count(cascade: true)
      # Cancel all marketplace subscription items to prevent incorrect payouts
      Billing::CancelSubscriptionItemsJob.perform_later(user_id: self.id, force: true, subscribable_type: Marketplace::ListingPlan.name, sdn_suspension: sdn_suspension, send_email: send_email, event: :suspension, tos_reason: tos_reason_for_business_org || reason, dsa_source: dsa_source)
      ToggleHiddenUserInNotificationsJob.perform_later(self.id, "hide")
      RecalculateUserDiscussionsJob.perform_later(self) unless GitHub.enterprise?
      if business_user_account = BusinessUserAccount.find_by(user_id: self.id)
        business_user_account.business&.update_license_usage
      end
      DelistSpammySponsorsListingJob.perform_later(sponsorable: self, actor: actor) if GitHub.sponsors_enabled?
    end

    if is_a?(User) && is_enterprise_managed? && actor.present? && actor.is_enterprise_managed?
      instrument :suspend, { actor: actor, actor_id: actor.id, reason: notes.present? ? "#{reason}: #{notes}" : reason }
    else
      instrument :suspend, GitHub.guarded_audit_log_staff_actor_entry(actor).merge(reason: notes.present? ? "#{reason}: #{notes}" : reason)
    end

    if instrument_abuse_classification
      instrument_abuse_classification_publish({
        actor: actor,
        account: self,
        queue_action: :QUEUE_ACTION_NONE,
        origin: origin,
        serialized_previously_suspended: serialized_previously_suspended,
      })
    end

    # Suspending a business results in each underlying org being suspended, which will publish their own event
    if dsa_source.present? && !is_a?(Business)
      base_reason = reason.to_s.include?(" - flagged with") ? reason.split(" - flagged with").first : reason
      GlobalInstrumenter.instrument "user.suspend", {
        actor: actor,
        account: self,
        tos_reason: tos_reason_for_business_org || base_reason,
        dsa_source: dsa_source,
        dsa_countries: dsa_countries,
        moderation_type: :SUSPENDED,
        moderation_end_timestamp: moderation_end_timestamp,
        content_created_at: content_creation_date,
        content_formats: content_formats,
        items_reported_to_ncmec: items_reported_to_ncmec,
      }
    end

    if is_a?(Business)
      ToggleSuspensionStatusOnBusinessOrganizationsJob.perform_later self, true, reason, sdn_suspension, actor: actor, send_email: send_email, dsa_source: dsa_source
      GitHub.dogstats.increment("business.suspend")
    end

    true
  end

  # Unsuspend a user or business.
  #
  # Returns false if a reason was provided or account suspension is managed
  # externally or there are no free seats, true otherwise. Error strings are
  # added to :base if there are any.
  def unsuspend(reason, actor: nil, instrument_abuse_classification: true, origin: nil, sdn_suspension: false)
    errors.delete(:base)
    errors.add(:base, "You have to specify a reason for the unsuspension.") if reason.blank?
    enforce_seat_limit "No seats available. Purchase more seats or suspend another user." unless is_a?(Business)

    return false unless errors[:base].empty?

    if suspended?
      serialized_previously_suspended = Hydro::EntitySerializer.account_suspended(self)

      self.class.transaction do
        update_attribute(:suspended_at, nil)
      end

      # Restart billing on the account.
      # This ensures the account can be billed going forward and immediately generates a new invoice for any products
      # that need to be billed. We disable payment collection in case adjustments need to be made the to invoices.
      synchronize_all_plan_subscriptions(collect: false)

      unless is_a?(Business)
        calculate_followerings_count(cascade: true)
        ToggleHiddenUserInNotificationsJob.perform_later(self.id, "unhide")
        if business_user_account = BusinessUserAccount.find_by(user_id: self.id)
          business_user_account.business&.update_license_usage
        end
        RelistNonSpammySponsorsListingJob.perform_later(sponsorable: self, actor: actor) if GitHub.sponsors_enabled?
      end

      if is_a?(User) && is_enterprise_managed? && actor.present? && actor.is_enterprise_managed?
        instrument :unsuspend, { actor: actor, actor_id: actor.id, reason: reason }
      else
        instrument :unsuspend, GitHub.guarded_audit_log_staff_actor_entry(actor).merge(reason: reason)
      end

      if instrument_abuse_classification
        instrument_abuse_classification_publish({
          actor: actor,
          origin: origin,
          queue_action: :QUEUE_ACTION_NONE,
          account: self,
          serialized_previously_suspended: serialized_previously_suspended,
        })
      end
    end

    if is_a?(Business)
      ToggleSuspensionStatusOnBusinessOrganizationsJob.perform_later self, false, reason, sdn_suspension, actor: actor
      GitHub.dogstats.increment("business.unsuspend")
    end

    true
  end
end
