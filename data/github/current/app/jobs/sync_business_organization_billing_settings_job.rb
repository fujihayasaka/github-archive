# typed: strict
# frozen_string_literal: true

class SyncBusinessOrganizationBillingSettingsJob < BillingJob

  queue_as :billing

  retry_on GitHub::Restraint::UnableToLock, wait: 1.minute, attempts: 5 do |_job, error|
    Failbot.report(error)
  end

  sig { params(business: T.nilable(Business), enterprise_purchase: T::Boolean, switch_org_billing_to_invoice: T::Boolean).void }
  def perform(business, enterprise_purchase: false, switch_org_billing_to_invoice: false)
    return unless GitHub.billing_enabled?
    return unless business

    business.organizations.each do |org|
      lock!(business, org) do
        with_write do
          # capture the org's billing date prior to conversion so we can re-activate sponsorships without billing
          # immediately
          org_next_billing_date = org[:billed_on]
          business.sync_organization_billing_settings(org)

          if enterprise_purchase
            business.transfer_marketplace_purchases_from_org_to_business(org, actor)  # Transfer marketplace items on successful GitHub Enterprise purchase
            if GitHub.sponsors_enabled?
              # if the upgrade occurs on first payment, we currently don't have access to an actor. In that case,
              # assume the first owner is the actor since they're the one who upgraded the org to a business.
              initiating_owner = actor.ghost? ? business.owners.first : actor
              business.transfer_sponsors_purchases_from_org_to_business(org, initiating_owner,
                bill_on: org_next_billing_date
              )
            end

            # When GitHub Enterprise is purchased, either through upgrading an EA trial or through upgrading an org to
            # an EA, this logic is used to update the org's billing type to match that of the EA.
            if switch_org_billing_to_invoice
              org.switch_billing_type_to_invoice(actor)
            else
              org.cancel_billing
              ::Billing::PaymentMethodRemovalJob.perform_later(user: org, actor: actor)
            end
          elsif business.billing_type != org.billing_type
            # When an existing EA wants to change its billing type (GitHub Enterprise is not being purchased), this
            # logic is used to update the org's billing type to match that of the EA.
            if business.invoiced?
              org.switch_billing_type_to_invoice(actor)
            else
              org.switch_billing_type_to_card(actor)
            end
          end
        end
      end
    end
  end

  private

  sig { returns(GitHub::Restraint) }
  def restraint
    @restraint ||= T.let(GitHub::Restraint.new, T.nilable(GitHub::Restraint))
  end

  sig { params(business: Business, organization: Organization, block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def lock!(business, organization, &block)
    lock_key = business.business_organization_billing_sync_key(organization)
    restraint.lock!(lock_key, _max_concurrency = 1, _ttl = 1.minute) do
      yield
    end
  end

  sig { returns(User) }
  def actor
    @actor ||= T.let((User.find_by(id: GitHub.context[:actor_id]) || User.ghost), T.nilable(User))
  end
end
