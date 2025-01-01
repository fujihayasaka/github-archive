# typed: strict
# frozen_string_literal: true

class User
  class InvoiceConverter

    sig { params(target: User).void }
    def initialize(target)
      @target = target
    end

    # Public: Determines if target user/organization can be converted to
    # invoice billing.
    #
    # If an organization is owned by a business its `invoiced?` method will
    # always return true. This means we have to check business owned
    # organization's `billing_type` value directly to determine if it has
    # already been migrated to invoice billing or not.
    sig { returns(T::Boolean) }
    def convertable?
      !target.invoiced? || needs_business_billing_migration?
    end

    # Public: Switches target user/organization to invoice billing
    sig { params(actor: User).returns(T::Boolean) }
    def convert(actor:)
      return false unless convertable?

      target.cancel_billing

      ::Billing::PaymentMethodRemovalJob.perform_later \
        user: target,
        actor: actor

      Organization.transaction do
        target.update!(billing_type: User::BillingDependency::INVOICE_BILLING_TYPE, billing_attempts: 0, plan_duration: User::BillingDependency::YEARLY_PLAN).tap do
          instrument(actor: actor)
          deactivate_trial
        end
      end
    end

    private

    sig { returns(User) }
    attr_reader :target

    # Private: This instrument call sends data to Hydro. There is a similar
    # instrumentation in StaffTools::UsersController#pay_by_invoice
    # that logs to the Audit Log, but can't be used with Hydro
    sig { params(actor: User).void }
    def instrument(actor:)
      GlobalInstrumenter.instrument(
        "billing.change_billing_type",
        old_billing_type: target.attribute_before_last_save(:billing_type),
        billing_type: target.billing_type,
        user: target,
        actor: actor,
      )
    end

    # Private: Returns whether or not the current organization needs to have
    # the switch_billing_type_to_invoice code run when owned by a business.
    sig { returns(T::Boolean) }
    def needs_business_billing_migration?
      return false if !target.organization?
      return false if target.business.nil?

      # invoiced? always returns true when owned by a business so we check the
      # billing type manually to see if a migration is necessary
      target.billing_type != User::BillingDependency::INVOICE_BILLING_TYPE
    end

    # Private: Deactivates an Enterprise Cloud trial if one exists and is
    # active. Because the billing is now managed by sales we shouldn't run the
    # pending_plan_change and their terms should go back to CToS
    sig { void }
    def deactivate_trial
      trial = Billing::EnterpriseCloudTrial.new(target)

      if trial.active?
        trial.deactivate!
      end
    end
  end
end
