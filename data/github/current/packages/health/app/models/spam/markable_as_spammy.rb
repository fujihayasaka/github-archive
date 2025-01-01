# typed: false
# frozen_string_literal: true

# Functionality for accounts that can be marked spammy.
# Included by User (and therefore Organization), and Business.
module Spam::MarkableAsSpammy
  extend ActiveSupport::Concern

  included do
    validates :spammy_reason, unicode3: true
  end

  MAX_SPAMMY_REASON_LENGTH = 65_535

  # Public: Is the account spammy?
  #
  # Returns Boolean
  def spammy?
    GitHub.spamminess_check_enabled? && super
  end

  # Indicates if we should hide the account's content. Considers
  # the account's spammy state.
  #
  # Returns a Boolean.
  def content_hidden?
    spammy?
  end

  # Clear this account from spamminess, and allowlist the account from being marked as
  # spammy again. Takes optional params and passes them to `#mark_not_spammy`.
  #
  # Returns nothing.
  def mark_as_hammy(params = {})
    params[:whitelist] ||= true
    mark_not_spammy(params)
  end

  # Has the account been allowlisted from being flagged spammy?
  #
  # Returns Boolean.
  def hammy?
    spammy_reason.to_s.start_with?("Not spammy")
  end

  # Returns true if this account is never spammy, otherwise false. Always
  # returns true when spamminess check is disabled.
  #
  # Returns Boolean
  def never_spammy?
    return true unless GitHub.spamminess_check_enabled?
    # Enterprise Managed Users are never spammy
    return true if is_a?(User) && is_enterprise_managed?
    return false if GitHub::SpamChecker.is_hard_flag?(spammy_reason)
    !can_be_flagged?
  end

  # Returns true if this account can be flagged as spammy, otherwise false.
  # Whitelisted accounts can't be flagged spammy (without first clearing the
  # whitelist). Always returns false when spamminess check is disabled.
  #
  # Returns Boolean
  def can_be_flagged?
    return false unless GitHub.spamminess_check_enabled?
    # Enterprise Managed Users are never spammy
    return false if is_a?(User) && is_enterprise_managed?
    return false if hammy?
    return false if is_a?(User) && employee?
    true
  end

  # Flag this account as spammy unless they're old/active enough to warrant a
  # human review first. In that case, queue the account instead.
  def safer_mark_as_spammy(params = {})
    reason    = params[:reason] || "No reason given"
    hard_flag = params[:hard_flag] || GitHub::SpamChecker.is_hard_flag?(reason)
    # If we're already flagged or this is a hard_flag, just move along.
    queue_it = if self.spammy || hard_flag || !self.can_be_flagged?
      false
    else
      GitHub::SpamChecker.old_or_active?(self)
    end

    if queue_it
      GlobalInstrumenter.instrument(
        "add_account_to_spamurai_queue",
        {
          account_global_relay_id: self.global_relay_id,
          additional_context: reason,
          queue_global_relay_id: SpamQueue::SUSPICIOUS_OLDER_ACCOUNTS_GLOBAL_RELAY_ID,
          origin: Spam::Origin.call(params[:origin]).upcase,
        },
      )
      GitHub.dogstats.increment("spam.active_user_review")
      GitHub::SpamChecker.notify \
        "%s %s (%d) seems fairly active, so queuing for review (Reason: %s)." %
        [self.class.to_s, self.to_s, self.id, params[:reason]]
    else
      mark_as_spammy(params)
    end
  end

  # Mark this account as spammy.
  #
  # :actor  - The User marking this account as spammy.
  # :reason - The String reason. Defaults to no reason.
  #
  # Returns nothing.
  def mark_as_spammy(params = {})
    actor     = params[:actor]
    reason    = params[:reason].to_s || "No reason given"
    hard_flag = params[:hard_flag] || GitHub::SpamChecker.is_hard_flag?(reason)
    instrument_abuse_classification = \
      params[:instrument_abuse_classification].nil? ? true : params[:instrument_abuse_classification]
    serialized_previous_data = hydro_spammy_and_suspended_data if instrument_abuse_classification

    dsa_source = params[:dsa_source]
    dsa_countries = params[:dsa_countries]
    moderation_end_timestamp = params[:moderation_end_timestamp]
    tos_reason = params[:tos_reason] || (dsa_source.present? ? params[:reason] : nil)
    notes = params[:notes]
    content_creation_date = params[:content_creation_date]
    content_formats = params[:content_formats]

    # Report some info about blank spammy_reason attempts
    if self.spammy && self.spammy_reason.blank?
      # Report to room that we had a blank spammy_reason
      room_msg = "WARNING: mark_as_spammy called on #{self.class} with empty spammy_reason: #{self} (#{self.id}) by actor #{actor}.  spammy_reason was ''. The new spammy_reason (not being applied) was #{reason}"
      GitHub::SpamChecker.notify(room_msg)
    end

    if reason == ""
      # Report to room that a blank spammy_reason is being submitted
      room_msg = "WARNING: mark_as_spammy called on #{self.class} #{self} (#{self.id}) by actor #{actor}.  Existing spammy_reason is '#{self.spammy_reason}'. The new spammy_reason IS EMPTY ('')"
      GitHub::SpamChecker.notify(room_msg)
    end

    # never_spammy_bailout
    if !hard_flag && !can_be_flagged?
      GitHub.dogstats.increment "spam.staff_actions", tags: ["spam_action:never_spammy_bailout"]
      return
    end

    if self.user?
      ActiveRecord::Base.connected_to(role: :writing) do
        OFACDowngrade.schedule_for(self)
      end
    end

    # If we're already flagged, but this is a hard-flag call, and our current
    # reason isn't a hard-flag, harden it by adding the magic phrase.
    # Return in any case.
    if self.spammy
      if hard_flag && !GitHub::SpamChecker.is_hard_flag?(spammy_reason)
        new_reason = GitHub::SpamChecker.make_hard_reason(spammy_reason)
        update_attribute :spammy_reason, new_reason
      end
      return
    end


    reason += " #{GitHub::SpamChecker::HARD_SPAM_FLAG_PHRASE}" if params[:paid_confirm]
    reason += ": #{notes}" if notes.present?
    reason += " by @#{actor.login}" if actor.is_a? User

    if hard_flag && !GitHub::SpamChecker.is_hard_flag?(reason)
      reason = GitHub::SpamChecker.make_hard_reason(reason)
    end
    previously_spammy = self.spammy
    previous_spammy_reason = self.spammy_reason
    self.spammy = true
    self.spammy_reason = reason.truncate(MAX_SPAMMY_REASON_LENGTH)

    ActiveRecord::Base.connected_to(role: :writing) do
      self.save(validate: false) unless self.new_record?
    end

    normalizer = Spam::SpammyReasonNormalizer.new(reason)
    origin ||= Spam::Origin.call(params[:origin])
    payload = {}
    payload[:previously_spammy] = previously_spammy
    payload[:currently_spammy] = true
    payload[:previous_spammy_reason] = previous_spammy_reason if previous_spammy_reason.present?
    payload[:reason] = reason
    payload[:origin] = origin.upcase
    Audit.context.push(from: "stafftools#spamurai.mark_as_spammy")
    payload.merge!(normalizer.payload)

    if instrument_abuse_classification
      instrument_abuse_classification_publish(
        serialized_previous_data.merge(actor: actor, origin: origin)
      )
    end

    # Marking a business as spammy will mark each org underneath as spam, which will publish their own event
    if dsa_source.present? && !is_a?(Business)
      GlobalInstrumenter.instrument "staff.mark_as_spammy", {
        actor: actor,
        account: self,
        dsa_source: dsa_source,
        dsa_countries: dsa_countries,
        tos_reason: tos_reason.to_s.include?(" - flagged with") ? tos_reason.split(" - flagged with").first : tos_reason,
        moderation_type: :SUSPENDED,
        moderation_end_timestamp: moderation_end_timestamp,
        content_created_at: content_creation_date,
        content_formats: content_formats,
      }
    end

    payload[:prefix] = :staff
    payload[self.event_prefix] = self
    payload[:user_type] = type if respond_to?(:type)
    payload[:hard_flag] = hard_flag
    payload.merge!(GitHub.guarded_audit_log_staff_actor_entry(actor))
    instrument :mark_as_spammy, payload

    unless self.new_record?
      update_tables_user_hidden
    end

    if is_a?(Business)
      params[:tos_reason] = tos_reason
      ToggleSpamFlagOnBusinessOrganizationsJob.perform_later self, true, params
      GitHub.dogstats.increment("business.mark_as_spammy")
    elsif is_a?(Organization)
      OrganizationMailer.flagged_as_spammy(self, tos_reason, dsa_source).deliver_later if dsa_source.present?
    else
      AccountMailer.flagged_as_spammy(self, tos_reason, dsa_source).deliver_later if dsa_source.present?
    end
  end

  # Queues up all user_hidden update jobs.
  def update_tables_user_hidden
    return unless GitHub.spamminess_check_enabled?
    # UpdateTableUserHiddenJob does not currently support being passed a Business ID
    return if is_a?(Business)
    UpdateTableUserHiddenJob.perform_later(self.id, Spam::Spammable.tables_classes_including.keys)
  end

  # Clear this account from spamminess.
  #
  # :actor     - The User marking this account as not spammy.
  # :whitelist - Boolean - should the account be whitelisted as well?
  #
  # Returns nothing.
  def mark_not_spammy(params = {})
    actor     = params[:actor]
    whitelist = params[:whitelist]
    instrument_abuse_classification = \
      params[:instrument_abuse_classification].nil? ? true : params[:instrument_abuse_classification]

    origin ||= Spam::Origin.call(params[:origin])

    # We need to keep up with our own changed? since spammy_reason is
    # a serialized attribute. Save dem queries.
    save_me = false

    if instrument_abuse_classification
      serialized_previous_classification = Hydro::EntitySerializer.account_spammy_classification(self)
      serialized_previous_spammy_reason = Hydro::EntitySerializer.account_spammy_reason(self)
      serialized_previously_suspended = Hydro::EntitySerializer.account_suspended(self)
    end

    old_reason = self.spammy_reason
    self.spammy_reason = whitelist ? "Not spammy" : nil
    save_me ||= (self.spammy_reason != old_reason)

    normalizer = Spam::SpammyReasonNormalizer.new(old_reason)
    payload = {}
    payload[:previously_spammy] = self.spammy
    payload[:currently_spammy] = false
    payload[:previous_spammy_reason] = old_reason if old_reason.present?
    payload[:origin] = origin.upcase
    payload.merge!(normalizer.payload) if self.spammy

    if (was_spammy = self.spammy)
      self.spammy = false
      save_me = true
    end

    if save_me
      # Don't let other invalid attrs get in the way of updating spamminess
      self.save(validate: false)
    end

    if instrument_abuse_classification
      instrument_abuse_classification_publish({
        actor: actor,
        origin: origin,
        rule_name: params[:rule_name],
        rule_version: params[:rule_version],
        serialized_previous_classification: serialized_previous_classification,
        serialized_previous_spammy_reason: serialized_previous_spammy_reason,
        serialized_previously_suspended: serialized_previously_suspended,
      })
    end

    payload[:whitelist] = whitelist
    payload[:prefix] = :staff
    payload[self.event_prefix] = self
    payload[:note] = "Old reason: #{old_reason}"
    payload.merge!(GitHub.guarded_audit_log_staff_actor_entry(actor))
    instrument :mark_not_spammy, payload

    # If we are only whitelisting a user already not-spammy, then the 'hidden'
    # state for that user's content should already be handled (even if there
    # was state flapping). So no need to kick off a possibly expensive job.
    if !whitelist || was_spammy
      update_tables_user_hidden
    end

    # Mark a false positive on any matching flagging SpamPatterns
    if was_spammy
      SpamPattern.flag_matches_for(self).each { |sp| sp.record_false_positive! }
    end

    # Tell The Spam Room what happened
    account_type = if is_a?(Business)
      "Enterprise"
    elsif organization?
      "Organization"
    else
      "User"
    end
    room_msg = "#{account_type} #{self} (#{self.id})"
    room_msg += " [#{self.email}]" if respond_to?(:email) && email.present?
    if was_spammy
      room_msg += " un-flagged (after #{Spam.flagged_interval_in_words(self)})"
      room_msg += " and" if whitelist
    end
    room_msg += " whitelisted" if whitelist
    room_msg += " by #{actor.login}" if actor
    room_msg += "."
    room_msg += " Old reason: '#{old_reason}'" if was_spammy

    skip_notification = false
    # If erebor is whitelisting zillions of legit accounts, spam-notifications
    # doesn't need the noise.
    skip_notification ||= whitelist && !was_spammy && actor && actor.login == ::Spam::SENIOR_ANALYST_LOGIN
    # Skip bots hamflagging themselves
    skip_notification ||= try(:bot?) && actor.try(:login) == self.login && whitelist
    # terms to skip notifications for, usually expected unflags such as ATO etc
    skippable_reasons = [
      "flagged_ato_campaign",
      "issues/533",
    ]
    skip_notification ||= skippable_reasons.any? { |reason| old_reason.to_s.include?(reason) }

    unless skip_notification
      GitHub::SpamChecker.notify(room_msg)
    end

    if self.user? && !self.trade_controls_restriction.any?
      ActiveRecord::Base.connected_to(role: :writing) do
        self.scheduled_ofac_downgrade&.destroy
      end
    end

    if self.trade_screening_record.spammy?
      self.trade_screening_record.not_screened!
    end

    if is_a?(Business)
      ToggleSpamFlagOnBusinessOrganizationsJob.perform_later self, false, params
      GitHub.dogstats.increment("business.mark_not_spammy")
    end
  end

  # Public: Get information about this account's spammy and suspended status.
  # For use in Hydro events like `github.v1.AbuseClassification` and `github.v1.EnterpriseAbuseClassification`.
  #
  # Returns a Hash.
  def hydro_spammy_and_suspended_data
    {
      serialized_previous_classification: Hydro::EntitySerializer.account_spammy_classification(self),
      serialized_previous_spammy_reason: Hydro::EntitySerializer.account_spammy_reason(self),
      serialized_previously_suspended: Hydro::EntitySerializer.account_suspended(self),
    }
  end

  # Public: Publishes the appropriate abuse classification Hydro event for the account.
  #
  # overrides - optional Hash of additional data to include in the event, including fields like
  #             :serialized_previous_classification, :serialized_previous_spammy_reason, and
  #             :serialized_previously_suspended.
  #
  # Returns nothing.
  def instrument_abuse_classification_publish(overrides = {})
    event = if is_a?(Business)
      "enterprise_abuse_classification.publish"
    else
      "abuse_classification.publish"
    end

    data = { queue_action: :QUEUE_ACTION_NONE }.merge(overrides)
    if is_a?(Business)
      data[:business] = self
    else
      data[:account] = self
    end

    GlobalInstrumenter.instrument event, data
  end
end
