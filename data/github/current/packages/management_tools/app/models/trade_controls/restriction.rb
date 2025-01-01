# typed: strict
# frozen_string_literal: true

module TradeControls
  class Restriction < ApplicationRecord::Collab
    include Workflow
    include Instrumentation::Model

    class FailedTransitionError < StandardError; end

    BATCH_SIZE = T.let(1000.freeze, Integer)
    self.inheritance_column = nil
    belongs_to :user

    # order here matters since this is used by enforcement_reason
    VALID_ENFORCEMENT_REASONS = T.let([
      :manual,
      :ip,
      :email,
      :organization_admin,
      :organization_billing_manager,
      :website_url,
    ].freeze, T::Array[Symbol])

    enum :enforcement_reason, VALID_ENFORCEMENT_REASONS

    enum :type, {
      unrestricted: "unrestricted",
      full: "full", # Financial Restriction + Full Feature Restriction => For paying orgs
      # Free orgs
      tier_0: "tier_0", # Financial Restriction, no free feature restrictions
      tier_1: "tier_1" # Financial Restriction, FPR restricted
    }

    validates_presence_of :user, :type
    validates_uniqueness_of :user_id
    validates_inclusion_of :type, in: types.keys
    validates_exclusion_of :type, in: %w[tier_0 tier_1], unless: -> {
      T.bind(self, Restriction)
      T.must(user).organization?
    }

    after_commit :instrument_country_code_update, on: [:create, :update], if: :saved_change_to_trade_restricted_country_code?

    scope :any_restricted_ids, ->(ids) { where(user_id: ids).where.not(type: "unrestricted").find_each(batch_size: BATCH_SIZE) }
    scope :full_restricted_ids, ->(ids) { where(user_id: ids, type: "full").find_each(batch_size: BATCH_SIZE) }

    sig { returns(T::Boolean) }
    def tcr_has_organization?
      T.must(user).organization?
    end

    workflow(:type) do
      state :unrestricted do
        event :enforce, transitions_to: :full
        event :tier_0_enforce, transitions_to: :tier_0, if: :tcr_has_organization?
        event :tier_1_enforce, transitions_to: :tier_1, if: :tcr_has_organization?
      end

      state :full do
        event :override, transitions_to: :unrestricted
      end

      state :tier_0 do
        event :override, transitions_to: :unrestricted
        event :tier_1_upgrade, transitions_to: :tier_1
        event :enforce, transitions_to: :full
      end

      state :tier_1 do
        event :override, transitions_to: :unrestricted
        event :tier_0_downgrade, transitions_to: :tier_0
        event :enforce, transitions_to: :full
      end

      after_transition do |from, to, event, compliance:, skip_enforcement_email: false|
        T.bind(self, Restriction)
        sdn_suspend_if_applicable(restriction_type: to, compliance: compliance)
        instrument_transition_event(from: from, to: to, event: event, compliance: compliance, skip_enforcement_email: skip_enforcement_email)
      end
    end

    sig { returns(T::Boolean) }
    def any?
      !unrestricted?
    end

    sig { returns(T::Boolean) }
    def tiered_restriction?
      tier_0? || tier_1?
    end

    sig { returns(T::Array[[Symbol, Symbol]]) }
    def valid_events_with_subsequent_state
      current_state.events.map do |_, (event)|
        [event.transitions_to, event.name] if event.condition_applicable?(self)
      end.compact
    end

    sig { params(restriction_type: T.any(Symbol, String)).returns(T.nilable(Symbol)) }
    def restriction_event(restriction_type)
      current_state.events.keys.delete(restriction_type.to_sym)
    end

    sig { returns(T::Boolean) }
    def has_override_within_last_6_months?
      return false if last_override_date.nil?

      last_override_date > 6.months.ago
    end

    sig { returns(T::Boolean) }
    def restricted_on_creation?
      return true if restricted_on_creation

      T.must(user).created_at.to_date == self.created_at.to_date
    end

    sig { returns(T::Boolean) }
    def has_insufficient_account_age?
      T.must(user).created_at.to_date >= 30.days.ago.to_date
    end

    sig { returns(T::Boolean) }
    def can_override_automatically?
      return false if restricted_on_creation?
      return false if has_insufficient_account_age?
      return false if has_override_within_last_6_months?

      enforcement_reason == "ip"
    end

    private

    sig { void }
    def instrument_country_code_update
      tags = [
        "country_code_was:#{trade_restricted_country_code_previously_was}",
        "country_code_is:#{trade_restricted_country_code}"
      ]
      GitHub.dogstats.increment(
        "trade_controls_restriction.country_code.update",
        tags: tags,
      )
    end

    sig { params(restriction_type: Symbol, compliance: TradeControls::Compliance).void }
    def sdn_suspend_if_applicable(restriction_type:, compliance:)
      return unless restriction_type == :full || restriction_type == :tier_1
      return unless compliance.sdn_suspend?
      return if T.must(user).sdn_suspended?

      T.must(user).sdn_suspend(staff_user: User.staff_user, reason: "Actor is from sanctioned country #{self.trade_restricted_country_code}")
    end

    # We deviate from workflow-orchestrator's behavior here. Instead of
    # persisting the state via update_column, we save the new state and
    # run validations by using update. We do this because it's possible
    # that several events have been queued for the same user, and we
    # need validations to run to prevent duplicate records for one user.
    # see note at: https://github.com/lorefnon/workflow-orchestrator/tree/4a96f194faebb01498f7d2827b4bb1fde5f9c239#transition-event-handler
    sig {  params(new_value: T.any(String, Symbol)).returns(T::Boolean) }
    def persist_workflow_state(new_value)
      self.type = new_value
      unless save
        raise FailedTransitionError.new("Failed to transition from #{self.type_was} to #{new_value}")
      end

      true
    end

    sig { params(compliance: Compliance).void }
    def set_enforcement_metadata(compliance:)
      payload = compliance.to_hydro
      reason = if payload[:reason].present? && VALID_ENFORCEMENT_REASONS.include?(payload[:reason])
        payload[:reason].to_s
      else
        "manual"
      end

      restricted_on_creation = ["user.signup", "organization.create"].include?(compliance.event_source)
      update_hash = {
        metadata: nil,
        enforcement_reason: reason,
        last_enforcement_date: Time.now.utc,
        restricted_on_creation: restricted_on_creation
      }

      populate_ofac_flagged_country(compliance, update_hash)
      assign_attributes(update_hash)
    end

    sig { params(compliance: Compliance).void }
    def set_override_metadata(compliance:)
      payload = compliance.to_hydro
      metadata_reason = { reason: payload[:reason] } if compliance.is_a?(ManualCompliance) && payload[:reason].present?
      update_hash = {
        metadata: metadata_reason,
        last_override_date: Time.now.utc,
        enforcement_reason: nil,
        trade_restricted_country_code: nil
      }

      assign_attributes(update_hash)
    end

    # Private: Populates the update_hash with country/region information for a restriction when we are able to infer the country/region
    # from the violation data.
    #
    # If both country code and region name is available we use both. Otherwise we use which one is available.
    sig { params(compliance: Compliance, update_hash: T::Hash[T.any(String, Symbol), T.untyped]).void }
    def populate_ofac_flagged_country(compliance, update_hash = {})
      hydro_hash = compliance.to_hydro
      country_name = hydro_hash[:country]
      region_name = hydro_hash[:region]

      country = TradeControls::Country.from_braintree(Braintree::Address::CountryNames.find { |c| c[0] == country_name })
      country_code = country.alpha3.presence || country.alpha2
      region_code = Countries.ukraine_region_name(region_name) if region_name.present?
      update_value = [country_code, region_code].compact_blank.join(" -- ")
      update_hash[:trade_restricted_country_code] = update_value if update_value.present?
    end

    sig { params(from: Symbol, to: Symbol, event: Symbol, compliance: Compliance::ComplianceType, skip_enforcement_email: T::Boolean).void }
    def instrument_transition_event(from:, to:, event:, compliance:, skip_enforcement_email: false)
      instrument(event, {
        compliance: compliance,
        skip_enforcement_email: skip_enforcement_email,
        restriction_type: to,
        restriction_type_was: from,
        restricted_country: trade_restricted_country_code
      })

      hydro_extras = {
        restricted_on_creation: self.restricted_on_creation,
        last_override_date: self.last_override_date,
        last_enforcement_date: self.last_enforcement_date,
      }

      if event == :override
        T.must(user).instrument_trade_controls_override(compliance: compliance, **hydro_extras)
      else
        T.must(user).instrument_trade_controls_enforcement(compliance: compliance, **hydro_extras)
      end
    end

    concerning :Enforce do

      protected

      # Private: but marked protected to be invoked by workflow gem
      #
      # Enforce the limited access afforded to restricted users.
      sig { params(compliance: Compliance, skip_enforcement_email: T::Boolean).void }
      def enforce(compliance:, skip_enforcement_email: false)
        suspend_subscription
        destroy_migrations
        unpublish_private_pages
        schedule_downgrade

        # we only want to send enforcement emails the first time and not when moving
        # between restriction states
        if self.unrestricted? && !skip_enforcement_email
          send_enforcement_email
        end

        set_ofac_flagged_notice
        set_enforcement_metadata(compliance:)
      end

      # Private: but marked protected to be invoked by workflow gem
      #
      # Enforce the less-limited access afforded to restricted orgs.
      sig { params(compliance: Compliance).void }
      def partially_enforce(compliance:)
        enforce(compliance:, skip_enforcement_email: true)
      end

      private

      sig { void }
      def suspend_subscription
        T.must(user).suspend_billing
      end

      sig { params(compliance: Compliance).void }
      def tier_0_enforce(compliance:)
        partially_enforce(compliance: compliance)
      end

      sig { params(compliance: Compliance).void }
      def tier_1_enforce(compliance:)
        partially_enforce(compliance: compliance)
      end

      sig { void }
      def destroy_migrations
        Migration.where(owner: user).find_each do |m|
          MigrationDestroyFileJob.enqueue(m)
        end
      end

      sig { void }
      def unpublish_private_pages
        T.must(user).unpublish_private_pages
      end

      sig { void }
      def schedule_downgrade
        OFACDowngrade.schedule_for(user)
      end

      sig { void }
      def send_enforcement_email
        T.must(user).send_trade_controls_enforcement_email
      end

      sig { void }
      def set_ofac_flagged_notice
        GlobalNoticeNext.new(viewer: user).set_notice(:ofac_flagged)
      end
    end

    concerning :Override do

      protected

      # Private: but marked protected to be invoked by workflow gem
      #
      # Undoes the effects of a user being restricted.
      # This does not prevent re-flagging in the future.
      sig { params(compliance: ManualCompliance).void }
      def override(compliance:)
        resume_subscription
        cancel_scheduled_downgrade
        send_reactivation_email
        unban_sponsors_listing(actor: compliance.actor)
        set_override_metadata(compliance:)
      end

      private

      sig { void }
      def resume_subscription
        T.must(user).resume_billing
      end

      sig { void }
      def cancel_scheduled_downgrade
        user_spammy_restricted = T.must(user).user? && T.must(user).spammy?
        T.must(user).scheduled_ofac_downgrade&.destroy unless user_spammy_restricted
      end

      sig { void }
      def send_reactivation_email
        T.must(user).send_trade_controls_override_email
      end

      sig { params(actor: User).void }
      def unban_sponsors_listing(actor:)
        if (listing = T.must(user).sponsors_listing)&.banned?
          listing.actor = actor
          listing.un_ban!
        end
      end
    end

    concerning :Upgrade do

      protected

      sig { params(compliance: Compliance).void }
      def tier_1_upgrade(compliance:)
        # we don't do anything yet
      end
    end

    concerning :Downgrade do

      protected

      sig { params(compliance: Compliance).void }
      def tier_0_downgrade(compliance:)
        # we don't do anything yet
      end
    end

    concerning :Instrumentation do
      include Instrumentation::Model

      private

      # Default event_prefix is trade_controls/restriction
      # but the audit-log UI in stafftools doesn't handle slashes well
      sig { returns(Symbol) }
      def event_prefix
        :trade_controls_restriction
      end

      # Include user in payload by default, keyed appropriately as :user or :org
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def event_payload
        sym = T.must(user).organization? ? :org : :user
        { sym => T.must(user) }
      end
    end
  end
end
