# typed: strict
# frozen_string_literal: true

module Billing::ContactDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  requires_ancestor { Customer }

  included do
    T.bind(self, T.class_of(Customer))

    has_many :contacts, class_name: "Billing::Contact", dependent: :destroy
    has_one :billing_contact, -> { where address_type: :billing }, class_name: "Billing::Contact"
    has_one :shipping_contact, -> { where address_type: :shipping }, class_name: "Billing::Contact"
  end

  sig { returns(Billing::Contact) }
  def billing_contact
    return self.linked_billing_contact if self.org_is_on_standard_tos?

    super || build_billing_contact
  end

  # Checks if the org on Standard Terms of Service has a linked billing contact
  sig { returns(T::Boolean) }
  def has_linked_billing_contact?
    return T.must(@has_linked_billing_contact) if defined?(@has_linked_billing_contact)
    return @has_linked_billing_contact = false unless self.org_is_on_standard_tos?

    @has_linked_billing_contact = T.let(nil, T.nilable(T::Boolean))
    @has_linked_billing_contact = Billing::ContactLinkManager.org_has_linked_contact?(address_type: :billing, org: T.cast(self, Organization))
  end

  private

  sig { returns(T::Boolean) }
  def org_is_on_standard_tos?
    return T.must(@org_is_on_standard_tos) if defined?(@org_is_on_standard_tos)

    @org_is_on_standard_tos = T.let(false, T.nilable(T::Boolean))
    @org_is_on_standard_tos = billable_owner&.org_is_on_standard_tos? || false
  end

  # Returns the linked billing contact if this is a Standard Terms of Service org
  # otherwise returns the billing contact associated with this customer
  sig { returns(Billing::Contact) }
  def linked_billing_contact
    return T.must(@linked_billing_contact) if defined?(@linked_billing_contact)
    return @linked_billing_contact = self.billing_contact unless self.org_is_on_standard_tos?

    @linked_billing_contact = T.let(nil, T.nilable(Billing::Contact))
    @linked_billing_contact = Billing::ContactLinkManager.linked_org_contact(address_type: :billing, org: T.cast(self.billable_owner, Organization))
  end
end
