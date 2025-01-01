# typed: strict
# frozen_string_literal: true

module Copilot
  # This is a wrapper around the ::Organization class.
  # It adds in methods related to Copilot.
  class Organization < SimpleDelegator
    include GitHub::Memoizer

    include Copilot::Abuse
    include ::Billing::Abuse::Copilot::AuthAndCapture
    include Copilot::Billable
    include Copilot::Helpers
    include Copilot::Metrics
    include Copilot::Signup
    include Copilot::Organizations::ActivityExport
    include Copilot::Organizations::Business
    include Copilot::Organizations::CsvExport
    include Copilot::Organizations::InstrumentationDetails
    include Copilot::Organizations::SeatManagement
    include Copilot::Organizations::Settings
    include Copilot::Organizations::State
    include Copilot::Organizations::FeatureAuthorization
    include Copilot::Organizations::Mailable
    include Copilot::Organizations::FeatureEnabled
    include Copilot::Organizations::Usage

    include ::Growth::CopilotOrganization

    include Vexi::Actor

    delegate :analytics_tracking_id,
             :display_login,
             :profile_name,
             :spammy?,
             :suspended?,
             to: :organization_object

    sig { params(organization: ::Organization).void.checked(:always).on_failure(:raise) }
    def initialize(organization)
      super
    end

    sig { returns(T::Class[T.anything]) }
    def sorbet_class
      ::Organization
    end

    sig { returns(Integer) }
    def id
      organization_object.id
    end

    sig { override.returns(::Organization) }
    def configurable_object
      organization_object
    end

    sig { override.returns(::Organization) }
    def organization_object
      T.cast(__getobj__, ::Organization)
    end

    sig { override.returns(T.nilable(Copilot::BusinessTrial)) }
    memoize def business_trial
      Copilot::BusinessTrial.for_organization(organization_object)
    end

    sig { override.returns(T::Boolean) }
    memoize def on_free_trial?
      return false unless business_trial.present?

      T.must(business_trial).active?
    end

    sig { returns(T::Boolean) }
    def on_free_copilot_enterprise_trial?
      on_free_trial? && T.must(business_trial).copilot_plan_enterprise?
    end

    sig { returns(T::Boolean) }
    def on_free_copilot_business_trial?
      on_free_trial? && T.must(business_trial).copilot_plan_business?
    end

    sig { returns(T::Boolean) }
    def has_trial?
      return false unless trial = business_trial

      trial.has_trial?
    end

    sig { override.returns(T::Boolean) }
    def pending_free_trial?
      return false unless business_trial.present?
      T.must(business_trial).pending?
    end

    sig { override.returns(T::Boolean) }
    def has_assigned_seats?
      Copilot::Seat.for_organization(organization_object).any?
    end

    sig { params(user: ::User).returns(T::Boolean) }
    def has_seat_for?(user)
      Copilot::Seat.where(organization: organization_object, assigned_user: user).exists?
    end

    sig { returns({ seats: Integer, seats_added: Integer, seats_to_be_removed: Integer }) }
    def billing_summary
      org = organization_object

      {
        seats: Copilot::Seat.for_organization(org).count,
        seats_added: Copilot::Seat.where(
          seat_assignment: Copilot::SeatAssignment.for_organization(org).where(
            "created_at > ? AND created_at < ?",
            organization_object.current_metered_billing_cycle_starts_at,
            organization_object.next_metered_billing_cycle_starts_at
          )
        ).count,
        seats_to_be_removed: Copilot::Seat.where(
          seat_assignment: Copilot::SeatAssignment.for_organization(org).where("pending_cancellation_date IS NOT NULL")
        ).count,
      }
    end

    # Disables the Copilot flag on the organization,
    # sets seat management to disabled, and instruments
    # an audit log event describing the changes.
    sig { params(actor: T.nilable(::User)).void }
    def revoke_copilot_for_org!(actor = nil)
      disable_copilot!(actor)

      old_seat_management_setting = self.seat_management_setting

      unless old_seat_management_setting == "disabled"
        Copilot::Instrumenter.instrument_copilot_for_business_seat_management_changed(
          actor,
          organization_object,
          old_seat_management_setting,
          "disabled"
        )
      end

      seat_management_disable!
    end

    sig { returns(T::Boolean) }
    def copilot_standalone?
      false
    end

    sig { returns(T.nilable(::Business)) }
    memoize def business
      organization_object.business
    end

    # This method determines if a Copilot plan is being formalized as the value of the existing Copilot plan applied to the organization,
    # from a parent business.
    # This can be necessary because an organization can have Copilot enabled, but not have a plan explicitly set.
    # Knowing that a plan is merely being formalized allows us to avoid e.g. sending plan change emails.
    #
    # For example, consider the following situation
    #   * The enterprise has a copilot plan of "enterprise"
    #   * The enterprise has copilot enabled for all orgs
    #   * The organization has never had a configured plan; implicitly they have a plan of "enterprise"
    #   * From the organization plan enablement UI, the enterprise admin selects "enterprise" for the org from the list of plans
    #   * This method runs and sees that the selected plan is making the implicit explicit and returns true
    sig { params(plan: String).returns(T::Boolean) }
    def is_explicit_plan_confirmation?(plan)
      is_copilot_plan_misconfigured? && new_plan_matches_business_plan?(plan)
    end

    sig { returns(T::Boolean) }
    memoize def is_copilot_plan_misconfigured?
      return false if business.nil?
      !!(copilot_org.copilot_plan_unconfigured? && copilot_org.copilot_enabled?)
    end

    sig { params(plan: String).returns(T::Boolean) }
    def new_plan_matches_business_plan?(plan)
      return false if business.nil?

      # We have already established there is a business, so we can safely cast here.
      plan == T.must(copilot_business).copilot_plan
    end
  end
end
