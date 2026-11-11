# typed: strict
# frozen_string_literal: true

module Billing::Abuse::Copilot
  module AuthAndCapture
    extend T::Helpers
    include GitHub::Memoizer

    COPILOT_INDIVIDUAL_MONTHLY_RATE_IN_CENTS = T.let(10 * 100, Integer)
    COPILOT_BUSINESS_MONTHLY_PER_SEAT_RATE_IN_CENTS = T.let(19 * 100, Integer)

    # This will create a db record that the Abuse::Copilot::RunRequiredAuthorizationsJob will pick up, causing it to try and
    # authorize the organization. If the organization cannot be authorized, the job will keep trying on each run until
    # the auth check can be run, at which point the next job run will delete the db record.
    # If `pending_token` is set, the required auth record will be skipped until the organization generates their first token
    sig { params(reason: T.nilable(String), pending_token: T::Boolean).void }
    def schedule_auth_and_capture!(reason: "unknown", pending_token: false)
      return unless configurable_object.organization?
      state = pending_token ? :pending_token : :active
      return if ::Abuse::Copilot::RequiredAuthorization.for_organizations(configurable_object.id).where(state: state).exists?

      ::Abuse::Copilot::RequiredAuthorization.for_organizations(configurable_object.id).create!(state: state, reason: reason)
    end

    # If the user's organizations have any auth checks in the `pending_token` state, flip them to active so they get run during
    # the next Abuse::Copilot::RunRequiredAuthorizationsJob
    sig { void }
    def activate_pending_auth_checks!
      return unless configurable_object.user? && T.unsafe(self).respond_to?(:send_abuse_notification)
      organizations = T.unsafe(self).copilot_organizations.map(&:organization_object)
      required_auths = ::Abuse::Copilot::RequiredAuthorization.pending_token.for_organizations(organizations.map(&:id))

      required_auths.each do |auth|
        auth.update!(state: :active)
      end
    end

    sig { returns(T::Boolean) }
    def has_pending_auth_checks?
      return false unless configurable_object.user? && T.unsafe(self).respond_to?(:send_abuse_notification)
      organizations = T.unsafe(self).copilot_organizations.map(&:organization_object)
      ::Abuse::Copilot::RequiredAuthorization.pending_token.for_organizations(organizations.map(&:id)).exists?
    end

    sig { params(skip_previous_authorizations_check: T::Boolean, audit_log_reason: T.nilable(String), delay: Integer).void }
    def perform_auth_and_capture!(skip_previous_authorizations_check: false, audit_log_reason: "unknown", delay: 0)
      audit_log_payload = T.let({ reason: audit_log_reason }, T::Hash[Symbol, T.untyped])

      GitHub.logger.with_named_tags(
        "gh.copilot.configurable_object.type" => configurable_object.class.to_s,
        "gh.copilot.configurable_object.id" => configurable_object.id,
      ) do
        unless customer = configurable_object.customer
          GitHub.dogstats.increment("copilot.auth_and_capture.skipped", tags: ["reason:customer_not_found"] + dogstats_tags)
          GitHub.logger.info("Skipping auth and capture, not eligible", "gh.copilot.auth_and_capture.skip_reason": "customer_not_found")
          return
        end

        last_authorization_time_frame = unless skip_previous_authorizations_check
          1.month.ago
        end

        result = Billing.domain.payment_authorizations.create(
          customer_id: customer.id,
          origin: "Copilot::AuthAndCapture",
          amount_in_cents: auth_and_capture_amount_in_cents,
          check_overage: false,
          cancel_free_trials_on_failure: true,
          skip_if_last_successful_authorization_at: last_authorization_time_frame,
          delay: delay,
        )
        case result
        when GH::Result::Error
          GitHub.dogstats.increment("copilot.auth_and_capture.error", tags: dogstats_tags)
          GitHub.logger.info("Error during auth and capture", "gh.copilot.auth_and_capture.error": result.message)
        when GH::Result::Ok
          auth_result = result.value
          if auth_result.skipped?
            GitHub.dogstats.increment("copilot.auth_and_capture.skipped", tags: ["reason:#{auth_result.reason}"] + dogstats_tags)
            GitHub.logger.info("Skipping auth and capture, skipped by domain logic", "gh.copilot.auth_and_capture.skip_reason": auth_result.reason)
            return
          end

          audit_log_payload[:amount_in_cents] = auth_result.amount_authorized_in_cents
          audit_log_payload[configurable_object.event_prefix] = configurable_object
          GitHub.instrument("copilot.billing_authorization_performed", audit_log_payload)
          GitHub.dogstats.increment("copilot.auth_and_capture.performed", tags: dogstats_tags)
        end
      end
    end

    # This is called by an event listener in copilot_for_business_watched_events.rb. Eventually we may use this to trigger
    # a new auth and capture check for the organization, but for now we're just logging the event.
    # Remember that this is called for _all_ users who get billing unlocked, so it's critical that we check for previous
    # Copilot activity before we do anything.
    sig { void }
    def handle_billing_unlock!
      return unless configurable_object.feature_flag_enabled?(:copilot_auth_on_billing_unlock, default: true)
      return unless configurable_object.organization?

      # Skip unless this organization has had Copilot seats in the past
      return unless ::Copilot::SeatHistory.for_organization(configurable_object).exists?

      last_authorization = ::Billing::BillingTransaction
              .current_authorizations_for_customer(T.must(configurable_object.customer).id)
              .last

      # We only care about organizations that have a recent failed auth and no successful auths since then
      return unless last_authorization&.last_status == "processor_declined"

      # For safety, exclude the trusted tier of organizations
      is_untrusted = ::TrustTiers::Tier.for_billable_owner(configurable_object).tier >= TrustTiers::Tier::NEUTRAL
      return unless is_untrusted

      GitHub.logger.info(
        "Organization with Copilot history unlocked with a failing authorization",
        "gh.org.id": configurable_object.id,
        "gh.org.login": configurable_object.display_login,
        "gh.copilot.authorization_id": last_authorization&.id,
      )

      if T.unsafe(self).respond_to?(:send_abuse_notification)
        details = "Organization #{configurable_object.display_login} with a previous failing authorization just unlocked their billing"
        T.unsafe(self).send_abuse_notification(details: details)
      end
    end

    sig { returns(Integer) }
    def auth_and_capture_amount_in_cents
      if configurable_object.user?
        COPILOT_INDIVIDUAL_MONTHLY_RATE_IN_CENTS
      elsif configurable_object.organization? && configurable_object.feature_flag_enabled?(:copilot_org_auth_dynamic_amount, default: true)
        # We only auth organizations that have never paid for Copilot before, so it's OK to auth for a slightly larger
        # amount here to catch orgs that are sneaking under the radar. Still, let's make sure there's an upper bound
        # of 10 seats so we don't auth a very large legitimate org for a very large amount.
        COPILOT_BUSINESS_MONTHLY_PER_SEAT_RATE_IN_CENTS * [10, seats_to_auth_count].min
      else
        COPILOT_BUSINESS_MONTHLY_PER_SEAT_RATE_IN_CENTS
      end
    end

    sig { returns(T::Array[String]) }
    def dogstats_tags
      ["type:#{configurable_object.class}"]
    end

    # We might run this before the seat assignments have been converted to seats, so let's make sure we're at least
    # authing for something if that's the case
    sig { returns(Integer) }
    def seats_to_auth_count
      seat_count = ::Copilot::Seat.for_organization(configurable_object).count

      if seat_count == 0
        ::Copilot::SeatAssignment.for_organization(configurable_object).count
      else
        seat_count
      end
    end

    abstract!

    sig { abstract.returns(T.any(::User, ::Organization, ::Business)) }
    def configurable_object; end
  end
end
