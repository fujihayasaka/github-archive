# typed: strict
# frozen_string_literal: true

module Customer::ContactDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Customer }

  included do
    T.bind(self, T.class_of(Customer))

    has_many :contacts, class_name: "Billing::Contact", dependent: :destroy
    has_one :billing_contact, -> { where address_type: :billing }, class_name: "Billing::Contact", autosave: false
    has_one :shipping_contact, -> { where address_type: :shipping }, class_name: "Billing::Contact", autosave: false
  end

  sig { returns(Billing::Contact) }
  def billing_contact
    return linked_billing_contact if billable_owner&.org_is_on_standard_tos?

    super || build_billing_contact
  end

  sig { returns(Billing::Contact) }
  def shipping_contact
    super || build_shipping_contact
  end

  private

  # Returns the linked billing contact if the billable owner is an org
  # otherwise returns the billing contact associated with this customer
  sig { returns(Billing::Contact) }
  def linked_billing_contact
    return T.must(@linked_billing_contact) if defined?(@linked_billing_contact)
    billable_owner = self.billable_owner
    is_an_org = billable_owner&.is_a?(Organization) && billable_owner.organization?
    return @linked_billing_contact = billing_contact unless is_an_org

    @linked_billing_contact = T.let(nil, T.nilable(Billing::Contact))
    @linked_billing_contact = Billing::ContactLinkManager.linked_org_contact(address_type: :billing, org: billable_owner)
  end
end
