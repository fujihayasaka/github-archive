# typed: true
# frozen_string_literal: true

module SponsorsListing::StateDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  EMAIL_WAIT_TIME = 5.minutes
  AUTO_APPROVE_WAIT_TIME_RANGE_IN_HOURS = 1..20
  SDN_DISABLE_REASON = "commercially restricted"

  requires_ancestor { SponsorsListing }

  included do
    T.bind(self, T.class_of(SponsorsListing))

    workflow :state do
      state :waitlisted, 8 do
        event :accept, transitions_to: :draft, if: :country_supported?
        event :ban, transitions_to: :banned
        event :request_approval, transitions_to: :pending_approval, if: :ready_for_submission?
      end

      state :banned, 12 do
        event :un_ban, transitions_to: :waitlisted
        event :ban, transitions_to: :banned
      end

      state :draft, 0 do
        event :revert_to_waitlisted, transitions_to: :waitlisted
        event :ban, transitions_to: :banned
        event :request_approval, transitions_to: :pending_approval, if: :ready_for_submission?
        event :disable, transitions_to: :disabled
        event :publish, transitions_to: :approved, if: :auto_approvable?
      end

      state :pending_approval, 4 do
        event :approve, transitions_to: :approved
        event :disable, transitions_to: :disabled
        event :cancel_approval_request, transitions_to: :draft
        event :ban, transitions_to: :banned
        event :require_additional_review, transitions_to: :requires_additional_review
        event :enqueue_for_auto_approval, transitions_to: :queued_for_auto_approval, if: :auto_approvable?
      end

      state :requires_additional_review, 5 do
        event :approve, transitions_to: :approved
        event :disable, transitions_to: :disabled
        event :cancel_approval_request, transitions_to: :draft
        event :ban, transitions_to: :banned
      end

      state :approved, 6 do
        event :unpublish, transitions_to: :pending_approval
        event :disable, transitions_to: :disabled
        event :ban, transitions_to: :banned
        event :redraft, transitions_to: :draft, unless: :has_active_subscription_items?
        event :sdn_disable, transitions_to: :sdn_disabled, if: :sdn_disable_sponsors_listings_enabled?
        event :mark_spammy, transitions_to: :spammy
      end

      state :disabled, 7 do
        event :reactivate, transitions_to: :draft
        event :ban, transitions_to: :banned
      end

      # During trade screening a user will be screened to see if they are a Specially Designated National
      # and as such, U.S. persons are generally prohibited from dealing with them.
      # If a user receives a "blocking" screening status, they will be transitioned to this state.
      # A sponsorable in this state will not be able to be sponsored and will not appear as sponsorable.
      state :sdn_disabled, 13 do
        event :sdn_enable, transitions_to: :approved
      end

      state :spammy, 14 do
        event :mark_not_spammy, transitions_to: :approved
        event :ban, transitions_to: :banned
      end

      state :queued_for_auto_approval, 9 do
        event :approve, transitions_to: :approved
        event :cancel_approval_request, transitions_to: :draft
        event :auto_approval_failed, transitions_to: :pending_approval
        event :ban, transitions_to: :banned
      end

      on_transition do |from, to, _event, *_args, **_kwargs|
        T.bind(self, SponsorsListing)

        if to == :pending_approval
          stafftools_metadata&.touch(:reviewed_at, :approval_requested_at)
        else
          stafftools_metadata&.touch(:reviewed_at)
        end
        SponsorsListingZuoraSyncJob.perform_later(self) if to == :approved

        if to == :approved || from == :approved
          UpdateOwnerRepositorySponsorablesJob.perform_later(sponsorable_id: sponsorable_id)
        end

        became_accepted = ACCEPTED_INTO_SPONSORS_STATES.include?(to) && !ACCEPTED_INTO_SPONSORS_STATES.include?(from)
        stopped_being_accepted = !ACCEPTED_INTO_SPONSORS_STATES.include?(to) &&
          ACCEPTED_INTO_SPONSORS_STATES.include?(from)
        sync_sponsors_patreon_user if became_accepted || stopped_being_accepted
      end
    end

    scope :with_states, ->(*states) do
      if states.compact.present?
        state_values = states.map { |state| state_value(state) }
        where(state: state_values)
      end
    end

    scope :without_states, ->(*states) do
      if states.compact.present?
        state_values = states.map { |state| state_value(state) }
        where.not(state: state_values)
      end
    end

    # Public: Get Sponsors listings that are in or are not in the specified state, based on whether the "not_" prefix is
    # present.
    #
    # state - a String or nil; valid values include "approved", "banned", "draft", "sdn_disabled", "spammy",
    #         "pending_approval", "requires_additional_review", "queued_for_auto_approval", waitlisted", "disabled",
    #         "not_approved", "not_banned", "not_draft", "not_sdn_disabled", "not_spammy", "not_pending_approval",
    #         "not_requires_additional_review", "not_queued_for_auto_approval", "not_waitlisted", "not_disabled", "all"
    #
    # Returns an ActiveRecord::Relation of SponsorsListing.
    scope :filter_by_state, ->(state) do
      if state.present?
        normalized_state_maybe_with_prefix = state.downcase
        prefix = "not_"
        if normalized_state_maybe_with_prefix.start_with?(prefix)
          normalized_state = normalized_state_maybe_with_prefix.split(prefix).last
          without_states(normalized_state)
        elsif state != "all"
          with_states(normalized_state_maybe_with_prefix)
        end
      end
    end

    scope :ordered_by_state, -> do
      approved = state_value(:approved)
      pending_states = [
        state_value(:draft),
        state_value(:pending_approval),
        state_value(:requires_additional_review),
        state_value(:queued_for_auto_approval)
      ].map(&:to_s).join(", ")
      disabled = state_value(:disabled)

      sql = <<~SQL
        CASE WHEN sponsors_listings.state = #{approved} THEN 0
        WHEN sponsors_listings.state IN (#{pending_states}) THEN 1
        WHEN sponsors_listings.state = #{disabled} THEN 3
        ELSE 2 END
      SQL
      order(Arel.sql(sql))
    end
  end

  class_methods do
    extend T::Sig

    # Public: Get the Integer value matching a certain state.
    sig { params(name: T.any(String, Symbol)).returns(T.nilable(Integer)) }
    def state_value(name)
      SponsorsListing.workflow_spec.states[name.to_sym]&.value
    end
  end

  # Public: Is the maintainer waiting to be reviewed by GitHub?
  sig { returns T::Boolean }
  def waiting_to_be_reviewed?
    pending_approval? || requires_additional_review? || waitlisted? || queued_for_auto_approval?
  end

  ACCEPTED_INTO_SPONSORS_STATES = [:draft, :pending_approval, :requires_additional_review, :queued_for_auto_approval,
    :approved, :disabled,
    # Spammy and SDN disabled listings are only able to get to those states once they've been approved,
    # so they must have been accepted into the program:
    :spammy, :sdn_disabled].freeze

  # Public: Has the maintainer been accepted into the Sponsors program, even if they don't
  # have a publicly visible Sponsors profile yet? That is, have they been moved off the waitlist and haven't been
  # explicitly rejected from the program.
  sig { returns T::Boolean }
  def accepted_into_sponsors?
    ACCEPTED_INTO_SPONSORS_STATES.include?(current_state_name)
  end

  SIGNUP_IN_PROGRESS_STATES = [:draft, :pending_approval].freeze

  # Public: Has this maintainer begun the signup process but not completed it yet?
  sig { returns T::Boolean }
  def signup_in_progress?
    SIGNUP_IN_PROGRESS_STATES.include?(current_state_name)
  end

  # Public: Returns a symbol representing the current state of this listing.
  sig { returns Symbol }
  def current_state_name
    current_state.name
  end

  # Public: The datetime when Sponsors listings entered its current state or got ignored, if known.
  sig { returns T.nilable(T.any(DateTime, ActiveSupport::TimeWithZone)) }
  def in_current_state_since
    most_recent_state_change = if approved?
      published_at
    elsif draft?
      accepted_at
    elsif waitlisted?
      joined_at
    else
      stafftools_metadata&.in_current_state_since(current_state_name)
    end
    [most_recent_state_change, stafftools_metadata&.ignored_at].compact.max
  end

  private

  # Private: Called when calling `mark_spammy!` for state transition.
  sig { void }
  def mark_spammy
    disable_payouts_for_active_stripe_connect_account(reason: "Spammy maintainer")
  end

  # Private: Called when calling `mark_not_spammy!` for state transition.
  sig { void }
  def mark_not_spammy
    enable_payouts_for_active_stripe_connect_account
  end

  # Private: Called when calling `request_approval!` for state transition.
  sig { params(_prior_state: T.nilable(Workflow::State), _triggering_event: T.nilable(Symbol)).void }
  def request_approval(_prior_state = nil, _triggering_event = nil)
    unless eligible_for_sponsors?
      BanSponsorsListingJob.perform_later(
        sponsors_listing: T.bind(self, SponsorsListing),
        actor: User.staff_user,
        ban_reason: SponsorsListing.auto_ban_reason,
        automated: true,
      )
      halt SponsorsListing.auto_ban_halt_message
    end
  end

  # Private: Called when calling `ban!` for state transition.
  sig { params(banned_reason: String, automated: T::Boolean).void }
  def ban(banned_reason:, automated: false)
    disable_payouts_for_active_stripe_connect_account(reason: banned_reason)

    SponsorsListingNoLongerSponsorableJob.perform_later(
      sponsors_listing: T.bind(self, SponsorsListing),
      actor: actor,
      reason: :BANNED_LISTING,
    )

    stafftools_metadata&.update_columns(
      banned_by_id: actor&.id,
      banned_at: Time.current,
      banned_reason: banned_reason,
    )

    actor_hash = if actor&.site_admin?
      GitHub.guarded_audit_log_staff_actor_entry(actor)
    elsif actor
      { actor: actor }
    else
      {}
    end

    instrument :create, actor_hash.merge(
      banned_reason: banned_reason,
      prefix: :sponsors_memberships_ban
    )

    # Hydro
    GlobalInstrumenter.instrument("sponsors.listing_state_change",
      user: sponsorable,
      action: :BANNED,
      listing: self,
      listing_stafftools_metadata: self.stafftools_metadata,
      automated: automated
    )

    nil
  end

  # Private: Called when calling "un_ban!" for state transition.
  sig { void }
  def un_ban
    success = T.let(true, T::Boolean)

    SponsorsListing.transaction do
      if stafftools_metadata
        success = T.must(stafftools_metadata).update(banned_by: nil, banned_at: nil, banned_reason: nil)
      end
      raise ActiveRecord::Rollback unless success
    end

    unless success
      all_errors = T.must(stafftools_metadata).errors.full_messages
      return halt "Unable to unban Sponsors listing: #{all_errors.to_sentence}"
    end

    actor_hash = if actor&.site_admin?
      GitHub.guarded_audit_log_staff_actor_entry(actor)
    elsif actor
      { actor: actor }
    else
      {}
    end

    instrument :destroy, actor_hash.merge(prefix: :sponsors_memberships_ban)

    nil
  end

  # Private: Called when calling `accept!` for state transition.
  sig { params(automated: T::Boolean, send_acceptance_email: T::Boolean).void }
  def accept(automated: false, send_acceptance_email: true)
    if sponsorable_has_any_trade_restrictions?
      return halt "Trade-restricted users are not eligible for GitHub Sponsors"
    end

    unless eligible_for_sponsors?
      BanSponsorsListingJob.perform_later(
        sponsors_listing: T.bind(self, SponsorsListing),
        actor: User.staff_user,
        ban_reason: SponsorsListing.auto_ban_reason,
        automated: true,
      )
      return halt SponsorsListing.auto_ban_halt_message
    end

    instrument_acceptance(automated: automated)
    touch(:accepted_at)
    if send_acceptance_email
      SponsorsPrimerMailer.waitlist_acceptance(sponsorable: sponsorable).deliver_later
    end

    nil
  end

  # Private: Called when calling `disable!` for state transition.
  sig { void }
  def disable
    SponsorsListingNoLongerSponsorableJob.perform_later(
      sponsors_listing: T.bind(self, SponsorsListing),
      actor: actor,
      reason: :DISABLED_LISTING,
    )

    # Audit log
    instrument(:sponsored_developer_disable, prefix: :sponsors, actor: actor)

    # Hydro
    GlobalInstrumenter.instrument("sponsors.listing_state_change",
      user: sponsorable,
      action: :DISABLED,
    )
  end

  # Private: Called when calling `unpublish!` for state transition.
  sig { void }
  def unpublish
    SponsorsListingNoLongerSponsorableJob.perform_later(
      sponsors_listing: T.bind(self, SponsorsListing),
      actor: actor,
      reason: :UNPUBLISHED_LISTING,
    )
  end

  # Private: Called when calling `redraft!` for state transition.
  sig { void }
  def redraft
    # Audit log
    instrument(:sponsored_developer_redraft, prefix: :sponsors)

    SyncSponsorsSearchIndicesJob.perform_later(sponsorable: sponsorable)

    # Hydro
    GlobalInstrumenter.instrument("sponsors.listing_state_change", {
      user: sponsorable,
      action: :REDRAFTED,
    })
  end

  # Private: Called when calling `cancel_approval_request!` for state transition.
  sig { void }
  def cancel_approval_request
    # Audit log
    instrument(:sponsored_developer_redraft,
      redrafted_because: "approval request canceled",
      prefix: :sponsors
    )

    # Hydro
    GlobalInstrumenter.instrument("sponsors.listing_state_change", {
      user: sponsorable,
      action: :REDRAFTED,
    })
  end

  # Private: Called after a listing is transitioned to `pending_approval`.
  sig { params(_prior_state: T.nilable(Workflow::State), _triggering_event: T.nilable(Symbol), kwargs: T.untyped).void }
  def on_pending_approval_entry(_prior_state = nil, _triggering_event = nil, **kwargs)
    sponsorable&.perform_live_sdn_screening

    SponsorsPrimerMailer.approval_request_submitted(
      sponsorable: sponsorable,
    ).deliver_later

    # Audit log
    instrument(:sponsored_developer_request_approval, prefix: :sponsors)

    # Hydro
    GlobalInstrumenter.instrument("sponsors.listing_state_change", {
      user: sponsorable,
      action: :REQUESTED_APPROVAL,
    })

    enqueue_for_auto_approval! if auto_approvable?
  end

  # Private: Called when calling `enqueue_for_auto_approval!` for state transition.
  sig { void }
  def enqueue_for_auto_approval
    wait_time = AUTO_APPROVE_WAIT_TIME_RANGE_IN_HOURS.to_a.sample
    AutoApproveSponsorsListingJob.set(wait: wait_time.hours).perform_later(self)

    # Audit log
    instrument(:sponsored_developer_queued_for_auto_approval, actor: User.staff_user, prefix: :sponsors)

    # Hydro
    GlobalInstrumenter.instrument("sponsors.listing_state_change",
      action: "QUEUED_FOR_AUTO_APPROVAL",
      user: sponsorable
    )
  end

  # Private: Called when calling `auto_approval_failed!` for state transition.
  sig { void }
  def auto_approval_failed
    instrument_auto_approval(success: false)
  end

  # Private: Called when calling `approve!` for state transition.
  sig { params(automated: T::Boolean).void }
  def approve(automated: false)
    instrument_approval(automated: automated)
  end

  # Private: Called when calling `publish!` for state transition.
  sig { params(automated: T::Boolean).void }
  def publish(automated: false)
    instrument_approval(automated: automated)
  end

  # Private: Called after state transitions to approved
  sig { params(previous_state: Workflow::State, _triggering_event: Symbol, automated: T::Boolean).void }
  def on_approved_entry(previous_state, _triggering_event, automated: false)
    update_attribute(:published_at, Time.zone.now)
    this_sponsorable = T.must_because(sponsorable) { "listing must have a sponsorable to be approved" }
    SponsorsPrimerMailer.listing_approved(sponsorable: this_sponsorable).deliver_later

    if this_sponsorable.actively_sponsoring?
      CreateMatchDisabledSponsorsActivityJob.perform_later(listing: self)
    end

    if previous_state == :sdn_disabled
      GitHub.dogstats.increment("sponsors_listing.sdn_enable", tags: ["status:#{sponsorable_trade_screening_status}"])
    end

    SyncSponsorsSearchIndicesJob.perform_later(sponsorable: sponsorable)
  end

  # Private: Called after state transitions to sdn_disabled
  sig { params(_previous_state: Workflow::State, _triggering_event: Symbol, kwargs: T.untyped).void }
  def on_sdn_disabled_entry(_previous_state, _triggering_event, **kwargs)
    GitHub.dogstats.increment("sponsors_listing.sdn_disable", tags: ["status:#{sponsorable_trade_screening_status}"])
  end

  # Private: Called when calling `sdn_disable!` for state transition.
  sig { void }
  def sdn_disable
    disable_payouts_for_active_stripe_connect_account(reason: SDN_DISABLE_REASON)
  end

  # Private: Called when calling `sdn_enable!` for state transition.
  sig { void }
  def sdn_enable
    enable_payouts_for_active_stripe_connect_account
  end
end
