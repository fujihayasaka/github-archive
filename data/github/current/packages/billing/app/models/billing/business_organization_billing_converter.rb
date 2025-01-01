# typed: strict
# frozen_string_literal: true

class Billing::BusinessOrganizationBillingConverter


  sig { params(business: Business, organization: Organization).void }
  def self.perform(business:, organization:)
    new(business: business, organization: organization).perform
  end

  sig { params(business: Business, organization: Organization).void }
  def initialize(business:, organization:)
    @business = business
    @organization = organization
    @old_org_billing_type = T.let(organization.billing_type, T.nilable(String))
  end

  sig { void }
  def perform
    update_organization_billing_data
    log_change_billing_type
  end

  private

  sig { returns(User) }
  def actor
    @actor ||= T.let((User.find_by(id: GitHub.context[:actor_id]) || User.ghost), T.nilable(User))
  end

  sig { void }
  def update_organization_billing_data
    organization.skip_admins_presence_validation = true
    if business.invoiced?
      organization.switch_billing_type_to_invoice(actor)
    else
      organization.update!(billing_type: User::BillingDependency::CARD_BILLING_TYPE)

      if should_close_out_billing?
        organization.cancel_billing unless organization.plan_subscription&.business.present?
        organization.incomplete_pending_plan_changes.each(&:cancel)
        ::Billing::PaymentMethodRemovalJob.perform_later(user: organization, actor: actor)
      end
    end

    organization.enable!
    business.sync_organization_billing_settings(organization)
  end

  sig { void }
  def log_change_billing_type
    return if old_org_billing_type == organization.billing_type

    GitHub.instrument("billing.change_billing_type",
         old_billing_type: old_org_billing_type,
         billing_type: organization.billing_type,
         user: organization,
         actor: actor,
         actor_id: actor.id)
  end

  sig { returns(T::Boolean) }
  def should_close_out_billing?
    return true if organization.disabled?
    !business.trial?
  end

  sig { returns(Business) }
  attr_reader :business

  sig { returns(Organization) }
  attr_reader :organization

  sig { returns(T.nilable(String)) }
  attr_reader :old_org_billing_type
end
