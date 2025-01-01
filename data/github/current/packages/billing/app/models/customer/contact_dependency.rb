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

    private

    sig { void }
    def rescreen_on_pii_update
      billing_contact.rescreen_on_pii_update(changed_attributes: saved_changes.slice("vat_code"))
    end
  end

  sig { returns(Billing::Contact) }
  def billing_contact
    billable_owner = self.billable_owner
    linked_billing_contact = T.let(billable_owner.try(:linked_billing_contact), T.nilable(Billing::Contact))
    return linked_billing_contact if linked_billing_contact.present?

    super || build_billing_contact
  end

  sig { returns(Billing::Contact) }
  def shipping_contact
    super || build_shipping_contact
  end
end
